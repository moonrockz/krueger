///|
/// A valid Elm module with comments in the gaps where Elm allows them: line
/// comments at the end of lines that end with a name, number or bracket;
/// block comments (also nested) in place of a separating space between two
/// tokens; comments on their own lines. Edge values: a comment right after
/// the header, on the last line, on an empty line; LF and CRLF line ends
/// (the base module picks them; a line comment keeps the line end it had).
pub(all) struct Commented(String) derive(Debug)

///|
/// The module's source text.
pub fn Commented::text(self : Commented) -> String {
  let Commented(text) = self
  text
}

///|
fn ends_safely(line : String) -> Bool {
  // A name, number or closing bracket cannot end inside a string or GLSL.
  line.length() > 0 &&
  (
    line.has_suffix(")") ||
    line.has_suffix("]") ||
    line.has_suffix("}") ||
    is_name_char(line[line.length() - 1])
  )
}

///|
fn is_name_char(c : UInt16) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
/// Whether each line starts and ends outside a block comment and a
/// multi-line string. A comment goes only after or in a line that does.
fn line_states(lines : Array[String]) -> (Array[Bool], Array[Bool]) {
  let starts = []
  let ends = []
  let mut depth = 0
  let mut triple = false
  for line in lines {
    starts.push(depth == 0 && !triple)
    let n = line.length()
    let mut i = 0
    while i < n {
      if triple {
        if line[i] == '\\' {
          i += 2
        } else if has_at(line, i, "\"\"\"") {
          triple = false
          i += 3
        } else {
          i += 1
        }
      } else if depth > 0 {
        if has_at(line, i, "{-") {
          depth += 1
          i += 2
        } else if has_at(line, i, "-}") {
          depth -= 1
          i += 2
        } else {
          i += 1
        }
      } else if has_at(line, i, "--") {
        break
      } else if has_at(line, i, "{-") {
        depth = 1
        i += 2
      } else if has_at(line, i, "\"\"\"") {
        triple = true
        i += 3
      } else if line[i] == '"' {
        i += 1
        while i < n && line[i] != '"' {
          i += if line[i] == '\\' { 2 } else { 1 }
        }
        i += 1
      } else if line[i] == '\'' {
        // A char literal holds at least one unit.
        i += 2
        while i < n && line[i] != '\'' {
          i += 1
        }
        i += 1
      } else {
        i += 1
      }
    }
    ends.push(depth == 0 && !triple)
  }
  (starts, ends)
}

///|
fn has_at(line : String, i : Int, s : String) -> Bool {
  i + s.length() <= line.length() && line.view(start_offset=i).has_prefix(s)
}

///|
/// A multi-line construct that holds a comment before its closing bracket,
/// so that the comment is `Inner` to the construct.
fn closing_bracket_lines(n : Int, rs : @splitmix.RandomState) -> Array[String] {
  let (open, close, first) = match pick(rs, 3) {
    0 => ("[", "]", "1")
    1 => ("{", "}", "a = 1")
    _ => ("(", ")", "1")
  }
  [
    "",
    "",
    "br\{n} =",
    "    \{open} \{first}",
    "    -- in\u{A7}\{n}",
    "    \{close}",
  ]
}

///|
/// Every comment that this generator adds holds the marker `\u{A7}` once, so
/// that a test can count them. The base module has none.
pub impl @quickcheck.Arbitrary for Commented with fn arbitrary(size, rs) {
  let ElmModule(base) = ElmModule::arbitrary(size, rs)
  let eol = if base.contains("\r\n") { "\r\n" } else { "\n" }
  let lines : Array[String] = base
    .replace_all(old="\r\n", new="\n")
    .split("\n")
    .map(l => l.to_owned())
    .collect()
  // Edge value: a comment before a closing bracket.
  for n in 0..<pick(rs, 3) {
    for l in closing_bracket_lines(n, rs) {
      lines.push(l)
    }
  }
  let (starts, ends) = line_states(lines)
  let out : Array[String] = []
  for i, line in lines {
    let mut l = line
    // Block comment: replace one separating space between two tokens.
    if starts[i] && pick(rs, 5) == 0 && is_plain(line) {
      l = block_comment(line, rs)
    }
    // Line comment at the end of a safe line, after the header.
    if i > 0 &&
      starts[i] &&
      ends[i] &&
      pick(rs, 4) == 0 &&
      is_plain(l) &&
      ends_safely(l) {
      l = l + " -- c\u{A7}\{i}"
    }
    out.push(l)
    // A comment on its own line after an empty line or the last line.
    if i > 0 &&
      ends[i] &&
      (line.trim() == "" || i == lines.length() - 1) &&
      pick(rs, 3) == 0 {
      out.push("-- own\u{A7}\{i}")
    }
  }
  Commented(out.join(eol))
}

///|
/// A line that holds no string, char, comment or GLSL text, so that the
/// generator cannot cut a token in two.
fn is_plain(line : String) -> Bool {
  !line.contains("\"") &&
  !line.contains("'") &&
  !line.contains("--") &&
  !line.contains("{-") &&
  !line.contains("[glsl|")
}

///|
fn block_comment(line : String, rs : @splitmix.RandomState) -> String {
  // Candidate spaces: between two non-space characters, past the indent.
  let candidates = []
  for i in 1..<(line.length() - 1) {
    if line[i] == ' ' && line[i - 1] != ' ' && line[i + 1] != ' ' {
      candidates.push(i)
    }
  }
  guard candidates.length() > 0 else { return line }
  let at = candidates[pick(rs, candidates.length())]
  let comment = one(rs, ["{- b\u{A7} -}", "{- {- n\u{A7} -} -}", "{-b\u{A7}-}"])
  line.view(end_offset=at).to_owned() +
  " " +
  comment +
  line.view(start_offset=at).to_owned()
}

///|
pub impl @quickcheck.Shrink for Commented
