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
pub impl @quickcheck.Arbitrary for Commented with fn arbitrary(size, rs) {
  let ElmModule(base) = ElmModule::arbitrary(size, rs)
  let crlf = base.contains("\r\n")
  let eol = if crlf { "\r\n" } else { "\n" }
  let lines : Array[String] = base
    .replace_all(old="\r\n", new="\n")
    .split("\n")
    .map(l => l.to_owned())
    .collect()
  let out : Array[String] = []
  for i, line in lines {
    let mut l = line
    // Block comment: replace one separating space between two tokens.
    if pick(rs, 5) == 0 && is_plain(line) {
      l = block_comment(line, rs)
    }
    // Line comment at the end of a safe line, after the header.
    if i > 0 && pick(rs, 4) == 0 && is_plain(l) && ends_safely(l) {
      l = l + " -- c\{i}"
    }
    out.push(l)
    // A comment on its own line after an empty line or the last line.
    if i > 0 &&
      (line.trim() == "" || i == lines.length() - 1) &&
      pick(rs, 3) == 0 {
      out.push("-- own \{i}")
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
  let comment = one(rs, ["{- b -}", "{- {- n -} -}", "{-b-}"])
  line.view(end_offset=at).to_owned() +
  " " +
  comment +
  line.view(start_offset=at).to_owned()
}

///|
pub impl @quickcheck.Shrink for Commented
