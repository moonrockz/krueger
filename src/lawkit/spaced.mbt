///|
/// A valid Elm module with line breaks and indentation where Elm allows
/// them, so that each line-break rule of a formatter sees both decisions: a
/// break or not after `=`, `:`, `->` and operators, between the items of
/// an application (deeper indented), and inside lists, records and tuples
/// before and after `,`. Each module chooses one policy for its gaps.
///
/// Edge values: a break in every gap; in no gap; only before the first
/// argument of each application; only before the last; in random gaps;
/// indentation one column right of the layout column and up to 8 columns
/// more; CRLF line ends; a tab inside a string literal; an application
/// with one argument (first and last at once).
pub(all) struct Spaced(String) derive(Debug)

///|
/// The module's source text.
pub fn Spaced::text(self : Spaced) -> String {
  let Spaced(text) = self
  text
}

///|
/// Where the gaps of a module break.
priv enum GapPolicy {
  Never
  Always
  Random
  FirstArgument
  LastArgument
}

///|
/// A place where a line break may go: before an argument (`first` and
/// `last` say which), or elsewhere.
priv enum Gap {
  Argument(first~ : Bool, last~ : Bool)
  Other
}

///|
priv struct Spacer {
  rs : @splitmix.RandomState
  policy : GapPolicy
}

///|
/// A space, or a line break and the indentation of a continuation line:
/// right of `column`, the indentation of the enclosing layout item.
fn Spacer::gap(self : Spacer, column : Int, at : Gap) -> String {
  let breaks = match (self.policy, at) {
    (Never, _) => false
    (Always, _) => true
    (Random, _) => pick(self.rs, 3) == 0
    (FirstArgument, Argument(first~, ..)) => first
    (LastArgument, Argument(last~, ..)) => last
    (FirstArgument | LastArgument, Other) => false
  }
  if breaks {
    "\n" + ind(column + 1 + pick(self.rs, 8))
  } else {
    " "
  }
}

///|
fn Spacer::leaf(self : Spacer) -> String {
  one(self.rs, [
    "1", "x", "\"s\"", "'c'", "1.5", "()", "Nothing", "0x1F", ".f", "(+)", "r.a",
    "List.map", "\"é😀\"", "\"a\tb\"", "f(x)",
  ])
}

///|
/// An expression that needs no parentheses as an argument.
fn Spacer::atom(self : Spacer, size : Int, column : Int) -> String {
  if size <= 0 {
    return self.leaf()
  }
  let s = size / 2
  let g = () => self.gap(column, Other)
  match pick(self.rs, 8) {
    0 => "(" + self.expr(s, column) + ")"
    1 =>
      "[" +
      g() +
      self.expr(s, column) +
      g() +
      "," +
      g() +
      self.expr(s, column) +
      g() +
      "]"
    2 =>
      "(" +
      g() +
      self.expr(s, column) +
      g() +
      "," +
      g() +
      self.expr(s, column) +
      g() +
      ")"
    3 =>
      "{" +
      g() +
      "a =" +
      g() +
      self.expr(s, column) +
      g() +
      "," +
      g() +
      "b =" +
      g() +
      self.expr(s, column) +
      g() +
      "}"
    4 => "{ r |" + g() + "a =" + g() + self.expr(s, column) + g() + "}"
    5 => "(\\y ->" + g() + self.expr(s, column) + ")"
    6 => "[]"
    _ => self.leaf()
  }
}

///|
/// An expression whose continuation lines go right of `column`.
fn Spacer::expr(self : Spacer, size : Int, column : Int) -> String {
  if size <= 0 {
    return self.leaf()
  }
  let s = size / 2
  let g = () => self.gap(column, Other)
  match pick(self.rs, 7) {
    0 | 1 => {
      // An application with one to three arguments.
      let n = 1 + pick(self.rs, 3)
      let sb = StringBuilder()
      sb.write_string("f")
      for i in 0..<n {
        sb.write_string(
          self.gap(column, Argument(first=i == 0, last=i == n - 1)),
        )
        sb.write_string(self.atom(s, column))
      }
      sb.to_string()
    }
    2 => self.atom(s, column) + g() + "+" + g() + self.atom(s, column)
    3 => self.atom(s, column) + g() + "|>" + g() + "f"
    4 => self.atom(s, column) + g() + "::" + g() + self.atom(s, column)
    5 =>
      "if" +
      g() +
      self.atom(s, column) +
      g() +
      "then" +
      g() +
      self.atom(s, column) +
      g() +
      "else" +
      g() +
      self.atom(s, column)
    _ => self.atom(size, column)
  }
}

///|
/// A type whose continuation lines go right of `column`.
fn Spacer::type_(self : Spacer, size : Int, column : Int) -> String {
  if size <= 0 {
    return one(self.rs, ["Int", "a", "()", "String"])
  }
  let s = size / 2
  let g = () => self.gap(column, Other)
  match pick(self.rs, 5) {
    0 => self.type_(s, column) + g() + "->" + g() + self.type_(s, column)
    1 =>
      "(" +
      g() +
      self.type_(s, column) +
      g() +
      "," +
      g() +
      self.type_(s, column) +
      g() +
      ")"
    2 =>
      "{" +
      g() +
      "c :" +
      g() +
      self.type_(s, column) +
      g() +
      "," +
      g() +
      "d :" +
      g() +
      self.type_(s, column) +
      g() +
      "}"
    3 => "List" + self.gap(column, Argument(first=true, last=true)) + "Int"
    _ => self.type_(0, column)
  }
}

///|
/// The body of a declaration at column 1: an expression after `=` (on the
/// line or the next), a `case` or a `let`.
fn Spacer::body(self : Spacer, size : Int) -> String {
  let s = size / 2
  match pick(self.rs, 4) {
    0 => {
      let sb = StringBuilder()
      sb.write_string("\n    case x of")
      for _ in 0..<(1 + pick(self.rs, 2)) {
        sb.write_string("\n        Just y ->\n            ")
        sb.write_string(self.expr(s, 8))
      }
      sb.write_string("\n\n        Nothing ->\n            1")
      sb.to_string()
    }
    1 =>
      "\n    let\n        y =" +
      self.gap(8, Other) +
      self.expr(s, 8) +
      "\n    in\n    " +
      self.expr(s, 4)
    _ => self.gap(0, Other) + self.expr(size, 0)
  }
}

///|
fn Spacer::declaration(self : Spacer, i : Int, size : Int) -> String {
  match pick(self.rs, 4) {
    0 =>
      "type alias T\{i} a =" + self.gap(0, Other) + self.type_(size, 0) + "\n"
    1 =>
      "f\{i} :" +
      self.gap(0, Other) +
      self.type_(size / 2, 0) +
      "\nf\{i} x =" +
      self.body(size) +
      "\n"
    _ => "g\{i} x =" + self.body(size) + "\n"
  }
}

///|
pub impl @quickcheck.Arbitrary for Spaced with fn arbitrary(size, rs) {
  let policy = match pick(rs, 5) {
    0 => Never
    1 => Always
    2 => FirstArgument
    3 => LastArgument
    _ => Random
  }
  let spacer = { rs, policy, }
  let sb = StringBuilder()
  sb.write_string("module M exposing (..)\n")
  for i in 0..<(1 + pick(rs, 3)) {
    sb.write_string("\n\n" + spacer.declaration(i, size))
  }
  let text = sb.to_string()
  Spaced(
    if pick(rs, 4) == 0 {
      text.replace_all(old="\n", new="\r\n")
    } else {
      text
    },
  )
}

///|
pub impl @quickcheck.Shrink for Spaced
