//! Same commands in → same state and same responses out, and a snapshot taken
//! mid-stream then installed elsewhere converges to the same place.
//! TODO(app): extend `arb_command` when you add a command, so every arm is exercised.
use app::{Command, Fsm};
use proptest::prelude::*;
use uc_service::{ApplyCtx, SnapshotStateMachine, StateMachine};

fn arb_command() -> impl Strategy<Value = Command> {
    let key = prop::sample::select(vec!["a", "b", "c", "d"]).prop_map(String::from);
    prop_oneof![
        (key.clone(), "[a-z]{0,8}").prop_map(|(key, value)| Command::Put { key, value }),
        key.prop_map(|key| Command::Delete { key }),
    ]
}

fn pos(i: usize) -> u64 {
    32 * (i as u64 + 1)
}

fn projection(sm: &Fsm) -> String {
    let mut out = Vec::new();
    sm.project(&mut out).unwrap();
    String::from_utf8(out).unwrap()
}

proptest! {
    #[test]
    fn replicas_agree(cmds in prop::collection::vec(arb_command(), 0..64)) {
        let (mut a, mut b) = (Fsm::default(), Fsm::default());
        for (i, c) in cmds.iter().enumerate() {
            let ra = a.apply(&mut ApplyCtx::for_sm::<Fsm>(pos(i)), c.clone());
            let rb = b.apply(&mut ApplyCtx::for_sm::<Fsm>(pos(i)), c.clone());
            prop_assert_eq!(ra, rb);
        }
        prop_assert_eq!(projection(&a), projection(&b));
    }

    #[test]
    fn snapshot_then_continue_equals_uninterrupted(
        cmds in prop::collection::vec(arb_command(), 1..64),
        cut in 0usize..64,
    ) {
        let cut = cut % cmds.len();
        let mut whole = Fsm::default();
        for (i, c) in cmds.iter().enumerate() {
            whole.apply(&mut ApplyCtx::for_sm::<Fsm>(pos(i)), c.clone());
        }
        let mut first = Fsm::default();
        for (i, c) in cmds[..cut].iter().enumerate() {
            first.apply(&mut ApplyCtx::for_sm::<Fsm>(pos(i)), c.clone());
        }
        let (h, _) = first.freeze().unwrap();
        let mut img = Vec::new();
        Fsm::stream_snapshot(h, &mut img).unwrap();
        let mut restored = Fsm::default();
        restored.install_snapshot(pos(cut), &mut img.as_slice()).unwrap();
        for (i, c) in cmds.iter().enumerate().skip(cut) {
            restored.apply(&mut ApplyCtx::for_sm::<Fsm>(pos(i)), c.clone());
        }
        prop_assert_eq!(projection(&restored), projection(&whole));
    }
}
