///|
using @lawkit {type ElmModule}

///|
fn pick(rs : @splitmix.RandomState, n : Int) -> Int {
  rs.next_uint(limit=n.reinterpret_as_uint()).reinterpret_as_int()
}

///|
/// The root of a generated module. Any diagnostic fails the law: a generator
/// defect must be seen, not discarded.
fn elm_root(m : ElmModule) -> @syntax.NodeRef raise {
  let ElmModule(text) = m
  let result = parse_result(text)
  if !result.diagnostics.is_empty() {
    fail(
      "generated Elm does not parse:\n\{text}\n\{result.diagnostics.map(d => d.message).join("; ")}",
    )
  }
  guard @syntax.NodeRef::of_result(result) is Some(root) else { fail("no AST") }
  root
}

///|
/// What the k-th entered node returns: mostly Continue, sometimes
/// SkipChildren, rarely Stop.
struct Policy(Array[@syntax.Control]) derive(Debug)

///|
impl @quickcheck.Arbitrary for Policy with fn arbitrary(_, rs) {
  let n = 1 + pick(rs, 8)
  Policy(
    Array::makei(n, _ => {
      match pick(rs, 10) {
        0 => Stop
        1 | 2 | 3 => SkipChildren
        _ => Continue
      }
    }),
  )
}

///|
impl @quickcheck.Shrink for Policy

///|
fn decide(p : Policy, k : Int) -> @syntax.Control {
  let Policy(cs) = p
  cs[k % cs.length()]
}

///|
/// A node's occurrence tag: category, kind and full range.
fn tag(n : @syntax.NodeRef) -> String {
  let r = n.range()
  "\{n.category()}/\{n.kind()}@\{r.start.row}:\{r.start.column}-\{r.end.row}:\{r.end.column}"
}

///|
/// The events a walk under `p` must produce, by plain recursion (test-only;
/// generated trees are shallow).
fn model(root : @syntax.NodeRef, p : Policy) -> Array[String] {
  let events = []
  let mut k = 0
  fn go(n : @syntax.NodeRef) -> Bool {
    let c = decide(p, k)
    k = k + 1
    events.push("+" + tag(n))
    match c {
      Stop => return true
      SkipChildren => ()
      Continue =>
        for child in n.children() {
          if go(child) {
            return true
          }
        }
    }
    events.push("-" + tag(n))
    false
  }
  ignore(go(root))
  events
}

///|
fn walk_events(root : @syntax.NodeRef, p : Policy) -> Array[String] {
  let events = []
  let mut k = 0
  @syntax.walk(
    root,
    n => {
      events.push("+" + tag(n))
      k = k + 1
      decide(p, k - 1)
    },
    leave=n => events.push("-" + tag(n)),
  )
  events
}
