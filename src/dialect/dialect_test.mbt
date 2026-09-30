///|
test "built-in dialects have names and the standard operator table" {
  let elm = @dialect.Dialect::elm_0_19_1()
  @expect.expect(elm.name).to_equal("elm-0.19.1")
  @expect.expect(@dialect.Dialect::elm_syntax_7_3_9().name).to_equal(
    "elm-syntax-7.3.9",
  )
  guard elm.operator("|>") is Some(pipe) else { fail("no |>") }
  @expect.expect(pipe.precedence).to_equal(1)
  @expect.expect(pipe.direction).to_equal(Left)
  @expect.expect(elm.operator("<=>") is None).to_be_true()
  @expect.expect(elm.reserved_words).to_equal([])
  @expect.expect(elm.operator_symbols).to_equal([])
  @expect.expect(elm.attributes).to_equal(DocComment)
}

///|
test "rules are off unless the dialect enables them" {
  let syntax = @dialect.Dialect::elm_syntax_7_3_9()
  @expect.expect(syntax.has(LeadingZero)).to_equal(false)
  syntax.rules.add(LeadingZero)
  @expect.expect(syntax.has(LeadingZero)).to_equal(true)
  @expect.expect(@dialect.Dialect::elm_syntax_7_3_9().has(LeadingZero)).to_equal(
    false,
  )
  @expect.expect(@dialect.Dialect::elm_0_19_1().has(LeadingZero)).to_equal(true)
  @expect.expect(@dialect.Dialect::elm_syntax_7_3_9().has(IndentedContinuation)).to_equal(
    true,
  )
  @expect.expect(@dialect.Rule::LeadingZero.name()).to_equal("leading-zero")
  @expect.expect(@dialect.Rule::IndentedContinuation.name()).to_equal(
    "indented-continuation",
  )
}
