///|
/// Text that is mostly not valid Elm, for laws that must hold for any text
/// (no crash, positions between characters and in bounds). It is a list of
/// pieces; `text()` joins them. Kinds of text: fragments (Elm tokens and
/// keywords, edge characters, edge characters inside every literal and
/// comment form, closed or not); a valid module changed at one place or cut
/// at any UTF-16 offset (inside a CRLF or a surrogate pair too); only
/// whitespace and comments; and a module whose value is an edge character
/// inside a literal or comment form. It shrinks by dropping a piece or
/// halving the longest one.
pub(all) struct ElmText(Array[String]) derive(Debug)

///|
/// A string of these UTF-16 code units (a literal cannot hold a lone
/// surrogate).
pub fn units(xs : Array[Int]) -> String {
  let sb = StringBuilder()
  for x in xs {
    sb.write_char(Int::unsafe_to_char(x))
  }
  sb.to_string()
}

///|
/// Characters at the edges of what the scanner handles: lone surrogates
/// (high, low, high before another unit, a low after a pair, two lows), a
/// surrogate pair, a lone `\r`, CRLF, LF, tab, a byte order mark, ASCII,
/// non-ASCII, and nothing.
pub fn edge_chars() -> Array[String] {
  [
    units([0xD800]),
    units([0xDC00]),
    units([0xD800, 'a'.to_int()]),
    units([0xD83D, 0xDE00, 0xDC00]),
    units([0xDC00, 0xDC00]),
    "😀",
    "\r",
    "\r\n",
    "\n",
    "\t",
    "\u{FEFF}",
    "a",
    "é",
    "",
  ]
}

///|
/// Characters at the edges of how a printed string or char literal writes
/// them: the quotes and the backslash, runs of `"` (a triple-quoted string
/// escapes three in a row), line feed, carriage return, tab, other
/// controls, the spaces that elm-format escapes (U+00A0, U+2000, U+202F)
/// and U+0020, which it does not, format characters (U+06DD, U+E007F),
/// line and paragraph separators, private use (U+E000), unassigned code
/// points (U+2E7F, and U+1F6DC, unassigned in Unicode 14.0), a character
/// new in Unicode 14.0 (U+0870), and plain ASCII and non-ASCII.
pub fn literal_edge_chars() -> Array[String] {
  [
    "\"", "\"\"", "\"\"\"", "'", "\\", "\n", "\r", "\t", "\u{0}", "\u{7F}", "\u{9F}",
    " ", "\u{00A0}", "\u{2000}", "\u{202F}", "\u{06DD}", "\u{E007F}", "\u{2028}",
    "\u{2029}", "\u{E000}", "\u{2E7F}", "\u{1F6DC}", "\u{0870}", "a", "é", "😀",
  ]
}

///|
/// Every literal and comment form as (open, close), closed and not.
pub fn literal_forms() -> Array[(String, String)] {
  [
    ("'", "'"),
    ("\"", "\""),
    ("\"\"\"", "\"\"\""),
    ("{-", "-}"),
    ("{-|", "-}"),
    ("--", ""),
    ("'\\", "'"),
    ("\"\\", "\""),
    ("[glsl|", "|]"),
    ("'", ""),
    ("\"", ""),
    ("\"\"\"", ""),
    ("{-", ""),
    ("[glsl|", ""),
  ]
}

///|
let fragments : Array[String] = [
  "module", " ", "M", "exposing", "(..)", "\n", "import", "x", "=", "1", "\"s\"",
  "'c'", "{-", "-}", "{-|", "--", "\"\"\"", "\"", "'", "\r\n", "\r", "\t", "    ",
  "é", "😀", "\u{FEFF}", "(", ")", "[", "]", "{", "}", "|", "->", "\\", ".", "..",
  "0x", "0x1F", "1.5e", "1e3", "1.", ".5", "case", "of", "let", "in", "if", "then",
  "else", "type", "alias", "port", "infix", "where", "as", ",", ":", "@", "`", "#",
  ";", "[glsl|", "|]", "+", "-", "::", "++", "|>", "&", "?", "_", "Just", "\\u{1F600}",
  "\\u{D800}", "{- {- -} -}",
]

///|
let trivia_pieces : Array[String] = [
  "  ", "\n", "\r\n", "\t", "-- c", "{- c -}", "{-| d -}", "{- {- n -} -}",
]

///|
fn piece(rs : @splitmix.RandomState) -> String {
  let edges = edge_chars()
  let forms = literal_forms()
  match pick(rs, 10) {
    0 => edges[pick(rs, edges.length())]
    1 | 2 => {
      let (open, close) = forms[pick(rs, forms.length())]
      open + edges[pick(rs, edges.length())] + close
    }
    _ => fragments[pick(rs, fragments.length())]
  }
}

///|
/// `text` split after each `\n`, so the parts join back to `text` exactly.
fn split_lines(text : String) -> Array[String] {
  let parts = []
  let mut from = 0
  for i in 0..<text.length() {
    if text.code_unit_at(i).to_int() == '\n'.to_int() {
      parts.push(text.unsafe_substring(start=from, end=i + 1))
      from = i + 1
    }
  }
  if from < text.length() {
    parts.push(text.unsafe_substring(start=from, end=text.length()))
  }
  parts
}

///|
pub impl @quickcheck.Arbitrary for ElmText with fn arbitrary(size, rs) {
  let edges = edge_chars()
  let forms = literal_forms()
  match pick(rs, 10) {
    0 | 1 | 2 | 3 => ElmText(Array::makei(pick(rs, size + 1), _ => piece(rs)))
    8 =>
      ElmText(
        Array::makei(pick(rs, 6), _ => {
          trivia_pieces[pick(rs, trivia_pieces.length())]
        }),
      )
    9 => {
      let (open, close) = forms[pick(rs, forms.length())]
      ElmText([
        "module M exposing (..)\n\n\nx =\n    ",
        open + edges[pick(rs, edges.length())] + close,
        ["", "\n", "\r\n", " 1\n"][pick(rs, 4)],
      ])
    }
    _ => {
      let text = (@quickcheck.Arbitrary::arbitrary(size, rs) : ElmModule).text()
      let parts = split_lines(text)
      let at = pick(rs, parts.length() + 1)
      match pick(rs, 4) {
        0 => parts.insert(at, piece(rs))
        1 => if at < parts.length() { ignore(parts.remove(at)) }
        2 => parts.truncate(at)
        _ => {
          // Cut at any UTF-16 offset: inside a token, a CRLF or a pair too.
          let cut = pick(rs, text.length() + 1)
          return ElmText([text.unsafe_substring(start=0, end=cut)])
        }
      }
      ElmText(parts)
    }
  }
}

///|
/// Shrinks by dropping one piece, or by halving the longest piece.
pub impl @quickcheck.Shrink for ElmText with fn shrink(self) {
  let ElmText(parts) = self
  let out = Array::makei(parts.length(), i => {
    let fewer = parts.copy()
    ignore(fewer.remove(i))
    ElmText(fewer)
  })
  let mut longest = -1
  for i, p in parts {
    if p.length() > 1 && (longest < 0 || p.length() > parts[longest].length()) {
      longest = i
    }
  }
  if longest >= 0 {
    let halved = parts.copy()
    let p = parts[longest]
    halved[longest] = p.unsafe_substring(start=0, end=p.length() / 2)
    out.push(ElmText(halved))
  }
  out.iter()
}

///|
/// The text.
pub fn ElmText::text(self : ElmText) -> String {
  let ElmText(parts) = self
  parts.join("")
}
