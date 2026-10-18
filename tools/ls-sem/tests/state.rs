use std::collections::BTreeSet;

use ls_sem::{demo_bad, selftest, AliasOccurrence, Mode, Place, Sigma};

#[test]
fn bad_recover_reports_s_holder() {
    let demo = demo_bad();
    assert!(!demo.accepted);
    let s = Place::var("s");
    let b = 0;
    assert!(demo.aliases.contains(&AliasOccurrence { place: s, b }));
}

#[test]
fn recover_succeeds_when_only_holder_is_consumed() {
    let mut sigma = Sigma::new();
    let x = Place::var("x");
    let v = Place::var("v");
    sigma.bind_var("x", "Int", Mode::Uniq, "local");
    let b = sigma.freeze(&x, "local").unwrap();
    sigma.bind_var("v", "val[Int]", Mode::Frozen, "local");
    sigma.bind_aliases(&v, &BTreeSet::from([b]));

    sigma
        .recover(&x, Some(&v), &BTreeSet::from([b]))
        .expect("recover should succeed");
    assert_eq!(sigma.mode_of(&x), Some(Mode::Uniq));
    assert!(sigma.aliases_star(&x).is_empty());
}

#[test]
fn move_transfers_h_and_marks_root_moved() {
    let mut sigma = Sigma::new();
    let s = Place::var("s");
    let b = sigma.fresh_bid();
    sigma.bind_var("s", "S", Mode::Uniq, "local");
    sigma.bind_aliases(&s, &BTreeSet::from([b]));
    let moved = sigma.move_place(&s);
    assert_eq!(moved, BTreeSet::from([b]));
    assert!(sigma.is_moved(&s));
    assert!(sigma.h_star(&s).is_empty());
}

#[test]
fn consumed_between_reports_removed_occurrences() {
    let mut before = Sigma::new();
    let s = Place::var("s");
    let b = before.fresh_bid();
    before.bind_var("s", "S", Mode::Uniq, "local");
    before.bind_aliases(&s, &BTreeSet::from([b]));

    let mut after = before.clone();
    after.drop_place(&s);
    let consumed = Sigma::consumed_between(&before, &after);
    assert!(consumed.contains(&AliasOccurrence { place: s, b }));
}

#[test]
fn selftest_passes() {
    selftest().expect("selftest");
}
