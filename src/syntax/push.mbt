///|
/// Receives pushed events. `on_enter` steers the traversal like a walk's
/// `enter`; both methods have defaults (`Continue`, nothing).
pub(open) trait Handler {
  fn on_enter(Self, EnterEvent) -> Control = _
  fn on_leave(Self, LeaveEvent) -> Unit = _
}

///|
impl Handler with fn on_enter(_self, _event) {
  Continue
}

///|
impl Handler with fn on_leave(_self, _event) {
  ()
}

///|
/// Pull every event from `source` and push it to `handler`: `on_enter` for
/// `Enter` (its `SkipChildren` skips the node's children, its `Stop` ends the
/// run) and `on_leave` for `Leave`.
pub fn[S : EventSource, H : Handler] push_events(
  source : S,
  handler : H,
) -> Unit {
  while source.next() is Some(event) {
    match event {
      Enter(e) =>
        match handler.on_enter(e) {
          Continue => ()
          SkipChildren => source.skip_children()
          Stop => return
        }
      Leave(e) => handler.on_leave(e)
    }
  }
}
