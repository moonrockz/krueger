///|
test "format passes the fuel to the parser" {
  let text = @lawkit.nested(Parens, 20)
  let codes : Array[String] = try {
    ignore(@printer.format(text, fuel=100))
    []
  } catch {
    ParseFailed(diags) => diags.map(d => d.code)
    Unprintable(_) => ["unprintable"]
  }
  @expect.expect(codes).to_equal(["KR-PARSE-010"])
}

///|
test "format keeps doc-comment code that does not parse within the fuel" {
  // The code in the doc comment is 20 parentheses deep: with fuel 100 it
  // stays as written; with the default it is formatted (the parentheses go).
  let code = "x = " + "(".repeat(20) + "1" + ")".repeat(20)
  let text = "module M exposing (..)\n\n{-| Doc.\n\n    " +
    code +
    "\n\n-}\n\n\na =\n    1\n"
  @expect.expect_all(s => {
    s.expect(@printer.format(text, fuel=100).contains(code)).to_be_true()
    s
    .expect(@printer.format(text).contains("    x =\n        1\n"))
    .to_be_true()
  })
}
