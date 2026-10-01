///|
fn lex(text : String) -> Result[Array[RawToken], ScanErrorList] {
  lex_raw({ module_name: None, text, })
}

///|
fn codes(result : Result[Array[RawToken], ScanErrorList]) -> Array[String] {
  match result {
    Ok(_) => []
    Err(errs) => errs.diagnostics.map(d => d.code)
  }
}

///|
fn significant(text : String) -> Array[RawToken] raise {
  guard lex(text) is Ok(tokens) else { fail("expected tokens for \{text}") }
  tokens.filter(t => t.kind is Significant(_))
}

///|
test "a backslash at the end of an open literal is an error, not a crash" {
  @expect.expect_all(s => {
    s.expect(codes(lex("x \"abc\\"))).to_equal(["KR-SCAN-004"])
    s.expect(codes(lex("c = '\\"))).to_equal(["KR-SCAN-004"])
    s.expect(codes(lex("g = [glsl| a \\"))).to_equal(["KR-SCAN-004"])
  })
}

///|
test "columns count code points, like elm-syntax" {
  @expect.expect_all(s => {
    let tokens = significant("a = \"😀\" ++ b")
    // [3,5-3,8] in elm-syntax: the emoji counts as one column.
    s.expect(tokens[2].span.start.column).to_equal(5)
    s.expect(tokens[2].span.end.column).to_equal(8)
    s.expect(tokens[4].lexeme).to_equal("b")
    s.expect(tokens[4].span.start.column).to_equal(12)
  })
}

///|
test "a GLSL block has no escapes" {
  @expect.expect_all(s => {
    let tokens = significant("g = [glsl| a \\|]")
    s.expect(tokens[2].kind).to_equal(Significant(Glsl))
    s.expect(tokens[2].lexeme).to_equal("[glsl| a \\|]")
  })
}

///|
fn kinds_in(
  text : String,
  dialect : @dialect.Dialect,
) -> Array[TokenKind] raise {
  guard lex_raw({ module_name: None, text, }, dialect~) is Ok(raw) else {
    fail("lex failed for \{text}")
  }
  raw.filter_map(r => if r.kind is Significant(k) { Some(k) } else { None })
}

///|
test "a dialect adds operator symbols, longest first" {
  @expect.expect_all(s => {
    let d = @dialect.Dialect::elm_0_19_1()
    let custom = { ..d, operator_symbols: ["<=>"], }
    s
    .expect(kinds_in("a <=> b", custom))
    .to_equal([Identifier, Operator("<=>"), Identifier])
    s
    .expect(kinds_in("a <=> b", d))
    .to_equal([Identifier, Operator("<="), Operator(">"), Identifier])
  })
}

///|
test "a dialect adds reserved words" {
  @expect.expect_all(s => {
    let d = @dialect.Dialect::elm_0_19_1()
    let custom = { ..d, reserved_words: ["forall"], }
    s.expect(kinds_in("forall", custom)).to_equal([Keyword(Custom("forall"))])
    s.expect(kinds_in("forall", d)).to_equal([Identifier])
  })
}

///|
test "the default scanner uses the dialect it was built with" {
  let d = @dialect.Dialect::elm_0_19_1()
  let custom = { ..d, reserved_words: ["forall"], }
  guard DefaultScanner::new(dialect=custom).tokenize({
      module_name: None,
      text: "forall",
    })
    is Ok(stream) else {
    fail("tokenize failed")
  }
  @expect.expect(stream.tokens.map(t => t.kind)).to_equal([
    Keyword(Custom("forall")),
  ])
}

///|
test "an empty operator symbol in a dialect is ignored" {
  @expect.expect_all(s => {
    let d = @dialect.Dialect::elm_0_19_1()
    let custom = { ..d, operator_symbols: [""], }
    s
    .expect(kinds_in("a + b", custom))
    .to_equal([Identifier, Operator("+"), Identifier])
    guard lex_raw({ module_name: None, text: "a & b", }, dialect=custom)
      is Err(errs) else {
      fail("expected KR-SCAN-003")
    }
    s.expect(errs.diagnostics.map(e => e.code)).to_equal(["KR-SCAN-003"])
  })
}

///|
test "an exponent needs a digit" {
  @expect.expect_all(s => {
    let d = @dialect.Dialect::elm_0_19_1()
    s.expect(kinds_in("1e5", d)).to_equal([FloatLiteral])
    s.expect(kinds_in("1.5e-3", d)).to_equal([FloatLiteral])
    s.expect(kinds_in("2E+10", d)).to_equal([FloatLiteral])
    s.expect(kinds_in("1e", d)).to_equal([IntLiteral, Identifier])
    s.expect(kinds_in("1ex", d)).to_equal([IntLiteral, Identifier])
    s.expect(kinds_in("0x1F", d)).to_equal([IntLiteral])
  })
}

///|
test "identifiers follow Unicode letters" {
  @expect.expect_all(s => {
    let d = @dialect.Dialect::elm_0_19_1()
    s
    .expect(kinds_in("café = 1", d))
    .to_equal([Identifier, Equals, IntLiteral])
    s.expect(kinds_in("Ωmega", d)).to_equal([Identifier])
    // elm make allows only ASCII digits in names; elm-syntax allows any number.
    let syntax = @dialect.Dialect::elm_syntax_7_3_9()
    s.expect(kinds_in("x₁", syntax)).to_equal([Identifier])
    s.expect(kinds_in("x₁", d)).to_equal([Identifier, Identifier])
    // elm-syntax does not let a title-case letter start a name; elm make does.
    s.expect(kinds_in("ǅx", d)).to_equal([Identifier])
    s
    .expect(
      lex_raw({ module_name: None, text: "ǅx", }, dialect=syntax) is Err(_),
    )
    .to_equal(true)
    s.expect(kinds_in("\u{1D4B3}", d)).to_equal([Identifier])
    s.expect(kinds_in("\"é\"", d)).to_equal([StringLiteral])
    s.expect(is_lower_start('é')).to_equal(true)
    s.expect(is_upper_start('Ω')).to_equal(true)
    s.expect(is_upper_start('\u{1D4B3}')).to_equal(true)
    s.expect(is_lower_start('₁')).to_equal(false)
  })
}

///|
test "a lone carriage return is whitespace" {
  @expect.expect_all(s => {
    guard lex_raw({ module_name: None, text: "x\r+ 1", }) is Ok(raw) else {
      fail("lex failed")
    }
    let significant = raw.filter(r => r.kind is Significant(_))
    s
    .expect(significant.map(r => r.kind))
    .to_equal([
      Significant(Identifier),
      Significant(Operator("+")),
      Significant(IntLiteral),
    ])
    s.expect(significant[1].span.start.column).to_equal(3)
    s.expect(significant[1].span.start.line).to_equal(1)
  })
}
