///|
/// Records pushed events; skips function declarations and stops at the
/// first integer.
struct Recording {
  pushed : Array[String]
}

///|
impl @syntax.Handler for Recording with fn on_enter(self, e) {
  self.pushed.push(event_label(Enter(e)))
  if e.kind == "integer" {
    Stop
  } else if e.category == "let_declaration" {
    SkipChildren
  } else {
    Continue
  }
}

///|
impl @syntax.Handler for Recording with fn on_leave(self, e) {
  self.pushed.push(event_label(Leave(e)))
}

///|
let let_source : String =
  #|module M exposing (..)
  #|
  #|
  #|f =
  #|    let
  #|        y =
  #|            2
  #|    in
  #|    g 1
  #|

///|
test "push_events follows the handler's SkipChildren and Stop" {
  let h : Recording = { pushed: [], }
  @syntax.push_events(@syntax.EventReader::new(parse_root(let_source)), h)
  @expect.expect(h.pushed[8:].to_owned()).to_equal([
    "+implementation/implementation declaration 4:1", "+name/name name 4:1", "-name/name",
    "+expression/let expression 5:5", "+let_declaration/function declarations 6:9",
    "-let_declaration/function", "+expression/application expression 9:5", "+expression/functionOrValue application 9:5",
    "-expression/functionOrValue", "+expression/integer application 9:7",
  ])
}

///|
/// A handler with only `on_leave`.
struct LeaveTally {
  mut tally : Int
}

///|
impl @syntax.Handler for LeaveTally with fn on_leave(self, _) {
  self.tally = self.tally + 1
}

///|
test "a handler with only on_leave leaves every node" {
  let root = parse_root(expression_source)
  let h : LeaveTally = { tally: 0, }
  @syntax.push_events(@syntax.EventReader::new(root), h)
  @expect.expect(h.tally).to_equal(preorder(root).length())
}

///|
test "push_events handles a 398-level tree" {
  let h : LeaveTally = { tally: 0, }
  @syntax.push_events(
    @syntax.EventReader::new(tree_of(deep_source()).root()),
    h,
  )
  @expect.expect(h.tally).to_equal(399 + 398 + 7)
}

///|
/// An event source outside the syntax package: it replays events built with
/// `EnterEvent::new` and `LeaveEvent::new`.
struct Replay {
  events : Array[@syntax.Event]
  mut at : Int
}

///|
impl @syntax.EventSource for Replay with fn next(self) {
  let e = self.events.get(self.at)
  self.at = self.at + 1
  e
}

///|
impl @syntax.EventSource for Replay with fn skip_children(_self) {
  ()
}

///|
test "an outside event source builds events with new, and push_events reads it" {
  @expect.expect_all(s => {
    let root = parse_root(small)
    let path = @syntax.NodePath::root()
    let enter = @syntax.EnterEvent::new(
      category="file",
      kind="file",
      field=None,
      start=loc(1, 1),
      path~,
    )
    let source = {
      events: [Enter(enter), Leave(@syntax.LeaveEvent::new(node=root, path~))],
      at: 0,
    }
    let h : Recording = { pushed: [], }
    @syntax.push_events(source, h)
    s.expect(h.pushed).to_equal(["+file/file 1:1", "-file/file"])
    s.expect(enter.depth).to_equal(0)
  })
}
