///|
test "generated spaced modules parse without errors and reach their edges" {
  let rs = @splitmix.new(seed=2034)
  let mut broken = 0
  let mut unbroken = 0
  let mut crlf = 0
  let mut tab = 0
  for i in 0..<200 {
    let m : @lawkit.Spaced = @quickcheck.Arbitrary::arbitrary(i % 20, rs)
    let text = m.text()
    let r = @parser.parse_module(
      @scanner.SourceText::new(text),
      @scanner.DefaultScanner::new(),
    )
    let errors = r.diagnostics.filter(d => d.severity is Error)
    guard errors.is_empty() else {
      fail(
        "generated Elm does not parse:\n\{text}\n" +
        errors.map(d => d.message).join("; "),
      )
    }
    // A continuation line: a line break, then more than 0 spaces of
    // indentation that is not a multiple of 4 or an argument line.
    let lines = text.replace_all(old="\r\n", new="\n").split("\n").collect()
    let continued = lines
      .iter()
      .any(l => l.has_prefix(" ") && !l.has_prefix("    ") && l.trim() != "")
    if continued {
      broken += 1
    } else {
      unbroken += 1
    }
    if text.contains("\r\n") {
      crlf += 1
    }
    if text.contains("\"a\tb\"") {
      tab += 1
    }
  }
  @expect.expect_all(s => {
    s.expect(broken > 40).to_be_true()
    s.expect(unbroken > 40).to_be_true()
    s.expect(crlf > 20).to_be_true()
    s.expect(tab > 10).to_be_true()
  })
}
