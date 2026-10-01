///|
/// A random Elm module that parses without errors. Nesting depth is bounded
/// by the quickcheck size (each level halves it).
struct ElmModule(String) derive(Debug)

///|
fn pick(rs : @splitmix.RandomState, n : Int) -> Int {
  rs.next_uint(limit=n.reinterpret_as_uint()).reinterpret_as_int()
}

///|
fn one(rs : @splitmix.RandomState, xs : Array[String]) -> String {
  xs[pick(rs, xs.length())]
}

///|
fn ind(n : Int) -> String {
  " ".repeat(n)
}

///|
fn gen_leaf(rs : @splitmix.RandomState) -> String {
  one(rs, [
    "1", "x", "\"s\"", "'c'", "1.5", "()", "Nothing", "0x1F", ".f", "(+)", "r.a",
    "List.map",
  ])
}

///|
/// An expression that needs no parentheses as an argument.
fn gen_atom(size : Int, rs : @splitmix.RandomState) -> String {
  if size <= 0 {
    return gen_leaf(rs)
  }
  let s = size / 2
  match pick(rs, 9) {
    0 => "(" + gen_inline(s, rs) + ")"
    1 => "[ " + gen_inline(s, rs) + ", " + gen_inline(s, rs) + " ]"
    2 => "( " + gen_inline(s, rs) + ", " + gen_inline(s, rs) + " )"
    3 => "{ a = " + gen_inline(s, rs) + ", b = " + gen_inline(s, rs) + " }"
    4 => "{ r | a = " + gen_inline(s, rs) + " }"
    5 => "(\\y -> " + gen_inline(s, rs) + ")"
    6 => "(-x)"
    7 => "[]"
    _ => gen_leaf(rs)
  }
}

///|
/// A one-line expression.
fn gen_inline(size : Int, rs : @splitmix.RandomState) -> String {
  if size <= 0 {
    return gen_leaf(rs)
  }
  let s = size / 2
  match pick(rs, 6) {
    0 => "f " + gen_atom(s, rs) + " " + gen_atom(s, rs)
    1 => gen_atom(s, rs) + " + " + gen_atom(s, rs)
    2 => gen_atom(s, rs) + " :: " + gen_atom(s, rs)
    3 => gen_atom(s, rs) + " |> f"
    4 =>
      "if " +
      gen_atom(s, rs) +
      " then " +
      gen_atom(s, rs) +
      " else " +
      gen_atom(s, rs)
    _ => gen_atom(size, rs)
  }
}

///|
fn gen_pattern_atom(size : Int, rs : @splitmix.RandomState) -> String {
  if size <= 0 {
    return one(rs, ["_", "a", "1", "\"s\"", "()", "Nothing", "[]", "'c'"])
  }
  let s = size / 2
  match pick(rs, 5) {
    0 => "( " + gen_pattern(s, rs) + ", " + gen_pattern(s, rs) + " )"
    1 => "[ " + gen_pattern(s, rs) + " ]"
    2 => "{ a, b }"
    3 => "(" + gen_pattern(s, rs) + " as z)"
    _ => gen_pattern_atom(0, rs)
  }
}

///|
fn gen_pattern(size : Int, rs : @splitmix.RandomState) -> String {
  if size <= 0 {
    return gen_pattern_atom(0, rs)
  }
  let s = size / 2
  match pick(rs, 3) {
    0 => "Just " + gen_pattern_atom(s, rs)
    1 => gen_pattern_atom(s, rs) + " :: " + gen_pattern_atom(s, rs)
    _ => gen_pattern_atom(size, rs)
  }
}

///|
fn gen_type(size : Int, rs : @splitmix.RandomState) -> String {
  if size <= 0 {
    return one(rs, ["Int", "a", "()", "String"])
  }
  let s = size / 2
  match pick(rs, 6) {
    0 => gen_type(s, rs) + " -> " + gen_type(s, rs)
    1 => "( " + gen_type(s, rs) + ", " + gen_type(s, rs) + " )"
    2 => "{ c : " + gen_type(s, rs) + " }"
    3 => "{ a | c : " + gen_type(s, rs) + " }"
    4 => "List (" + gen_type(s, rs) + ")"
    _ => gen_type(0, rs)
  }
}

///|
/// An expression that may span lines (case, let), starting at column
/// `indent + 1`.
fn gen_block(size : Int, indent : Int, rs : @splitmix.RandomState) -> String {
  if size <= 0 {
    return gen_inline(0, rs)
  }
  let s = size / 2
  match pick(rs, 4) {
    0 => {
      let sb = StringBuilder()
      sb.write_string("case " + gen_atom(s, rs) + " of")
      for _ in 0..<(1 + pick(rs, 2)) {
        sb.write_string("\n" + ind(indent + 4) + gen_pattern(s, rs) + " ->\n")
        sb.write_string(ind(indent + 8) + gen_block(s, indent + 8, rs) + "\n")
      }
      sb.to_string()
    }
    1 => {
      let head = if pick(rs, 2) == 0 { "y" } else { "( p, q )" }
      "let\n" +
      ind(indent + 4) +
      head +
      " =\n" +
      ind(indent + 8) +
      gen_block(s, indent + 8, rs) +
      "\n" +
      ind(indent) +
      "in\n" +
      ind(indent) +
      gen_block(s, indent, rs)
    }
    _ => gen_inline(size, rs)
  }
}

///|
fn gen_declaration(i : Int, size : Int, rs : @splitmix.RandomState) -> String {
  match pick(rs, 6) {
    0 => "type alias T\{i} a =\n    " + gen_type(size, rs) + "\n"
    1 => "type U\{i}\n    = V\{i} Int\n    | W\{i}\n"
    2 => "-- c\{i}\n"
    3 =>
      "{-| F.\n\n@tag one\n-}\nf\{i} : " +
      gen_type(size / 2, rs) +
      "\nf\{i} x =\n    " +
      gen_block(size, 4, rs) +
      "\n"
    _ => "f\{i} x y =\n    " + gen_block(size, 4, rs) + "\n"
  }
}

///|
impl @quickcheck.Arbitrary for ElmModule with fn arbitrary(size, rs) {
  let sb = StringBuilder()
  sb.write_string("module M exposing (..)\n\n")
  if pick(rs, 2) == 0 {
    sb.write_string("import Dict as D exposing (Dict, empty)\n")
  }
  for i in 0..<(1 + pick(rs, 3)) {
    sb.write_string("\n\n" + gen_declaration(i, size, rs))
  }
  ElmModule(sb.to_string())
}

///|
impl @quickcheck.Shrink for ElmModule

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
