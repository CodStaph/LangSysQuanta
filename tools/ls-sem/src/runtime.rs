//! Runtime slice bounds and lifetime checks.
//!
//! This is the executable counterpart to the static `Buffer.slice` rules in
//! `surface.rs`.  Values are indexed by handles, not raw pointers:
//!
//! * a `RuntimeSlice` remembers its owning `RuntimeBuffer` and generation;
//! * every access re-checks that the owner is still live;
//! * every slice access checks `index < slice.len` and the slice range;
//! * releasing a buffer or its region invalidates all existing slices through
//!   generation mismatch, so use-after-free is reported instead of UB.
//!
//! No `unsafe` is used; this is a deterministic model for tests and for the
//! eventual runtime lowering.

use std::fmt;

use crate::state::Region;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd, Hash)]
pub struct RuntimeBuffer {
    index: usize,
    generation: u64,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd, Hash)]
pub struct RuntimeSlice {
    buffer: RuntimeBuffer,
    start: usize,
    len: usize,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RuntimeError {
    UseAfterFree,
    OutOfBounds {
        start: usize,
        len: usize,
        capacity: usize,
    },
    CapacityFull {
        capacity: usize,
    },
    InvalidRegion(Region),
}

impl fmt::Display for RuntimeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            RuntimeError::UseAfterFree => f.write_str("E-LS-SLICE: buffer is no longer live"),
            RuntimeError::OutOfBounds {
                start,
                len,
                capacity,
            } => write!(
                f,
                "E-LS-SLICE: range [{}, {}) exceeds live buffer length {}",
                start,
                start.saturating_add(*len),
                capacity
            ),
            RuntimeError::CapacityFull { capacity } => {
                write!(f, "E-LS-SLICE: buffer capacity {} is full", capacity)
            }
            RuntimeError::InvalidRegion(region) => {
                write!(f, "E-LS-SLICE: unknown region {:?}", region)
            }
        }
    }
}

#[derive(Clone, Debug)]
struct BufferCell<T> {
    elements: Vec<T>,
    capacity: usize,
    generation: u64,
    region: Region,
}

/// Handle-based runtime arena with generations.
#[derive(Clone, Debug)]
pub struct RuntimeArena<T> {
    slots: Vec<Option<BufferCell<T>>>,
    generations: Vec<u64>,
    next_serial: u64,
}

impl<T> Default for RuntimeArena<T> {
    fn default() -> Self {
        Self::new()
    }
}

impl<T> RuntimeArena<T> {
    pub fn new() -> Self {
        Self {
            slots: Vec::new(),
            generations: Vec::new(),
            next_serial: 0,
        }
    }

    pub fn alloc(&mut self, capacity: usize, region: impl Into<Region>) -> RuntimeBuffer {
        let region = region.into();
        self.next_serial = self.next_serial.wrapping_add(1);
        let serial = self.next_serial;
        for index in 0..self.slots.len() {
            if self.slots[index].is_none() {
                let generation = self.generations[index].wrapping_add(1).max(1);
                self.generations[index] = generation;
                self.slots[index] = Some(BufferCell {
                    elements: Vec::with_capacity(capacity),
                    capacity,
                    generation,
                    region,
                });
                return RuntimeBuffer { index, generation };
            }
        }
        let index = self.slots.len();
        let generation = serial.max(1);
        self.generations.push(generation);
        self.slots.push(Some(BufferCell {
            elements: Vec::with_capacity(capacity),
            capacity,
            generation,
            region,
        }));
        RuntimeBuffer { index, generation }
    }

    fn live(&self, handle: RuntimeBuffer) -> Option<&BufferCell<T>> {
        let cell = self.slots.get(handle.index)?.as_ref()?;
        if cell.generation != handle.generation {
            return None;
        }
        Some(cell)
    }

    fn live_mut(&mut self, handle: RuntimeBuffer) -> Option<&mut BufferCell<T>> {
        let cell = self.slots.get_mut(handle.index)?.as_mut()?;
        if cell.generation != handle.generation {
            return None;
        }
        Some(cell)
    }

    pub fn len(&self, handle: RuntimeBuffer) -> Result<usize, RuntimeError> {
        self.live(handle)
            .map(|cell| cell.elements.len())
            .ok_or(RuntimeError::UseAfterFree)
    }

    pub fn capacity(&self, handle: RuntimeBuffer) -> Result<usize, RuntimeError> {
        self.live(handle)
            .map(|cell| cell.capacity)
            .ok_or(RuntimeError::UseAfterFree)
    }

    pub fn push(&mut self, handle: RuntimeBuffer, value: T) -> Result<(), RuntimeError> {
        let cell = self.live_mut(handle).ok_or(RuntimeError::UseAfterFree)?;
        if cell.elements.len() == cell.capacity {
            return Err(RuntimeError::CapacityFull {
                capacity: cell.capacity,
            });
        }
        cell.elements.push(value);
        Ok(())
    }

    /// Create a checked view.  Bounds are checked against the *current* live
    /// length, not merely the reserved capacity.
    pub fn slice(
        &self,
        handle: RuntimeBuffer,
        start: usize,
        len: usize,
    ) -> Result<RuntimeSlice, RuntimeError> {
        let cell = self.live(handle).ok_or(RuntimeError::UseAfterFree)?;
        let end = start.checked_add(len).ok_or(RuntimeError::OutOfBounds {
            start,
            len,
            capacity: cell.elements.len(),
        })?;
        if end > cell.elements.len() {
            return Err(RuntimeError::OutOfBounds {
                start,
                len,
                capacity: cell.elements.len(),
            });
        }
        Ok(RuntimeSlice {
            buffer: handle,
            start,
            len,
        })
    }

    fn checked_index(&self, slice: RuntimeSlice, index: usize) -> Result<usize, RuntimeError> {
        let cell = self.live(slice.buffer).ok_or(RuntimeError::UseAfterFree)?;
        if index >= slice.len {
            return Err(RuntimeError::OutOfBounds {
                start: slice.start,
                len: slice.len,
                capacity: cell.elements.len(),
            });
        }
        let absolute = slice.start + index;
        let end = slice
            .start
            .checked_add(slice.len)
            .ok_or(RuntimeError::OutOfBounds {
                start: slice.start,
                len: slice.len,
                capacity: cell.elements.len(),
            })?;
        if end > cell.elements.len() {
            return Err(RuntimeError::OutOfBounds {
                start: slice.start,
                len: slice.len,
                capacity: cell.elements.len(),
            });
        }
        Ok(absolute)
    }

    pub fn read(&self, slice: RuntimeSlice, index: usize) -> Result<&T, RuntimeError> {
        let absolute = self.checked_index(slice, index)?;
        self.live(slice.buffer)
            .and_then(|cell| cell.elements.get(absolute))
            .ok_or(RuntimeError::UseAfterFree)
    }

    pub fn write(
        &mut self,
        slice: RuntimeSlice,
        index: usize,
        value: T,
    ) -> Result<(), RuntimeError> {
        let absolute = self.checked_index(slice, index)?;
        let cell = self
            .live_mut(slice.buffer)
            .ok_or(RuntimeError::UseAfterFree)?;
        let slot = cell
            .elements
            .get_mut(absolute)
            .ok_or(RuntimeError::UseAfterFree)?;
        *slot = value;
        Ok(())
    }

    pub fn slice_len(slice: RuntimeSlice) -> usize {
        slice.len
    }

    pub fn slice_start(slice: RuntimeSlice) -> usize {
        slice.start
    }

    pub fn release(&mut self, handle: RuntimeBuffer) -> Result<(), RuntimeError> {
        if !self.live(handle).is_some() {
            return Err(RuntimeError::UseAfterFree);
        }
        self.slots[handle.index] = None;
        Ok(())
    }

    /// Release every live buffer owned by `region`.  Existing handles and
    /// slices become invalid via generation/liveness checks.
    pub fn release_region(&mut self, region: &Region) -> Result<usize, RuntimeError> {
        let mut released = 0;
        let mut targets = Vec::new();
        for (index, slot) in self.slots.iter().enumerate() {
            if let Some(cell) = slot {
                if &cell.region == region {
                    targets.push(index);
                }
            }
        }
        for index in targets {
            self.slots[index] = None;
            released += 1;
        }
        Ok(released)
    }

    pub fn live_buffer_count(&self) -> usize {
        self.slots.iter().filter(|slot| slot.is_some()).count()
    }
}

pub fn selftest() -> Result<(), String> {
    let region = Region("frame".to_string());
    let mut arena = RuntimeArena::<i32>::new();
    let buffer = arena.alloc(4, region.clone());
    arena.push(buffer, 10).map_err(|e| e.to_string())?;
    arena.push(buffer, 20).map_err(|e| e.to_string())?;
    arena.push(buffer, 30).map_err(|e| e.to_string())?;

    let view = arena.slice(buffer, 1, 2).map_err(|e| e.to_string())?;
    if arena.read(view, 0).map_err(|e| e.to_string())? != &20 {
        return Err("slice start mismatch".to_string());
    }
    if arena.read(view, 1).map_err(|e| e.to_string())? != &30 {
        return Err("slice element mismatch".to_string());
    }
    if arena.read(view, 2).is_ok() {
        return Err("out-of-range slice read was accepted".to_string());
    }
    arena.write(view, 0, 21).map_err(|e| e.to_string())?;
    if arena.read(view, 0).map_err(|e| e.to_string())? != &21 {
        return Err("slice write did not persist".to_string());
    }
    if arena.slice(buffer, 2, 2).is_ok() {
        return Err("out-of-range slice was accepted".to_string());
    }

    arena.release(buffer).map_err(|e| e.to_string())?;
    if arena.read(view, 0).is_ok() {
        return Err("use-after-free slice read was accepted".to_string());
    }
    if arena.slice(buffer, 0, 0).is_ok() {
        return Err("slice of released buffer was accepted".to_string());
    }

    let region_buffer = arena.alloc(2, region.clone());
    let region_view = arena
        .slice(region_buffer, 0, 0)
        .map_err(|e| e.to_string())?;
    if arena.release_region(&region).map_err(|e| e.to_string())? != 1 {
        return Err("region release count mismatch".to_string());
    }
    if arena.read(region_view, 0).is_ok() {
        return Err("slice after region release was accepted".to_string());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slice_bounds_are_runtime_checked() {
        let mut arena = RuntimeArena::<i32>::new();
        let b = arena.alloc(4, "r");
        for v in [1, 2, 3] {
            arena.push(b, v).unwrap();
        }
        let s = arena.slice(b, 1, 2).unwrap();
        assert_eq!(arena.read(s, 0), Ok(&2));
        assert_eq!(arena.read(s, 1), Ok(&3));
        assert!(matches!(
            arena.read(s, 2),
            Err(RuntimeError::OutOfBounds { .. })
        ));
        assert!(matches!(
            arena.slice(b, 2, 2),
            Err(RuntimeError::OutOfBounds { .. })
        ));
    }

    #[test]
    fn release_invalidates_slices() {
        let mut arena = RuntimeArena::<i32>::new();
        let b = arena.alloc(2, "r");
        arena.push(b, 7).unwrap();
        let s = arena.slice(b, 0, 1).unwrap();
        arena.release(b).unwrap();
        assert_eq!(arena.read(s, 0), Err(RuntimeError::UseAfterFree));
        assert_eq!(arena.slice(b, 0, 0), Err(RuntimeError::UseAfterFree));
    }

    #[test]
    fn region_release_invalidates_all_slices() {
        let mut arena = RuntimeArena::<i32>::new();
        let region = Region("scope".to_string());
        let b1 = arena.alloc(1, region.clone());
        let b2 = arena.alloc(1, region.clone());
        let other = arena.alloc(1, "other");
        let s1 = arena.slice(b1, 0, 0).unwrap();
        let s2 = arena.slice(b2, 0, 0).unwrap();
        assert_eq!(arena.release_region(&region), Ok(2));
        assert_eq!(arena.read(s1, 0), Err(RuntimeError::UseAfterFree));
        assert_eq!(arena.read(s2, 0), Err(RuntimeError::UseAfterFree));
        assert!(arena.len(other).is_ok());
    }
}
