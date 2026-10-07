///|
/// The letters of `text`: its characters without ASCII punctuation, digits
/// and white space, and without the language of Elm code blocks (a fenced
/// Elm code block becomes an indented one).
fn letters(text : String) -> String {
  let sb = StringBuilder()
  for c in text.replace_all(old="```elm", new="```") {
    if !c.is_ascii() || c.is_ascii_alphabetic() {
      sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
test "law: format_doc is idempotent" {
  @quickcheck.check(
    (d : @lawkit.DocText) => {
      let once = @markdown.format_doc(d.text)
      @markdown.format_doc(once) == once
    },
    count=300,
    max_size=8,
    seed=2026,
  )
}

///|
test "law: code blocks in a language other than Elm stay byte for byte" {
  @quickcheck.check(
    (d : @lawkit.DocText) => {
      let out = @markdown.format_doc(d.text)
      d.foreign_code
      .iter()
      .all(c => {
        let (lang, code) = c
        out.contains("```" + lang + "\n" + code + "\n```\n")
      })
    },
    count=300,
    max_size=8,
    seed=2027,
  )
}

///|
test "law: format_doc keeps the letters of the text" {
  @quickcheck.check(
    (d : @lawkit.DocText) => {
      letters(@markdown.format_doc(d.text)) == letters(d.text)
    },
    count=300,
    max_size=8,
    seed=2028,
  )
}

///|
test "law: format_doc formats each Elm code block with format_code" {
  // With a `format_code` that marks the code, every Elm code block is
  // marked, and nothing else is.
  @quickcheck.check(
    (d : @lawkit.DocText) => {
      let mut calls = 0
      let out = @markdown.format_doc(d.text, format_code=code => {
        calls += 1
        Some("mark\n" + code)
      })
      let marks = out.split("mark").count() - 1
      marks == calls
    },
    count=300,
    max_size=8,
    seed=2029,
  )
}
