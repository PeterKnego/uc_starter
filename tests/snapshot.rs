use app::{Command, Fsm};
use uc_service::{ApplyCtx, SnapshotStateMachine, StateMachine};

fn filled() -> Fsm {
    let mut sm = Fsm::default();
    for (i, k) in ["b", "a", "c"].iter().enumerate() {
        sm.apply(
            &mut ApplyCtx::for_sm::<Fsm>(32 * (i as u64 + 1)),
            Command::Put {
                key: (*k).into(),
                value: format!("v{i}"),
            },
        );
    }
    sm
}

fn image(sm: &Fsm) -> (Vec<u8>, u64) {
    let (h, pos) = sm.freeze().unwrap();
    let mut buf = Vec::new();
    Fsm::stream_snapshot(h, &mut buf).unwrap();
    (buf, pos)
}

#[test]
fn round_trip_restores_state_and_cursor() {
    let sm = filled();
    let (buf, pos) = image(&sm);
    assert_eq!(pos, 96);
    let mut back = Fsm::default();
    let got = back.install_snapshot(128, &mut buf.as_slice()).unwrap();
    assert_eq!(got, 128, "install returns the instant, not the cursor");
    assert_eq!(
        back.last_applied(),
        Some(96),
        "cursor restored from the image, strictly below P"
    );
    assert_eq!(back.state(), sm.state());
}

#[test]
fn install_refuses_unknown_image_version() {
    let (mut buf, _) = image(&filled());
    buf[0..4].copy_from_slice(&99u32.to_le_bytes());
    let mut sm = Fsm::default();
    let err = sm
        .install_snapshot(128, &mut buf.as_slice())
        .unwrap_err()
        .to_string();
    assert!(err.contains("image version 99"), "{err}");
    assert_eq!(
        sm.last_applied(),
        None,
        "a refused install leaves state untouched"
    );
}

#[test]
fn install_refuses_cursor_at_or_above_instant() {
    let (buf, _) = image(&filled()); // cursor 96
    let mut sm = Fsm::default();
    let err = sm
        .install_snapshot(96, &mut buf.as_slice())
        .unwrap_err()
        .to_string();
    assert!(err.contains("not below"), "{err}");
    assert!(sm.state().entries.is_empty());
}

#[test]
fn projection_is_sorted_and_quoted() {
    let mut out = Vec::new();
    filled().project(&mut out).unwrap();
    assert_eq!(
        String::from_utf8(out).unwrap(),
        "entry \"a\"=\"v1\"\nentry \"b\"=\"v0\"\nentry \"c\"=\"v2\"\n"
    );
}
