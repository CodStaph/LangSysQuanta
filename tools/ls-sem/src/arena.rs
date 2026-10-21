//! Arena allocation with an explicit budget and scoped reclamation.
//!
//! The arena is a deterministic bump allocator model.  Allocation never aborts
//! and never panics: it returns `Result<Allocation, AllocError>` so callers can
//! propagate failure through `Result`.  `mark`/`reset_to` implement LIFO
//! reclamation (one mark per `region` scope); `reset` reclaims everything.

use std::fmt;

/// Logical byte offset inside the arena.
pub type Offset = usize;

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum AllocError {
    /// The request does not fit in the remaining budget.
    BudgetExceeded {
        requested: usize,
        remaining: usize,
        budget: usize,
    },
    /// Alignment is not a power of two, or size/alignment arithmetic overflowed.
    BadLayout { size: usize, align: usize },
}

impl fmt::Display for AllocError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            AllocError::BudgetExceeded {
                requested,
                remaining,
                budget,
            } => write!(
                f,
                "E-LS-ALLOC: arena budget exceeded (requested {}, remaining {}, budget {})",
                requested, remaining, budget
            ),
            AllocError::BadLayout { size, align } => {
                write!(f, "E-LS-ALLOC: bad layout (size {}, align {})", size, align)
            }
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Allocation {
    pub offset: Offset,
    pub size: usize,
    pub align: usize,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ArenaReport {
    pub budget: usize,
    pub used: usize,
    pub high_water: usize,
    pub allocations: usize,
    pub rejections: usize,
    pub reclamations: usize,
}

/// Deterministic bump arena.  `used` only moves forward on allocation and
/// backwards through `reset_to`; the model intentionally keeps no heap bytes.
#[derive(Clone, Debug)]
pub struct Arena {
    budget: usize,
    used: usize,
    high_water: usize,
    allocations: usize,
    rejections: usize,
    reclamations: usize,
}

impl Arena {
    pub fn new(budget: usize) -> Self {
        Self {
            budget,
            used: 0,
            high_water: 0,
            allocations: 0,
            rejections: 0,
            reclamations: 0,
        }
    }

    pub fn budget(&self) -> usize {
        self.budget
    }

    pub fn used(&self) -> usize {
        self.used
    }

    pub fn remaining(&self) -> usize {
        self.budget - self.used
    }

    pub fn high_water(&self) -> usize {
        self.high_water
    }

    pub fn report(&self) -> ArenaReport {
        ArenaReport {
            budget: self.budget,
            used: self.used,
            high_water: self.high_water,
            allocations: self.allocations,
            rejections: self.rejections,
            reclamations: self.reclamations,
        }
    }

    /// Record a reclaim point.  The returned token can be passed to
    /// [`Arena::reset_to`].
    pub fn mark(&self) -> Offset {
        self.used
    }

    /// Allocate `size` bytes with `align` alignment, or fail without changing
    /// the arena.
    pub fn alloc(&mut self, size: usize, align: usize) -> Result<Allocation, AllocError> {
        if align == 0 || !align.is_power_of_two() {
            return Err(AllocError::BadLayout { size, align });
        }
        let Some(offset) = align_up(self.used, align) else {
            return Err(AllocError::BadLayout { size, align });
        };
        let Some(end) = offset.checked_add(size) else {
            return Err(AllocError::BadLayout { size, align });
        };
        if end > self.budget {
            self.rejections += 1;
            return Err(AllocError::BudgetExceeded {
                requested: size,
                remaining: self.remaining(),
                budget: self.budget,
            });
        }
        self.used = end;
        self.high_water = self.high_water.max(end);
        self.allocations += 1;
        Ok(Allocation {
            offset,
            size,
            align,
        })
    }

    /// Allocate `count * elem_size` bytes, failing on overflow or budget
    /// exhaustion.  This is the shape used by `Buffer<T>` backing storage.
    pub fn alloc_elems(
        &mut self,
        count: usize,
        elem_size: usize,
        align: usize,
    ) -> Result<Allocation, AllocError> {
        match count.checked_mul(elem_size) {
            Some(size) => self.alloc(size, align),
            None => Err(AllocError::BadLayout {
                size: usize::MAX,
                align,
            }),
        }
    }

    /// Reclaim every allocation at or after `mark`.  Returns the number of
    /// bytes reclaimed.  A mark newer than `used` is rejected.
    pub fn reset_to(&mut self, mark: Offset) -> Result<usize, AllocError> {
        if mark > self.used {
            self.rejections += 1;
            return Err(AllocError::BudgetExceeded {
                requested: mark,
                remaining: self.used,
                budget: self.budget,
            });
        }
        let reclaimed = self.used - mark;
        self.used = mark;
        if reclaimed > 0 {
            self.reclamations += 1;
        }
        Ok(reclaimed)
    }

    /// Reclaim the whole arena.
    pub fn reset(&mut self) -> usize {
        let reclaimed = self.used;
        self.used = 0;
        if reclaimed > 0 {
            self.reclamations += 1;
        }
        reclaimed
    }

    /// Grow the budget.  Used for host-configured limits; shrinking is
    /// rejected so live allocations are never invalidated.
    pub fn set_budget(&mut self, budget: usize) -> Result<(), AllocError> {
        if budget < self.used {
            return Err(AllocError::BudgetExceeded {
                requested: self.used,
                remaining: 0,
                budget,
            });
        }
        self.budget = budget;
        Ok(())
    }
}

fn align_up(value: usize, align: usize) -> Option<usize> {
    let mask = align - 1;
    value.checked_add(mask).map(|v| v & !mask)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allocation_aligns_and_accounts() {
        let mut arena = Arena::new(64);
        let a = arena.alloc(1, 1).unwrap();
        let b = arena.alloc(8, 8).unwrap();
        assert_eq!(a.offset, 0);
        assert_eq!(b.offset, 8);
        assert_eq!(arena.used(), 16);
        assert_eq!(arena.high_water(), 16);
    }

    #[test]
    fn exhaustion_does_not_move_used() {
        let mut arena = Arena::new(8);
        arena.alloc(8, 1).unwrap();
        let err = arena.alloc(1, 1).unwrap_err();
        assert!(matches!(err, AllocError::BudgetExceeded { .. }));
        assert_eq!(arena.used(), 8);
        assert_eq!(arena.report().rejections, 1);
    }

    #[test]
    fn scoped_reset_reclaims_lifo() {
        let mut arena = Arena::new(64);
        arena.alloc(8, 1).unwrap();
        let mark = arena.mark();
        arena.alloc(16, 1).unwrap();
        assert_eq!(arena.reset_to(mark).unwrap(), 16);
        assert_eq!(arena.used(), 8);
        assert_eq!(arena.reset(), 8);
        assert_eq!(arena.used(), 0);
    }

    #[test]
    fn overflowing_element_count_is_rejected() {
        let mut arena = Arena::new(64);
        assert!(matches!(
            arena.alloc_elems(usize::MAX, 2, 8),
            Err(AllocError::BadLayout { .. })
        ));
        assert_eq!(arena.used(), 0);
    }
}
