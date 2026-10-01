///|
fn lit(kind : @scanner.TokenKind, lexeme : String) -> @scanner.Token {
  { kind, lexeme, span: dummy_span, trivia_before: [], trivia_after: [], }
}

///|
test "string escapes decode like elm-syntax" {
  @expect.expect_all(s => {
    s
    .expect(
      string_value(
        lit(StringLiteral, "\"a\\nb\\rc\\td\""),
        @dialect.Dialect::elm_0_19_1(),
      ),
    )
    .to_equal("a\nb\rc\td")
    s
    .expect(
      string_value(
        lit(StringLiteral, "\"q\\\"s\\'b\\\\\""),
        @dialect.Dialect::elm_0_19_1(),
      ),
    )
    .to_equal("q\"s'b\\")
    s
    .expect(
      string_value(
        lit(StringLiteral, "\"\\u{1F308}\\u{41}\""),
        @dialect.Dialect::elm_0_19_1(),
      ),
    )
    .to_equal("\u{1F308}A")
    s
    .expect(
      string_value(
        lit(StringLiteral, "\"\"\"line\none \\\"\"\"\""),
        @dialect.Dialect::elm_0_19_1(),
      ),
    )
    .to_equal("line\none \"")
  })
}

///|
test "char literals decode escapes" {
  @expect.expect_all(s => {
    s
    .expect(char_value(lit(CharLiteral, "'a'"), @dialect.Dialect::elm_0_19_1()))
    .to_equal('a')
    s
    .expect(
      char_value(lit(CharLiteral, "'\\n'"), @dialect.Dialect::elm_0_19_1()),
    )
    .to_equal('\n')
    s
    .expect(
      char_value(
        lit(CharLiteral, "'\\u{1F308}'"),
        @dialect.Dialect::elm_0_19_1(),
      ),
    )
    .to_equal('\u{1F308}')
  })
}

///|
test "unknown escapes and empty chars are syntax errors" {
  @expect.expect_all(s => {
    let unknown = try
      string_value(
        lit(StringLiteral, "\"\\q\""),
        @dialect.Dialect::elm_0_19_1(),
      )
    catch {
      SyntaxError(message, _, _) => message
    } noraise {
      _ => "no error"
    }
    s.expect(unknown).to_equal("unknown escape `\\q`")
    let empty = try
      char_value(lit(CharLiteral, "''"), @dialect.Dialect::elm_0_19_1())
    catch {
      SyntaxError(message, _, _) => message
    } noraise {
      _ => "no error"
    }
    s.expect(empty).to_equal("empty char literal")
  })
}

///|
test "numbers: decimal, hex, float" {
  @expect.expect_all(s => {
    s
    .expect(
      int_value(
        Cursor::new([], @dialect.Dialect::elm_0_19_1()),
        lit(IntLiteral, "31536000000"),
      ),
    )
    .to_equal(Ok(31536000000L))
    s
    .expect(
      int_value(
        Cursor::new([], @dialect.Dialect::elm_0_19_1()),
        lit(IntLiteral, "0xFF"),
      ),
    )
    .to_equal(Err(255L))
    s
    .expect(
      float_value(
        Cursor::new([], @dialect.Dialect::elm_0_19_1()),
        lit(FloatLiteral, "2.5e-3"),
      ),
    )
    .to_equal(0.0025)
  })
}
