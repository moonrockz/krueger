///|
fn lit(kind : @scanner.TokenKind, lexeme : String) -> @scanner.Token {
  { kind, lexeme, span: dummy_span, trivia_before: [], trivia_after: [], }
}

///|
test "string escapes decode like elm-syntax" {
  @expect.expect(
    string_value(
      lit(StringLiteral, "\"a\\nb\\rc\\td\""),
      @dialect.Dialect::elm_0_19_1(),
    ),
  ).to_equal("a\nb\rc\td")
  @expect.expect(
    string_value(
      lit(StringLiteral, "\"q\\\"s\\'b\\\\\""),
      @dialect.Dialect::elm_0_19_1(),
    ),
  ).to_equal("q\"s'b\\")
  @expect.expect(
    string_value(
      lit(StringLiteral, "\"\\u{1F308}\\u{41}\""),
      @dialect.Dialect::elm_0_19_1(),
    ),
  ).to_equal("\u{1F308}A")
  @expect.expect(
    string_value(
      lit(StringLiteral, "\"\"\"line\none \\\"\"\"\""),
      @dialect.Dialect::elm_0_19_1(),
    ),
  ).to_equal("line\none \"")
}

///|
test "char literals decode escapes" {
  @expect.expect(
    char_value(lit(CharLiteral, "'a'"), @dialect.Dialect::elm_0_19_1()),
  ).to_equal('a')
  @expect.expect(
    char_value(lit(CharLiteral, "'\\n'"), @dialect.Dialect::elm_0_19_1()),
  ).to_equal('\n')
  @expect.expect(
    char_value(lit(CharLiteral, "'\\u{1F308}'"), @dialect.Dialect::elm_0_19_1()),
  ).to_equal('\u{1F308}')
}

///|
test "unknown escapes and empty chars are syntax errors" {
  let unknown = try
    string_value(lit(StringLiteral, "\"\\q\""), @dialect.Dialect::elm_0_19_1())
  catch {
    SyntaxError(message, _, _) => message
  } noraise {
    _ => "no error"
  }
  @expect.expect(unknown).to_equal("unknown escape `\\q`")
  let empty = try
    char_value(lit(CharLiteral, "''"), @dialect.Dialect::elm_0_19_1())
  catch {
    SyntaxError(message, _, _) => message
  } noraise {
    _ => "no error"
  }
  @expect.expect(empty).to_equal("empty char literal")
}

///|
test "numbers: decimal, hex, float" {
  @expect.expect(int_value(lit(IntLiteral, "31536000000"))).to_equal(
    Ok(31536000000L),
  )
  @expect.expect(int_value(lit(IntLiteral, "0xFF"))).to_equal(Err(255L))
  @expect.expect(float_value(lit(FloatLiteral, "2.5e-3"))).to_equal(0.0025)
}
