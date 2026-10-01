///|
/// Records method and node, and returns the policy's k-th decision.
struct PolicyVisitor {
  policy : Policy
  events : Array[String]
  mut k : Int
}

///|
fn PolicyVisitor::on(
  self : PolicyVisitor,
  m : String,
  n : @syntax.NodeRef,
) -> @syntax.Control {
  self.events.push("+" + m + " " + tag(n))
  self.k = self.k + 1
  decide(self.policy, self.k - 1)
}

///|
impl @syntax.Visitor for PolicyVisitor with fn visit_declaration(self, n) {
  self.on("declaration", n)
}

///|
impl @syntax.Visitor for PolicyVisitor with fn visit_function(self, n) {
  self.on("function", n)
}

///|
impl @syntax.Visitor for PolicyVisitor with fn visit_expression(self, n) {
  self.on("expression", n)
}

///|
impl @syntax.Visitor for PolicyVisitor with fn visit_pattern(self, n) {
  self.on("pattern", n)
}

///|
impl @syntax.Visitor for PolicyVisitor with fn visit_type(self, n) {
  self.on("type", n)
}

///|
impl @syntax.Visitor for PolicyVisitor with fn visit_case(self, n) {
  self.on("case", n)
}

///|
impl @syntax.Visitor for PolicyVisitor with fn visit_import(self, n) {
  self.on("import", n)
}

///|
impl @syntax.Visitor for PolicyVisitor with fn visit_comment(self, n) {
  self.on("comment", n)
}

///|
impl @syntax.Visitor for PolicyVisitor with fn visit_attribute(self, n) {
  self.on("attribute", n)
}

///|
impl @syntax.Visitor for PolicyVisitor with fn visit_other(self, n) {
  self.on("other", n)
}

///|
impl @syntax.Visitor for PolicyVisitor with fn leave(self, n) {
  self.events.push("-" + tag(n))
}

///|
fn accept_events(root : @syntax.NodeRef, p : Policy) -> Array[String] {
  let v = { policy: p, events: [], k: 0, }
  @syntax.accept(root, v)
  v.events
}

///|
/// What accept must record: walk's events with the dispatch table's method.
fn dispatch_events(root : @syntax.NodeRef, p : Policy) -> Array[String] {
  let expected = []
  let mut k = 0
  @syntax.walk(
    root,
    n => {
      expected.push("+" + expected_method(n) + " " + tag(n))
      k = k + 1
      decide(p, k - 1)
    },
    leave=n => expected.push("-" + tag(n)),
  )
  expected
}

///|
test "law: accept is walk with the dispatch table" {
  @quickcheck.check(
    (input : (ElmModule, Policy)) => {
      let (m, p) = input
      let root = elm_root(m)
      accept_events(root, p) == dispatch_events(root, p)
    },
    count=200,
    max_size=24,
    seed=23,
  )
}

///|
/// A visitor with only `leave`, logging the nodes it leaves.
struct LeaveLog {
  left : Array[String]
}

///|
impl @syntax.Visitor for LeaveLog with fn leave(self, n) {
  self.left.push(tag(n))
}

///|
test "law: a visitor with only leave leaves every node in walk's post-order" {
  @quickcheck.check(
    (m : ElmModule) => {
      let root = elm_root(m)
      let v : LeaveLog = { left: [], }
      @syntax.accept(root, v)
      let expected = []
      @syntax.walk(root, _ => Continue, leave=n => expected.push(tag(n)))
      v.left == expected
    },
    count=100,
    max_size=24,
    seed=29,
  )
}

///|
test "law: an accept inside a callback gives its standalone result" {
  @quickcheck.check(
    (input : (ElmModule, Policy, Policy)) => {
      let (m, p, q) = input
      let root = elm_root(m)
      let outer = { policy: p, events: [], k: 0, }
      let mut ok = true
      // The outer accept runs first; then, under a walk, each node runs a
      // fresh inner accept with its own visitor.
      @syntax.accept(root, outer)
      @syntax.walk(
        root,
        n => {
          if accept_events(n, q) != dispatch_events(n, q) {
            ok = false
          }
          Continue
        },
        leave=n => {
          if accept_events(n, q) != dispatch_events(n, q) {
            ok = false
          }
        },
      )
      ok && outer.events == dispatch_events(root, p)
    },
    count=50,
    max_size=16,
    seed=37,
  )
}

///|
/// Runs a fresh inner accept at every node it enters and leaves, and forwards
/// each call to an inner PolicyVisitor.
struct NestingVisitor {
  inner : PolicyVisitor
  q : Policy
  mut ok : Bool
}

///|
fn NestingVisitor::check(self : NestingVisitor, n : @syntax.NodeRef) -> Unit {
  if accept_events(n, self.q) != dispatch_events(n, self.q) {
    self.ok = false
  }
}

///|
impl @syntax.Visitor for NestingVisitor with fn visit_declaration(self, n) {
  self.check(n)
  @syntax.Visitor::visit_declaration(self.inner, n)
}

///|
impl @syntax.Visitor for NestingVisitor with fn visit_function(self, n) {
  self.check(n)
  @syntax.Visitor::visit_function(self.inner, n)
}

///|
impl @syntax.Visitor for NestingVisitor with fn visit_expression(self, n) {
  self.check(n)
  @syntax.Visitor::visit_expression(self.inner, n)
}

///|
impl @syntax.Visitor for NestingVisitor with fn visit_pattern(self, n) {
  self.check(n)
  @syntax.Visitor::visit_pattern(self.inner, n)
}

///|
impl @syntax.Visitor for NestingVisitor with fn visit_type(self, n) {
  self.check(n)
  @syntax.Visitor::visit_type(self.inner, n)
}

///|
impl @syntax.Visitor for NestingVisitor with fn visit_case(self, n) {
  self.check(n)
  @syntax.Visitor::visit_case(self.inner, n)
}

///|
impl @syntax.Visitor for NestingVisitor with fn visit_import(self, n) {
  self.check(n)
  @syntax.Visitor::visit_import(self.inner, n)
}

///|
impl @syntax.Visitor for NestingVisitor with fn visit_comment(self, n) {
  self.check(n)
  @syntax.Visitor::visit_comment(self.inner, n)
}

///|
impl @syntax.Visitor for NestingVisitor with fn visit_attribute(self, n) {
  self.check(n)
  @syntax.Visitor::visit_attribute(self.inner, n)
}

///|
impl @syntax.Visitor for NestingVisitor with fn visit_other(self, n) {
  self.check(n)
  @syntax.Visitor::visit_other(self.inner, n)
}

///|
impl @syntax.Visitor for NestingVisitor with fn leave(self, n) {
  self.check(n)
  @syntax.Visitor::leave(self.inner, n)
}

///|
test "law: an accept inside an accept callback leaves the outer accept unchanged" {
  @quickcheck.check(
    (input : (ElmModule, Policy, Policy)) => {
      let (m, p, q) = input
      let root = elm_root(m)
      let v : NestingVisitor = {
        inner: { policy: p, events: [], k: 0, },
        q,
        ok: true,
      }
      @syntax.accept(root, v)
      v.ok && v.inner.events == dispatch_events(root, p)
    },
    count=50,
    max_size=16,
    seed=43,
  )
}
