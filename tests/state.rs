use app::{Command, Fsm, Query, QueryResponse, Response};
use uc_service::{ApplyCtx, StateMachine};

fn ctx(p: u64) -> ApplyCtx {
    ApplyCtx::for_sm::<Fsm>(p)
}

fn put(k: &str, v: &str) -> Command {
    Command::Put { key: k.into(), value: v.into() }
}

#[test]
fn put_then_get() {
    let mut sm = Fsm::default();
    let r = sm.apply(&mut ctx(32), put("a", "1"));
    assert_eq!(r, Response::Put { previous: None });
    assert_eq!(sm.query(Query::Get { key: "a".into() }), QueryResponse::Value(Some("1".into())));
}

#[test]
fn put_overwrites_and_returns_previous() {
    let mut sm = Fsm::default();
    sm.apply(&mut ctx(32), put("a", "1"));
    let r = sm.apply(&mut ctx(64), put("a", "2"));
    assert_eq!(r, Response::Put { previous: Some("1".into()) });
}

#[test]
fn delete_returns_removed() {
    let mut sm = Fsm::default();
    sm.apply(&mut ctx(32), put("a", "1"));
    assert_eq!(sm.apply(&mut ctx(64), Command::Delete { key: "a".into() }), Response::Delete { removed: Some("1".into()) });
    assert_eq!(sm.apply(&mut ctx(96), Command::Delete { key: "a".into() }), Response::Delete { removed: None });
    assert_eq!(sm.query(Query::Get { key: "a".into() }), QueryResponse::Value(None));
}

#[test]
fn last_applied_tracks_position() {
    let mut sm = Fsm::default();
    assert_eq!(sm.last_applied(), None);
    sm.apply(&mut ctx(4096), put("a", "1"));
    assert_eq!(sm.last_applied(), Some(4096));
}

#[test]
fn validate_refuses_oversize() {
    let long_key = "k".repeat(app::MAX_KEY_LEN + 1);
    let long_val = "v".repeat(app::MAX_VALUE_LEN + 1);
    assert!(put(&long_key, "x").validate().is_err());
    assert!(put("k", &long_val).validate().is_err());
    assert!(Command::Delete { key: long_key }.validate().is_err());
    assert!(put("k", "v").validate().is_ok());
    // The largest valid command still fits the 1312 B crypto-on ceiling with
    // the 16 B session envelope in front of it.
    let max = put(&"k".repeat(app::MAX_KEY_LEN), &"v".repeat(app::MAX_VALUE_LEN));
    assert!(app::encode(&max).len() + 16 <= 1312);
}

#[test]
fn wire_round_trip() {
    let c = put("a", "1");
    let back: Command = app::decode(&app::encode(&c)).unwrap();
    assert_eq!(back, c);
}
