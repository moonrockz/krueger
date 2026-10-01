///|
/// Receives pushed events. `on_enter` steers the traversal like a walk's
/// `enter`; both methods have defaults (`Continue`, nothing). See
/// `push_events` for an example.
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
/// run) and `on_leave` for `Leave`. The source is usually an `EventReader`;
/// a streaming parser can implement `EventSource` too, and handlers do not
/// change.
///
/// A handler needs its own type, so this example is not a doc test (a doc
/// test holds only `test` blocks). The cookbook article "Choose a traversal"
/// has a tested handler:
/// https://github.com/moonrockz/krueger/blob/main/docs/cookbook/traversal.mbt.md
///
/// ```mbt nocheck
/// struct Paths {
///   found : Array[String]
/// }
///
/// impl @syntax.Handler for Paths with fn on_enter(self, e) {
///   if e.category == "pattern" {
///     self.found.push(e.path.to_string())
///   }
///   Continue
/// }
///
/// test {
///   let src = "module Main exposing (..)\n\nadd x y =\n    x + y\n"
///   let result = @parser.parse_module(
///     @scanner.SourceText::new(src),
///     @scanner.DefaultScanner::new(),
///   )
///   let root = @syntax.NodeRef::of_result(result).unwrap()
///   let paths = { found: [], }
///   @syntax.push_events(@syntax.EventReader::new(root), paths)
///   inspect(paths.found.length(), content="2")
///   inspect(paths.found[1], content="declarations[0].declaration[0].arguments[1]")
/// }
/// ```
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
