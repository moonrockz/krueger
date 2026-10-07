///|
/// A random Elm module that parses without errors. Nesting depth is bounded
/// by the quickcheck size (each level halves it). Edge values: zero to three
/// declarations; non-ASCII strings, chars, names and comments (surrogate
/// pairs), also before a token on the same line and in multi-line strings and
/// comments; tokens with no space between them; comments inside expressions;
/// a port whose doc comment has attributes; layout or a comment before the
/// header; trailing spaces at the end; CRLF line ends and no final newline
/// (independently); literals at the edges of their types (the largest Int and
/// hex a Double holds exactly, the largest, smallest and an inexact Float, a
/// Float that rounds to zero, the first and last code point, escapes). No Int
/// literal above 2^53: the default encoder writes Ints as Doubles, as
/// elm-syntax does (`IntLiteral` reaches them). No GLSL: its elm-syntax range
/// ends two columns late, which the range laws reject.
pub(all) struct ElmModule(String) derive(Debug)

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
    "List.map", "\"é😀\"", "'😀'", "f(x)", "9007199254740991", "0x1FFFFFFFFFFFFF",
    "1.7976931348623157e308", "4.9e-324", "0.1", "1e-400", "'\\u{0}'", "'\\u{10FFFF}'",
    "\"\\u{2028}\\t\\\"\\\\\"",
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
  match pick(rs, 10) {
    0 => "f " + gen_atom(s, rs) + " " + gen_atom(s, rs)
    5 => "f {- é😀 -} " + gen_atom(s, rs) + "+" + gen_atom(s, rs)
    1 => gen_atom(s, rs) + " + " + gen_atom(s, rs)
    2 => gen_atom(s, rs) + " :: " + gen_atom(s, rs)
    3 => gen_atom(s, rs) + " |> f"
    // A lambda or `if` at the end of a chain: elm-format puts it in
    // parentheses, except after `<|`.
    6 => gen_atom(s, rs) + " |> \\y -> " + gen_atom(s, rs)
    7 => "f <| \\y -> " + gen_atom(s, rs)
    8 =>
      "((" +
      gen_inline(s, rs) +
      ")) ++ if x then " +
      gen_atom(s, rs) +
      " else y"
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
    return one(rs, [
      "_", "a", "1", "\"s\"", "()", "Nothing", "[]", "'c'", "9007199254740991", "0x1FFFFFFFFFFFFF",
      "'\\u{10FFFF}'", "\"\\u{0}\"",
    ])
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
  match pick(rs, 5) {
    0 => "Just " + gen_pattern_atom(s, rs)
    1 => gen_pattern_atom(s, rs) + " :: " + gen_pattern_atom(s, rs)
    // A constructor with arguments before or after `::` (and in an `as`,
    // from `gen_pattern_atom`): elm-format puts it in parentheses.
    2 => "Just " + gen_pattern_atom(s, rs) + " :: " + gen_pattern_atom(s, rs)
    3 => gen_pattern_atom(s, rs) + " :: Just " + gen_pattern_atom(s, rs)
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
fn gen_declaration(
  i : Int,
  size : Int,
  ports : Bool,
  rs : @splitmix.RandomState,
) -> String {
  if ports && pick(rs, 3) == 0 {
    // A port whose doc comment has attributes: the comment (a file comment)
    // overlaps the port declaration only in part.
    return "{-| P.\n\n@unit \"x\"\n-}\nport p\{i} : Int -> Cmd msg\n"
  }
  match pick(rs, 10) {
    0 => "type alias T\{i} a =\n    " + gen_type(size, rs) + "\n"
    1 => "type U\{i}\n    = V\{i} Int\n    | W\{i}\n"
    2 => if pick(rs, 2) == 0 { "-- c\{i}\n" } else { "-- 😀 c\{i}\n" }
    3 =>
      "{-| F.\n\n@tag one\n-}\nf\{i} : " +
      gen_type(size / 2, rs) +
      "\nf\{i} x =\n    " +
      gen_block(size, 4, rs) +
      "\n"
    4 => "naïve\{i} x =\n    " + gen_block(size, 4, rs) + "\n"
    5 => "f\{i} x y =\n    " + gen_block(size, 4, rs) + " -- 😀\n"
    6 => "s\{i} =\n    \"\"\"é\n😀b\nc\"\"\"\n"
    7 => "{- é\n😀 -}\n"
    8 =>
      "g\{i} (" +
      gen_pattern(size, rs) +
      ") =\n    " +
      gen_block(size, 4, rs) +
      "\n"
    _ => "f\{i} x y =\n    " + gen_block(size, 4, rs) + "\n"
  }
}

///|
pub impl @quickcheck.Arbitrary for ElmModule with fn arbitrary(size, rs) {
  let sb = StringBuilder()
  // Layout or a comment before the module header.
  sb.write_string(["", "", "\n\n", "-- c\n", "{- c -}\n"][pick(rs, 5)])
  let ports = pick(rs, 4) == 0
  sb.write_string(
    if ports {
      "port module M exposing (..)\n\n"
    } else {
      "module M exposing (..)\n\n"
    },
  )
  if pick(rs, 2) == 0 {
    sb.write_string("import Dict as D exposing (Dict, empty)\n")
  }
  // Zero to three declarations.
  for i in 0..<pick(rs, 4) {
    sb.write_string("\n\n" + gen_declaration(i, size, ports, rs))
  }
  // No final newline and CRLF are chosen independently.
  let text = sb.to_string()
  let text = match pick(rs, 6) {
    0 | 1 => text.trim_end(chars="\n").to_owned()
    // Trailing spaces and no final newline.
    2 => text + "   "
    _ => text
  }
  ElmModule(
    if pick(rs, 3) == 0 {
      text.replace_all(old="\n", new="\r\n")
    } else {
      text
    },
  )
}

///|
pub impl @quickcheck.Shrink for ElmModule

///|
/// The module's source text.
pub fn ElmModule::text(self : ElmModule) -> String {
  let ElmModule(text) = self
  text
}
