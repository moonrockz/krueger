///|
/// A document: pieces of text and places where `render` may break a line.
/// Build documents with the functions of this package and join them with
/// `+`. The representation is private, so it can change without a breaking
/// release.
struct Doc {
  node : DocNode
  // Whether the flat form holds a hard line. A group that holds one always
  // breaks.
  has_hardline : Bool
}

///|
priv enum DocNode {
  Empty
  Text(String, Int) // the text and its width in code points
  Line(Int) // the width of the flat form: 1 for `line`, 0 for `softline`
  HardLine
  VerbatimLine // a line break with no indentation
  Nest(Int, Doc)
  Align(Doc)
  Group(Doc)
  IfBreak(Doc, Doc) // broken, flat
  Concat(Doc, Doc)
}

///|
fn make(node : DocNode, has_hardline : Bool) -> Doc {
  { node, has_hardline, }
}

///|
/// The empty document. `empty() + d` and `d + empty()` render as `d`.
pub fn empty() -> Doc {
  make(Empty, false)
}

///|
fn columns(s : String) -> Int {
  let mut n = 0
  for _ in s {
    n += 1
  }
  n
}

///|
fn atom(s : String) -> Doc {
  if s.is_empty() {
    empty()
  } else {
    make(Text(s, columns(s)), false)
  }
}

///|
/// The text `s`. A line feed in `s` is a `hardline()`, so the lines after it
/// get the current indentation. Width counts code points.
///
/// ```mbt check
/// test {
///   inspect(
///     @pretty.render(@pretty.nest(2, @pretty.text("a\nb"))),
///     content="a\n  b",
///   )
/// }
/// ```
pub fn text(s : String) -> Doc {
  let parts = s.split("\n").map(p => atom(p.to_owned())).collect()
  join(parts, hardline())
}

///|
/// The text `s` as it is: a line feed in `s` starts a new line with no
/// indentation. Use it for text whose bytes must not change, such as a doc
/// comment. A group that holds a line feed this way always breaks.
pub fn verbatim(s : String) -> Doc {
  let parts = s.split("\n").map(p => atom(p.to_owned())).collect()
  join(parts, make(VerbatimLine, true))
}

///|
/// A space in flat mode; a line break and the indentation in break mode.
pub fn line() -> Doc {
  make(Line(1), false)
}

///|
/// Nothing in flat mode; a line break and the indentation in break mode.
pub fn softline() -> Doc {
  make(Line(0), false)
}

///|
/// Always a line break and the indentation. Every group that holds it
/// breaks.
pub fn hardline() -> Doc {
  make(HardLine, true)
}

///|
/// `d` with the indentation of its line breaks increased by `n`.
pub fn nest(n : Int, d : Doc) -> Doc {
  make(Nest(n, d), d.has_hardline)
}

///|
/// `d` with the indentation of its line breaks set to the column where `d`
/// starts.
pub fn align(d : Doc) -> Doc {
  make(Align(d), d.has_hardline)
}

///|
/// `d` on one line when it fits (with the rest of the line up to the next
/// possible break), otherwise `d` with its line breaks.
///
/// ```mbt check
/// test {
///   let d = @pretty.group(@pretty.text("a") + @pretty.line() + @pretty.text("b"))
///   inspect(@pretty.render(d, width=3), content="a b")
///   inspect(@pretty.render(d, width=2), content="a\nb")
/// }
/// ```
pub fn group(d : Doc) -> Doc {
  make(Group(d), d.has_hardline)
}

///|
/// `broken` when the enclosing group breaks, `flat` when it is flat. Only
/// `flat` decides whether the group can be flat.
pub fn if_break(broken : Doc, flat : Doc) -> Doc {
  make(IfBreak(broken, flat), flat.has_hardline)
}

///|
fn concat2(a : Doc, b : Doc) -> Doc {
  match (a.node, b.node) {
    (Empty, _) => b
    (_, Empty) => a
    _ => make(Concat(a, b), a.has_hardline || b.has_hardline)
  }
}

///|
/// The documents one after the other.
pub fn concat(docs : Array[Doc]) -> Doc {
  let mut d = empty()
  for x in docs {
    d = concat2(d, x)
  }
  d
}

///|
/// The documents with `sep` between them.
pub fn join(docs : Array[Doc], sep : Doc) -> Doc {
  let mut d = empty()
  for i, x in docs {
    d = if i == 0 { x } else { concat2(concat2(d, sep), x) }
  }
  d
}

///|
pub impl Add for Doc with fn add(self, other) {
  concat2(self, other)
}
