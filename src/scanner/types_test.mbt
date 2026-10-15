///|
test "a diagnostic carries optional detail" {
  let d : @scanner.Diagnostic = {
    code: "KR-PARSE-010",
    severity: Error,
    message: "nested too deeply",
    span: {
      start: { offset: 0, line: 1, column: 1, },
      end: { offset: 0, line: 1, column: 1, },
    },
    title: "TOO MUCH NESTING",
    report: [],
    detail: Some(OutOfFuel(fuel=1200, walk=Nesting)),
  }
  @expect.expect_all(s => {
    s
    .expect(d.detail)
    .to_equal(Some(@scanner.Detail::OutOfFuel(fuel=1200, walk=Nesting)))
    s.expect(d.detail == Some(OutOfFuel(fuel=1200, walk=Chain))).to_be_false()
    s.expect({ ..d, detail: None, }.detail).to_equal(None)
  })
}
