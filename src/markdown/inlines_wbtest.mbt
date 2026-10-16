///|
/// Cheapskate `pCode'` as a scan to the closing run: the model of
/// `InlineParser::code`.
fn code_model(p : InlineParser) -> (Inline, String)? {
  let start = p.pos
  guard p.take_while1(x => x == '`') is Some(ticks) else { return None }
  let contents = StringBuilder()
  while true {
    let save = p.pos
    if p.string(ticks) && p.peek() != Some('`') {
      let text = contents.to_string()
      return Some((Code(strip(text)), ticks + text + ticks))
    }
    p.pos = save
    if p.take_while1(x => x != '`') is Some(t) {
      contents.write_string(t)
    } else if p.take_while1(x => x == '`') is Some(t) {
      contents.write_string(t)
    } else {
      break
    }
  }
  p.pos = start
  None
}

///|
/// The text and the raw text of a code span.
fn span(r : (Inline, String)?) -> (String, String)? {
  match r {
    Some((Code(text), raw)) => Some((text, raw))
    Some(_) => Some(("not a code span", ""))
    None => None
  }
}

///|
/// Every text of up to `max` characters from `alphabet`.
fn all_texts(alphabet : Array[Char], max : Int32) -> Array[String] {
  let out = [""]
  let mut level = [""]
  for _ in 0..<max {
    let next = []
    for t in level {
      for c in alphabet {
        next.push(t + c.to_string())
      }
    }
    out.append(next)
    level = next
  }
  out
}

///|
test "code spans agree with the scan of Cheapskate pCode' at every position" {
  // Edges: no run, one run, runs of equal and different lengths, adjacent
  // runs, a run at the start and at the end of the text, a run inside a
  // longer run (where a retry starts).
  let mismatches = []
  for text in all_texts(['`', 'a', ' '], 9) {
    for pos in 0..<=text.length() {
      let p = InlineParser::new(text, 0)
      p.pos = pos
      let model = InlineParser::new(text, 0)
      model.pos = pos
      let got = (span(p.code()), p.pos)
      let want = (span(code_model(model)), model.pos)
      if got != want && mismatches.length() < 5 {
        mismatches.push((text, pos, got, want))
      }
    }
  }
  @expect.expect(mismatches).to_equal([])
}
