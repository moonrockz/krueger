///|
test "built-in dialects have names and the standard operator table" {
  @expect.expect_all(s => {
    let elm = @dialect.Dialect::elm_0_19_1()
    s.expect(elm.name).to_equal("elm-0.19.1")
    s
    .expect(@dialect.Dialect::elm_syntax_7_3_9().name)
    .to_equal("elm-syntax-7.3.9")
    guard elm.operator("|>") is Some(pipe) else { fail("no |>") }
    s.expect(pipe.precedence).to_equal(1)
    s.expect(pipe.direction).to_equal(Left)
    s.expect(elm.operator("<=>") is None).to_be_true()
    s.expect(elm.reserved_words).to_equal([])
    s.expect(elm.operator_symbols).to_equal([])
    s.expect(elm.attributes).to_equal(DocComment)
  })
}

///|
test "rules are off unless the dialect enables them" {
  @expect.expect_all(s => {
    let syntax = @dialect.Dialect::elm_syntax_7_3_9()
    s.expect(syntax.has(LeadingZero)).to_equal(false)
    syntax.rules.add(LeadingZero)
    s.expect(syntax.has(LeadingZero)).to_equal(true)
    s
    .expect(@dialect.Dialect::elm_syntax_7_3_9().has(LeadingZero))
    .to_equal(false)
    s.expect(@dialect.Dialect::elm_0_19_1().has(LeadingZero)).to_equal(true)
    s
    .expect(@dialect.Dialect::elm_syntax_7_3_9().has(IndentedContinuation))
    .to_equal(true)
    s.expect(@dialect.Rule::LeadingZero.name()).to_equal("leading-zero")
    s
    .expect(@dialect.Rule::IndentedContinuation.name())
    .to_equal("indented-continuation")
  })
}

///|
test "validate reports a bad operator table" {
  @expect.expect_all(s => {
    let d = @dialect.Dialect::elm_0_19_1()
    s.expect(d.validate()).to_equal([])
    let bad = {
      ..d,
      operators: [
        ..d.operators,
        { symbol: "+", precedence: 9, direction: Left, },
        { symbol: "<=>", precedence: 0, direction: Non, },
        { symbol: "", precedence: 4, direction: Non, },
      ],
      operator_symbols: ["", "~>"],
      reserved_words: ["alias", "forall"],
    }
    s
    .expect(bad.validate())
    .to_equal([
      "operator `+` is defined twice", "operator `<=>` has precedence 0; precedences are 1 to 9",
      "an operator has an empty symbol", "operator symbol `` is empty", "operator symbol `~>` does not start with a symbol character",
      "reserved word `alias` is a name the parser reads by its text",
    ])
  })
}
