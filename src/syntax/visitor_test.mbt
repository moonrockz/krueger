///|
/// Records which method saw each node.
struct Recorder {
  calls : Array[String]
  mut left : Int
}

///|
fn Recorder::new() -> Recorder {
  { calls: [], left: 0, }
}

///|
fn Recorder::record(self : Recorder, m : String) -> @syntax.Control {
  self.calls.push(m)
  Continue
}

///|
impl @syntax.Visitor for Recorder with fn visit_declaration(self, _) {
  self.record("declaration")
}

///|
impl @syntax.Visitor for Recorder with fn visit_function(self, _) {
  self.record("function")
}

///|
impl @syntax.Visitor for Recorder with fn visit_expression(self, _) {
  self.record("expression")
}

///|
impl @syntax.Visitor for Recorder with fn visit_pattern(self, _) {
  self.record("pattern")
}

///|
impl @syntax.Visitor for Recorder with fn visit_type(self, _) {
  self.record("type")
}

///|
impl @syntax.Visitor for Recorder with fn visit_case(self, _) {
  self.record("case")
}

///|
impl @syntax.Visitor for Recorder with fn visit_import(self, _) {
  self.record("import")
}

///|
impl @syntax.Visitor for Recorder with fn visit_comment(self, _) {
  self.record("comment")
}

///|
impl @syntax.Visitor for Recorder with fn visit_attribute(self, _) {
  self.record("attribute")
}

///|
impl @syntax.Visitor for Recorder with fn visit_other(self, _) {
  self.record("other")
}

///|
impl @syntax.Visitor for Recorder with fn leave(self, _) {
  self.left = self.left + 1
}

///|
let case_and_let : String =
  #|module M exposing (..)
  #|
  #|
  #|f x =
  #|    case x of
  #|        _ ->
  #|            let
  #|                y =
  #|                    1
  #|            in
  #|            y
  #|

///|
test "accept calls one method per node, by category and kind" {
  let r = Recorder::new()
  @syntax.accept(parse_root(case_and_let), r)
  @expect.expect(r.calls.join(" ")).to_equal(
    "other other other other function other other pattern expression " +
    "expression case pattern expression function other other expression expression",
  )
  @expect.expect(r.left).to_equal(r.calls.length())
}

///|
/// The method the dispatch table assigns to a node.
fn expected_method(n : @syntax.NodeRef) -> String {
  match (n.category(), n.kind()) {
    ("declaration", "function") | ("let_declaration", "function") => "function"
    ("declaration", _) | ("let_declaration", _) => "declaration"
    ("expression", _) => "expression"
    ("pattern", _) => "pattern"
    ("type", _) => "type"
    ("case_branch", _) => "case"
    ("import", _) => "import"
    ("comment", _) => "comment"
    ("attribute", _) => "attribute"
    _ => "other"
  }
}

///|
test "accept dispatches every method group" {
  let root = parse_root(expression_source)
  let r = Recorder::new()
  @syntax.accept(root, r)
  let expected = []
  @syntax.walk(root, n => {
    expected.push(expected_method(n))
    Continue
  })
  @expect.expect(r.calls).to_equal(expected)
  for
    m in [
      "declaration", "function", "expression", "pattern", "type", "case", "import",
      "comment", "attribute", "other",
    ] {
    @expect.expect(r.calls.contains(m)).to_equal(true)
  }
}

///|
test "accept dispatches each of the 77 kinds as the table says" {
  // kind_cases() has every kind except the file root.
  let cases = kind_cases() + [(parse_root(small), "file", "file")]
  let rows = @syntax.kind_table().map(row => "\{row.0}/\{row.1}")
  let covered = cases.map(c => "\{c.1}/\{c.2}")
  covered.sort()
  rows.sort()
  @expect.expect(covered).to_equal(rows)
  for c in cases {
    let (node, _, _) = c
    let r = Recorder::new()
    @syntax.accept(node, r)
    // The root is dispatched first.
    @expect.expect(r.calls[0]).to_equal(expected_method(node))
  }
}

///|
/// A visitor with only `leave`: every other method is the default.
struct LeaveCounter {
  mut count : Int
}

///|
impl @syntax.Visitor for LeaveCounter with fn leave(self, _) {
  self.count = self.count + 1
}

///|
test "unimplemented visitor methods continue into every node" {
  let root = parse_root(expression_source)
  let c = { count: 0, }
  @syntax.accept(root, c)
  @expect.expect(c.count).to_equal(preorder(root).length())
}

///|
/// Skips the children of function declarations.
struct Skipper {
  seen : Array[String]
}

///|
impl @syntax.Visitor for Skipper with fn visit_function(self, n) {
  self.seen.push(label(n))
  SkipChildren
}

///|
impl @syntax.Visitor for Skipper with fn visit_other(self, n) {
  self.seen.push(label(n))
  Continue
}

///|
impl @syntax.Visitor for Skipper with fn visit_expression(self, n) {
  self.seen.push(label(n))
  Continue
}

///|
test "a visitor's SkipChildren skips the function body" {
  let s = { seen: [], }
  @syntax.accept(parse_root(small), s)
  @expect.expect(s.seen).to_equal([
    "file/file", "module/normal", "module_name/module_name", "exposing/all", "declaration/function",
  ])
}

///|
/// Stops at the first expression; records what it leaves.
struct StopAtExpression {
  left : Array[String]
}

///|
impl @syntax.Visitor for StopAtExpression with fn visit_expression(_self, _) {
  Stop
}

///|
impl @syntax.Visitor for StopAtExpression with fn leave(self, n) {
  self.left.push(n.kind())
}

///|
test "a visitor's Stop ends accept with no further leave" {
  let v : StopAtExpression = { left: [], }
  @syntax.accept(parse_root(small), v)
  @expect.expect(v.left).to_equal(["module_name", "all", "normal", "name"])
}

///|
test "accept handles a 398-level tree" {
  let c = { count: 0, }
  @syntax.accept(tree_of(deep_source()).root(), c)
  @expect.expect(c.count).to_equal(399 + 398 + 7)
}
