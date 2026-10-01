///|
/// A construct that nests: each level adds one more of it.
pub(all) enum Construct {
  Parens
  List
  Record
  Lambda
  Let
  Case
  Type
  Pattern
  Operators
  Cons
  Arrow
  ElseIf
  Access
  CtorPattern
  TypeApp
} derive(Eq, Debug)

///|
/// A module whose one declaration nests `construct` `depth` levels deep.
pub(all) struct Nesting {
  construct : Construct
  depth : Int
} derive(Eq, Debug)

///|
/// Every construct.
pub fn constructs() -> Array[Construct] {
  [
    Parens,
    List,
    Record,
    Lambda,
    Let,
    Case,
    Type,
    Pattern,
    Operators,
    Cons,
    Arrow,
    ElseIf,
    Access,
    CtorPattern,
    TypeApp,
  ]
}

///|
/// The module text of `construct` nested `depth` levels deep.
pub fn nested(construct : Construct, depth : Int) -> String {
  let head = "module M exposing (..)\n\n\n"
  match construct {
    Parens =>
      head + "f =\n    " + "(".repeat(depth) + "1" + ")".repeat(depth) + "\n"
    List =>
      head + "f =\n    " + "[".repeat(depth) + "1" + "]".repeat(depth) + "\n"
    Record =>
      head +
      "f =\n    " +
      "{ a = ".repeat(depth) +
      "1" +
      " }".repeat(depth) +
      "\n"
    Lambda => head + "f =\n    " + "\\x -> ".repeat(depth) + "1\n"
    Operators => head + "f =\n    1" + " + 1".repeat(depth) + "\n"
    Cons => head + "f =\n    " + "1 :: ".repeat(depth) + "[]\n"
    Arrow => head + "f : " + "Int -> ".repeat(depth) + "Int\nf =\n    f\n"
    ElseIf => head + "f x =\n    " + "if x then 1 else ".repeat(depth) + "0\n"
    Access => head + "f r =\n    r" + ".a".repeat(depth) + "\n"
    CtorPattern =>
      head +
      "f " +
      "(Just ".repeat(depth) +
      "x" +
      ")".repeat(depth) +
      " =\n    1\n"
    TypeApp =>
      head +
      "f : " +
      "Maybe (".repeat(depth) +
      "Int" +
      ")".repeat(depth) +
      "\nf =\n    f\n"
    Type =>
      head +
      "f : " +
      "(".repeat(depth) +
      "Int" +
      ")".repeat(depth) +
      "\nf =\n    1\n"
    Pattern =>
      head + "f " + "(".repeat(depth) + "x" + ")".repeat(depth) + " =\n    1\n"
    Let => {
      let sb = StringBuilder()
      sb.write_string(head + "f =\n")
      for i in 0..<depth {
        let ind = " ".repeat(4 + 8 * i)
        sb.write_string(ind + "let\n" + ind + "    y =\n")
      }
      sb.write_string(" ".repeat(4 + 8 * depth) + "1\n")
      for i in 0..<depth {
        let ind = " ".repeat(4 + 8 * (depth - 1 - i))
        sb.write_string(ind + "in\n" + ind + "y\n")
      }
      sb.to_string()
    }
    Case => {
      let sb = StringBuilder()
      sb.write_string(head + "f x =\n")
      for i in 0..<depth {
        let ind = " ".repeat(4 + 8 * i)
        sb.write_string(ind + "case x of\n" + ind + "    _ ->\n")
      }
      sb.write_string(" ".repeat(4 + 8 * depth) + "1\n")
      sb.to_string()
    }
  }
}

///|
pub impl @quickcheck.Arbitrary for Nesting with fn arbitrary(_, rs) {
  // Edges: depths 1 and 2, and around both limits (twice a construct can
  // count two levels, so around half the nesting limit too).
  let near = [
    1, 2, 73, 74, 75, 76, 77, 148, 149, 150, 151, 152, 397, 398, 399, 400, 401,
  ]
  let all = constructs()
  let depth = if pick(rs, 4) == 0 {
    1 + pick(rs, 450)
  } else {
    near[pick(rs, near.length())]
  }
  { construct: all[pick(rs, all.length())], depth, }
}

///|
/// Shrinks toward a shallower nesting of the same construct.
pub impl @quickcheck.Shrink for Nesting with fn shrink(self) {
  let out = []
  if self.depth > 1 {
    out.push({ ..self, depth: self.depth / 2, })
    out.push({ ..self, depth: self.depth - 1, })
  }
  out.iter()
}

///|
/// The module text.
pub fn Nesting::text(self : Nesting) -> String {
  nested(self.construct, self.depth)
}
