///|
/// A valid module whose declaration `f` has a doc comment with attributes.
/// Edge values: `@docs` lists of one to four names, with characters outside
/// the BMP first, between and last; plain attributes with one value, with
/// the value on the next line, and with a list continued over lines; an
/// attributes block; values with characters outside the BMP and integers
/// too large for 64 bits (`overflow_literal`); LF, CRLF and mixed line ends
/// inside the comment.
pub(all) struct DocAttributes(String) derive(Debug)

///|
/// An integer literal too large for 64 bits: the parser warns on it.
pub fn overflow_literal() -> String {
  "9999999999999999999999999999999"
}

///|
fn doc_value(rs : @splitmix.RandomState) -> String {
  one(rs, [
    "1",
    "\"𐐨\"",
    "'𐐨'",
    "\"é\"",
    "( 1, \"𐐨\" )",
    overflow_literal(),
    "-" + overflow_literal(),
  ])
}

///|
fn doc_attribute(rs : @splitmix.RandomState) -> Array[String] {
  match pick(rs, 5) {
    0 => {
      let names = []
      for _ in 0..<(1 + pick(rs, 4)) {
        names.push(one(rs, ["a", "bb", "é", "𐐨", "x𐐨y", "𐐨𐐨"]))
      }
      ["@docs " + names.join(one(rs, [", ", ",", " , "]))]
    }
    1 => ["@tag " + doc_value(rs)]
    2 => ["@tag", one(rs, [" ", "  ", "    "]) + doc_value(rs)]
    3 => ["@tag [ " + doc_value(rs) + ",", "  " + doc_value(rs), "  ]"]
    _ => ["```attributes", "@tag " + doc_value(rs), " " + doc_value(rs), "```"]
  }
}

///|
pub impl @quickcheck.Arbitrary for DocAttributes with fn arbitrary(_, rs) {
  let lines = ["{-| d", ""]
  for _ in 0..<(1 + pick(rs, 3)) {
    for line in doc_attribute(rs) {
      lines.push(line)
    }
    lines.push("")
  }
  lines.push("-}")
  let ending = pick(rs, 3)
  let sb = StringBuilder()
  sb.write_string("module M exposing (..)\n\n\nx =\n    1\n\n\n")
  for i, line in lines {
    sb.write_string(line)
    // 0: LF, 1: CRLF, 2: mixed.
    let crlf = ending == 1 || (ending == 2 && i % 2 == 0)
    sb.write_string(if crlf { "\r\n" } else { "\n" })
  }
  sb.write_string("f =\n    1\n")
  DocAttributes(sb.to_string())
}

///|
pub impl @quickcheck.Shrink for DocAttributes

///|
/// The module text.
pub fn DocAttributes::text(self : DocAttributes) -> String {
  let DocAttributes(text) = self
  text
}
