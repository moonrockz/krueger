///|
fn cst_source(text : String) -> String? {
  let result = @parser.parse_module(
    @scanner.SourceText::new(text),
    @scanner.DefaultScanner::new(),
  )
  result.cst.map(c => c.to_source())
}

///|
test "to_source gives back texts at the edges" {
  @expect.expect_all(s => {
    for
      text in [
        "", "   ", "\n", "-- only a comment\n", "{- a -}\r\n{-| b -}", "module A exposing (..)\r\n\r\nx =\r\n    1",
        "module A exposing (..)\n\n\nx = \"😀\" -- é\n", "module A exposing (..)\nx = 1\n\n\n   ",
      ] {
      s.expect(cst_source(text)).to_equal(Some(text))
    }
  })
}

///|
test "law: to_source gives back every text that scans" {
  @quickcheck.check(
    (t : @lawkit.ElmText) => {
      let text = t.text()
      match cst_source(text) {
        Some(out) => out == text
        None => true // the text does not scan, so there is no CST
      }
    },
    count=300,
    max_size=40,
    seed=2026,
  )
}

///|
test "law: to_source gives back every generated module" {
  // Every ElmModule scans, so this law always reaches the success branch.
  @quickcheck.check(
    (m : @lawkit.ElmModule) => cst_source(m.text()) == Some(m.text()),
    count=200,
    max_size=24,
    seed=2027,
  )
}
