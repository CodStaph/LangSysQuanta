//! L-Sys semantic state skeleton.
//!
//! This is the first slice of `ls-sem`: Σ = (Γ, Λ, M, H), place paths,
//! alias occurrences, and the core operations needed by R1/R3/R4/R5.
//! It intentionally does not parse L-Sys source yet.

use std::collections::{BTreeMap, BTreeSet};
use std::fmt;

pub type Bid = u32;

/// Core ownership mode (`semantics.md` §2.1).
#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd, Hash)]
pub enum Mode {
    Uniq,
    Frozen,
    Mut,
    Atom,
    Raw,
    Copy,
}

impl fmt::Display for Mode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let s = match self {
            Mode::Uniq => "uniq",
            Mode::Frozen => "frozen",
            Mode::Mut => "mut",
            Mode::Atom => "atom",
            Mode::Raw => "raw",
            Mode::Copy => "copy",
        };
        f.write_str(s)
    }
}

/// Region name is opaque in the skeleton; the solver lands later.
#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd, Hash)]
pub struct Region(pub String);

impl From<&str> for Region {
    fn from(value: &str) -> Self {
        Region(value.to_string())
    }
}

impl From<String> for Region {
    fn from(value: String) -> Self {
        Region(value)
    }
}

/// Lexical region tree. A value may flow from an outer region into a nested
/// one, but never from a nested region into an ancestor or sibling.
#[derive(Clone, Debug, Default)]
pub struct RegionTree {
    parents: BTreeMap<Region, Option<Region>>,
}

impl RegionTree {
    pub fn add_root(&mut self, region: impl Into<String>) -> Result<Region, RegionError> {
        let region = Region(region.into());
        if self.parents.contains_key(&region) {
            return Err(RegionError::Duplicate(region));
        }
        self.parents.insert(region.clone(), None);
        Ok(region)
    }

    pub fn add_child(
        &mut self,
        region: impl Into<String>,
        parent: &Region,
    ) -> Result<Region, RegionError> {
        let region = Region(region.into());
        if self.parents.contains_key(&region) {
            return Err(RegionError::Duplicate(region));
        }
        if !self.parents.contains_key(parent) {
            return Err(RegionError::Unknown(parent.clone()));
        }
        self.parents.insert(region.clone(), Some(parent.clone()));
        Ok(region)
    }

    /// True when a value valid in `source` is also valid throughout `target`.
    pub fn outlives(&self, source: &Region, target: &Region) -> bool {
        let mut cursor = Some(target);
        while let Some(region) = cursor {
            if region == source {
                return true;
            }
            cursor = self.parents.get(region).and_then(Option::as_ref);
        }
        false
    }

    pub fn can_store(&self, value_region: &Region, destination_region: &Region) -> bool {
        self.outlives(value_region, destination_region)
    }

    /// Lowest common ancestor of two regions.  A value built from parts with
    /// different lifetimes is valid only in their common ancestor.
    pub fn common(&self, a: &Region, b: &Region) -> Option<Region> {
        let mut cursor = Some(a);
        while let Some(region) = cursor {
            if self.outlives(region, b) {
                return Some(region.clone());
            }
            cursor = self.parents.get(region).and_then(Option::as_ref);
        }
        None
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RegionError {
    Duplicate(Region),
    Unknown(Region),
}

/// Owning `Buffer<T>` metadata; elements are initialized in `[0, len)` and
/// capacity is reserved in the buffer's owning region.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Buffer<T> {
    pub elements: Vec<T>,
    pub capacity: usize,
    pub region: Region,
}

impl<T> Buffer<T> {
    pub fn with_capacity(capacity: usize, region: Region) -> Self {
        Self {
            elements: Vec::with_capacity(capacity),
            capacity,
            region,
        }
    }

    pub fn len(&self) -> usize {
        self.elements.len()
    }
    pub fn is_empty(&self) -> bool {
        self.elements.is_empty()
    }

    pub fn push(&mut self, value: T) -> Result<(), BufferFull> {
        if self.elements.len() == self.capacity {
            return Err(BufferFull {
                capacity: self.capacity,
            });
        }
        self.elements.push(value);
        Ok(())
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct BufferFull {
    pub capacity: usize,
}

#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd, Hash)]
pub enum PathSeg {
    Field(String),
    Index(String),
}

impl fmt::Display for PathSeg {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            PathSeg::Field(s) => write!(f, ".{}", s),
            PathSeg::Index(s) => write!(f, "[{}]", s),
        }
    }
}

/// A place is a root variable plus a field/index path.
#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd, Hash)]
pub struct Place {
    pub root: String,
    pub path: Vec<PathSeg>,
}

impl Place {
    pub fn var(root: impl Into<String>) -> Self {
        Self {
            root: root.into(),
            path: Vec::new(),
        }
    }

    pub fn field(&self, name: impl Into<String>) -> Self {
        let mut p = self.clone();
        p.path.push(PathSeg::Field(name.into()));
        p
    }

    pub fn index(&self, idx: impl Into<String>) -> Self {
        let mut p = self.clone();
        p.path.push(PathSeg::Index(idx.into()));
        p
    }

    /// `self` is `other` or a path prefix of `other`.
    pub fn is_prefix_of(&self, other: &Place) -> bool {
        self.root == other.root && other.path.starts_with(&self.path)
    }

    /// Same root and one path is a prefix of the other (semantics.md `overlap`).
    pub fn overlaps(&self, other: &Place) -> bool {
        self.is_prefix_of(other) || other.is_prefix_of(self)
    }

    pub fn root_place(&self) -> Place {
        Place::var(self.root.clone())
    }
}

impl fmt::Display for Place {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.root)?;
        for seg in &self.path {
            write!(f, "{}", seg)?;
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Binding {
    pub ty: String,
    pub mode: Mode,
    pub region: Region,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Borrow {
    pub b: Bid,
    pub place: Place,
    pub mode: Mode,
    pub scope: Region,
}

/// One alias occurrence `(q,b)` (semantics.md `Aliases*`).
#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd, Hash)]
pub struct AliasOccurrence {
    pub place: Place,
    pub b: Bid,
}

impl fmt::Display for AliasOccurrence {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "({},{})", self.place, self.b)
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RecoverError {
    pub target: Place,
    pub aliases: BTreeSet<AliasOccurrence>,
}

impl fmt::Display for RecoverError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let aliases = self
            .aliases
            .iter()
            .map(|a| a.to_string())
            .collect::<Vec<_>>()
            .join(", ");
        write!(
            f,
            "E-LS-UNIQ: recover({}) sees live aliases: {}",
            self.target, aliases
        )
    }
}

/// Σ = (Γ, Λ, M, H) from `semantics.md` §2.2.
#[derive(Clone, Debug, Default)]
pub struct Sigma {
    pub gamma: BTreeMap<String, Binding>,
    pub lambda: BTreeMap<Bid, Borrow>,
    pub moved: BTreeSet<Place>,
    pub h: BTreeMap<Place, BTreeSet<Bid>>,
    next_bid: Bid,
}

impl Sigma {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn fresh_bid(&mut self) -> Bid {
        let b = self.next_bid;
        self.next_bid += 1;
        b
    }

    pub fn bind_var(
        &mut self,
        name: impl Into<String>,
        ty: impl Into<String>,
        mode: Mode,
        region: impl Into<String>,
    ) {
        let name = name.into();
        self.moved.retain(|p| p.root != name);
        self.gamma.insert(
            name,
            Binding {
                ty: ty.into(),
                mode,
                region: Region(region.into()),
            },
        );
    }

    pub fn bind_aliases(&mut self, place: &Place, aliases: &BTreeSet<Bid>) {
        self.store(place, aliases);
    }

    pub fn mode_of(&self, place: &Place) -> Option<Mode> {
        self.gamma.get(&place.root).map(|b| b.mode)
    }

    pub fn set_mode(&mut self, place: &Place, mode: Mode) {
        if let Some(b) = self.gamma.get_mut(&place.root) {
            b.mode = mode;
        }
    }

    pub fn is_moved(&self, place: &Place) -> bool {
        self.moved.iter().any(|q| q.overlaps(place))
    }

    /// `live(Λ,p)`.
    pub fn live_aliases(&self, place: &Place) -> BTreeSet<Bid> {
        self.lambda
            .values()
            .filter(|borrow| borrow.place.overlaps(place))
            .map(|borrow| borrow.b)
            .collect()
    }

    /// `Holders(Σ,b)`.
    pub fn holders(&self, b: Bid) -> BTreeSet<Place> {
        self.h
            .iter()
            .filter(|(_, aliases)| aliases.contains(&b))
            .map(|(place, _)| place.clone())
            .collect()
    }

    /// `H*(Σ,p)`.
    pub fn h_star(&self, place: &Place) -> BTreeSet<Bid> {
        let mut out = BTreeSet::new();
        for (q, aliases) in &self.h {
            if place.is_prefix_of(q) {
                out.extend(aliases.iter().copied());
            }
        }
        out
    }

    /// `Aliases*(Σ,p)` as `(q,b)` occurrences.
    pub fn aliases_star(&self, place: &Place) -> BTreeSet<AliasOccurrence> {
        let mut out = BTreeSet::new();
        for b in self.live_aliases(place) {
            for q in self.holders(b) {
                out.insert(AliasOccurrence { place: q, b });
            }
        }
        out
    }

    /// `Consumed*(Σ,Σ')` occurrences.
    pub fn consumed_between(before: &Sigma, after: &Sigma) -> BTreeSet<AliasOccurrence> {
        let mut out = BTreeSet::new();
        for (place, aliases) in &before.h {
            for b in aliases {
                let still_there = after
                    .h
                    .get(place)
                    .map(|set| set.contains(b))
                    .unwrap_or(false);
                if !still_there {
                    out.insert(AliasOccurrence {
                        place: place.clone(),
                        b: *b,
                    });
                }
            }
        }
        out
    }

    /// Strong update: H(p) := aliases, clear descendants and old ancestor copies.
    pub fn store(&mut self, place: &Place, aliases: &BTreeSet<Bid>) {
        let old = self.h_star(place);
        let descendants: Vec<Place> = self
            .h
            .keys()
            .filter(|q| place.is_prefix_of(q))
            .cloned()
            .collect();
        for q in descendants {
            self.h.remove(&q);
        }
        if aliases.is_empty() {
            self.h.remove(place);
        } else {
            self.h.insert(place.clone(), aliases.clone());
        }
        // Parent places may have kept a coarse footprint of the old value.
        let ancestors: Vec<Place> = self
            .h
            .keys()
            .filter(|q| q.is_prefix_of(place) && *q != place)
            .cloned()
            .collect();
        for q in ancestors {
            if let Some(set) = self.h.get_mut(&q) {
                for b in &old {
                    set.remove(b);
                }
                if set.is_empty() {
                    self.h.remove(&q);
                }
            }
        }
        self.cleanup_borrows(&old);
    }

    /// R1-move: remove the source value, return its alias footprint.
    pub fn move_place(&mut self, place: &Place) -> BTreeSet<Bid> {
        let aliases = self.h_star(place);
        let descendants: Vec<Place> = self
            .h
            .keys()
            .filter(|q| place.is_prefix_of(q))
            .cloned()
            .collect();
        for q in descendants {
            self.h.remove(&q);
        }
        self.moved.insert(place.root_place());
        self.cleanup_borrows(&aliases);
        aliases
    }

    /// R1-drop: destroy the value at `place`.
    pub fn drop_place(&mut self, place: &Place) {
        let aliases = self.h_star(place);
        let descendants: Vec<Place> = self
            .h
            .keys()
            .filter(|q| place.is_prefix_of(q))
            .cloned()
            .collect();
        for q in descendants {
            self.h.remove(&q);
        }
        self.cleanup_borrows(&aliases);
    }

    /// R3-freeze: create `b`, make the root frozen.
    pub fn freeze(&mut self, place: &Place, scope: impl Into<String>) -> Option<Bid> {
        if !self.live_aliases(place).is_empty() {
            return None;
        }
        let b = self.fresh_bid();
        self.lambda.insert(
            b,
            Borrow {
                b,
                place: place.clone(),
                mode: Mode::Frozen,
                scope: Region(scope.into()),
            },
        );
        self.set_mode(place, Mode::Frozen);
        Some(b)
    }

    /// R3-read-Alias: create an in-flight `val(b)`.
    pub fn read_frozen(&mut self, place: &Place, scope: impl Into<String>) -> Bid {
        let b = self.fresh_bid();
        self.lambda.insert(
            b,
            Borrow {
                b,
                place: place.clone(),
                mode: Mode::Frozen,
                scope: Region(scope.into()),
            },
        );
        b
    }

    /// `ConsumeResult`: consume the block result and drop its holders.
    pub fn consume_result(&mut self, result_place: Option<&Place>, aliases: &BTreeSet<Bid>) {
        if let Some(q) = result_place {
            self.store(q, &BTreeSet::new());
        }
        for b in aliases {
            if self.holders(*b).is_empty() {
                self.lambda.remove(b);
            }
        }
    }

    /// R3-recover: after consuming the result, `Aliases*(Σ_c,p)` must be empty.
    pub fn recover(
        &mut self,
        target: &Place,
        result_place: Option<&Place>,
        result_aliases: &BTreeSet<Bid>,
    ) -> Result<(), RecoverError> {
        let mut next = self.clone();
        next.consume_result(result_place, result_aliases);
        let remaining = next.aliases_star(target);
        if !remaining.is_empty() {
            return Err(RecoverError {
                target: target.clone(),
                aliases: remaining,
            });
        }
        let live = next.live_aliases(target);
        for b in live {
            next.lambda.remove(&b);
        }
        next.set_mode(target, Mode::Uniq);
        next.h.remove(target);
        *self = next;
        Ok(())
    }

    /// R5-writable skeleton: no frozen/mut alias and not moved.
    pub fn writable(&self, place: &Place) -> bool {
        if self.is_moved(place) {
            return false;
        }
        let mode_ok = matches!(
            self.mode_of(place),
            Some(Mode::Uniq | Mode::Mut | Mode::Copy)
        );
        if !mode_ok {
            return false;
        }
        !self.aliases_star(place).iter().any(|occ| {
            self.lambda
                .get(&occ.b)
                .map(|b| matches!(b.mode, Mode::Frozen | Mode::Mut))
                .unwrap_or(false)
        })
    }

    fn cleanup_borrows(&mut self, aliases: &BTreeSet<Bid>) {
        for b in aliases {
            if self.holders(*b).is_empty() {
                self.lambda.remove(b);
            }
        }
    }
}

/// A small replay of `t4-proof.md` §3.5.3 `bad()`.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DemoResult {
    pub accepted: bool,
    pub aliases: BTreeSet<AliasOccurrence>,
    pub log: Vec<String>,
}

pub fn demo_bad() -> DemoResult {
    let mut sigma = Sigma::new();
    let x = Place::var("x");
    let v = Place::var("v");
    let s = Place::var("s");
    let mut log = Vec::new();

    sigma.bind_var("x", "Int", Mode::Uniq, "local");
    log.push("bind x: Int @ uniq".into());

    let b = sigma.freeze(&x, "local").expect("x is uniq");
    log.push(format!("freeze x -> b{}", b));

    sigma.bind_var("v", "val[Int]", Mode::Frozen, "local");
    sigma.bind_aliases(&v, &BTreeSet::from([b]));
    log.push(format!("let v = freeze x -> H(v)={{{}}}", b));

    sigma.bind_var("s", "S", Mode::Uniq, "local");
    sigma.bind_aliases(&s, &BTreeSet::from([b]));
    log.push(format!("let s = S {{ f: v }} -> H(s)={{{}}}", b));

    let result = sigma.recover(&x, Some(&v), &BTreeSet::from([b]));
    match result {
        Ok(()) => DemoResult {
            accepted: true,
            aliases: BTreeSet::new(),
            log,
        },
        Err(err) => {
            log.push(err.to_string());
            DemoResult {
                accepted: false,
                aliases: err.aliases,
                log,
            }
        }
    }
}

/// Tiny self-check used by `ls-sem selftest`.
pub fn selftest() -> Result<(), String> {
    let demo = demo_bad();
    if demo.accepted {
        return Err("bad() was accepted".into());
    }
    if demo.aliases.is_empty() {
        return Err("bad() did not report alias occurrences".into());
    }

    // A successful recover: only keeper v holds b.
    let mut sigma = Sigma::new();
    let x = Place::var("x");
    let v = Place::var("v");
    sigma.bind_var("x", "Int", Mode::Uniq, "local");
    let b = sigma.freeze(&x, "local").unwrap();
    sigma.bind_var("v", "val[Int]", Mode::Frozen, "local");
    sigma.bind_aliases(&v, &BTreeSet::from([b]));
    sigma
        .recover(&x, Some(&v), &BTreeSet::from([b]))
        .map_err(|e| e.to_string())?;

    // Strong store at the root clears the old footprint.
    let mut sigma = Sigma::new();
    let s = Place::var("s");
    let b = sigma.fresh_bid();
    sigma.lambda.insert(
        b,
        Borrow {
            b,
            place: s.clone(),
            mode: Mode::Frozen,
            scope: Region("local".into()),
        },
    );
    sigma.store(&s, &BTreeSet::from([b]));
    sigma.store(&s, &BTreeSet::new());
    if sigma.h_star(&s).contains(&b) {
        return Err("strong update did not clear the old alias footprint".into());
    }
    Ok(())
}
