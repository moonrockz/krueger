///|
/// The Markdown text of a doc comment (the text between `{-|` and `-}`),
/// and the code blocks in it whose language is not Elm.
///
/// Blocks: paragraphs (words, words with `_`, emphasis with `*` and `_`,
/// strong emphasis, code spans, links, URLs, entities, HTML tags,
/// escapes, `*` between words and escaped in a word, non-ASCII letters and characters outside
/// the BMP), ATX and setext headings, bullet lists (`-`, `*` and `+`) and
/// numbered lists (from 1 or 3), tight and loose, with a nested list, block
/// quotes, fenced code blocks (languages `elm`, none, `attributes` and
/// `js`), indented code blocks, `@docs` lines and thematic breaks. Edge
/// values: no blocks, a code block only, a first block that is not a
/// paragraph, text right after `{-|` or on the next line, no line break at
/// the end, CRLF line ends.
///
/// The code lines have no spaces at their end and no tabs, so code in a
/// language other than Elm stays byte for byte, and a code block does not
/// start with a blank line (elm-format is not idempotent there). Link
/// labels have no `_` or `*`, no `*` follows a letter (elm-format writes
/// `a*b c*` as `a_b c_`, which it reads as text the next time), and a
/// reference link is not followed by a
/// label (elm-format writes `[a] [a]` as `[a]`), so the letters of the text
/// stay the same after formatting. A paragraph comes between two other
/// blocks (elm-format reads two lists in a row as one when it formats
/// its own output).
pub(all) struct DocText {
  text : String
  foreign_code : Array[(String, String)] // language, code
} derive(Debug)

///|
fn doc_word(rs : @splitmix.RandomState) -> String {
  one(rs, [
    "word", "is", "a", "snake_case", "a_b_c", "é", "𐐨", "x𐐨y", "*em*", "_em_",
    "**strong**", "***both***", "`code`", "``co`de``", "[link](http://x.y)", "[link](u \"t\")",
    "[ref].", "http://elm-lang.org", "&amp;", "&ldquo;q&rdquo;", "a\\*b", "2 * 3",
    "\\_", "<b>x</b>", "(x)", "T(..)",
  ])
}

///|
fn doc_line(rs : @splitmix.RandomState) -> String {
  let words = []
  for _ in 0..<(1 + pick(rs, 5)) {
    words.push(doc_word(rs))
  }
  words.join(" ")
}

///|
fn doc_code(rs : @splitmix.RandomState) -> Array[String] {
  let lines = []
  for _ in 0..<(1 + pick(rs, 3)) {
    lines.push(
      one(rs, [
        "f x = x", "@derive [ Json.encoder ]", "x =  1", "let y = 2 in y", "", "a_b * c",
        "    nested", "<div>",
      ]),
    )
  }
  // A code block does not start or end with a blank line: elm-format
  // keeps a blank first line of a fenced block once, then drops it.
  if lines[0] == "" {
    lines[0] = "z"
  }
  if lines.last() == Some("") {
    lines[lines.length() - 1] = "z"
  }
  lines
}

///|
fn doc_list(
  rs : @splitmix.RandomState,
  lines : Array[String],
  indent : String,
  nested : Bool,
) -> Unit {
  let numbered = pick(rs, 2) == 0
  let bullet = one(rs, ["-", "*", "+"])
  let start = if pick(rs, 2) == 0 { 1 } else { 3 }
  let loose = pick(rs, 3) == 0
  for i in 0..<(1 + pick(rs, 3)) {
    if i > 0 && loose {
      lines.push("")
    }
    let mark = if numbered { "\{start + i}." } else { bullet }
    lines.push(indent + mark + " " + doc_line(rs))
    if nested && pick(rs, 4) == 0 {
      doc_list(rs, lines, indent + "    ", false)
    }
  }
}

///|
fn doc_block(
  rs : @splitmix.RandomState,
  lines : Array[String],
  foreign : Array[(String, String)],
) -> Unit {
  match pick(rs, 10) {
    0 => {
      lines.push(doc_line(rs))
      if pick(rs, 2) == 0 {
        lines.push(doc_line(rs))
      }
    }
    1 => lines.push(one(rs, ["# ", "## ", "### "]) + doc_line(rs))
    2 => {
      lines.push(doc_line(rs))
      lines.push(one(rs, ["---", "==="]))
    }
    3 => doc_list(rs, lines, "", true)
    4 => {
      lines.push("> " + doc_line(rs))
      if pick(rs, 2) == 0 {
        lines.push("> " + doc_line(rs))
      }
    }
    5 => {
      let lang = one(rs, ["elm", "", "attributes", "js"])
      let code = doc_code(rs)
      lines.push("```" + lang)
      for line in code {
        lines.push(line)
      }
      lines.push("```")
      if lang != "elm" && lang != "" {
        foreign.push((lang, code.join("\n")))
      }
    }
    6 =>
      for line in doc_code(rs) {
        lines.push(if line == "" { "" } else { "    " + line })
      }
    7 => lines.push("@docs " + one(rs, ["a", "a, b", "T(..), x", "a,b"]))
    8 => lines.push(one(rs, ["---", "* * *", "___"]))
    _ => lines.push(doc_line(rs))
  }
}

///|
pub impl @quickcheck.Arbitrary for DocText with fn arbitrary(size, rs) {
  let lines = []
  let foreign = []
  let blocks = if size <= 0 {
    0
  } else {
    pick(rs, if size < 6 { size } else { 6 }) + 1
  }
  for i in 0..<blocks {
    if i > 0 {
      lines.push("")
      if pick(rs, 4) == 0 {
        lines.push("")
      }
    }
    doc_block(rs, lines, foreign)
    // elm-format writes every bullet list with `-`, and then reads two
    // lists in a row as one: a paragraph separates them.
    if i < blocks - 1 {
      lines.push("")
      lines.push(doc_line(rs))
    }
  }
  let crlf = pick(rs, 4) == 0
  let body = lines.join(if crlf { "\r\n" } else { "\n" })
  let start = one(rs, [" ", " ", "\n", ""])
  let end = if lines.is_empty() || pick(rs, 5) == 0 {
    ""
  } else if crlf {
    "\r\n"
  } else {
    "\n"
  }
  { text: start + body + end, foreign_code: foreign, }
}

///|
pub impl @quickcheck.Shrink for DocText
