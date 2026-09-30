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
  @expect.expect(codes(lex("x \"abc\\"))).to_equal(["KR-SCAN-004"])
  @expect.expect(codes(lex("c = '\\"))).to_equal(["KR-SCAN-004"])
  @expect.expect(codes(lex("g = [glsl| a \\"))).to_equal(["KR-SCAN-004"])
}

///|
test "columns count code points, like elm-syntax" {
  let tokens = significant("a = \"😀\" ++ b")
  // [3,5-3,8] in elm-syntax: the emoji counts as one column.
  @expect.expect(tokens[2].span.start.column).to_equal(5)
  @expect.expect(tokens[2].span.end.column).to_equal(8)
  @expect.expect(tokens[4].lexeme).to_equal("b")
  @expect.expect(tokens[4].span.start.column).to_equal(12)
}

///|
test "a GLSL block has no escapes" {
  let tokens = significant("g = [glsl| a \\|]")
  @expect.expect(tokens[2].kind).to_equal(Significant(Glsl))
  @expect.expect(tokens[2].lexeme).to_equal("[glsl| a \\|]")
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
  let d = @dialect.Dialect::elm_0_19_1()
  let custom = { ..d, operator_symbols: ["<=>"], }
  @expect.expect(kinds_in("a <=> b", custom)).to_equal([
    Identifier,
    Operator("<=>"),
    Identifier,
  ])
  @expect.expect(kinds_in("a <=> b", d)).to_equal([
    Identifier,
    Operator("<="),
    Operator(">"),
    Identifier,
  ])
}

///|
test "a dialect adds reserved words" {
  let d = @dialect.Dialect::elm_0_19_1()
  let custom = { ..d, reserved_words: ["forall"], }
  @expect.expect(kinds_in("forall", custom)).to_equal([
    Keyword(Custom("forall")),
  ])
  @expect.expect(kinds_in("forall", d)).to_equal([Identifier])
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
  let d = @dialect.Dialect::elm_0_19_1()
  let custom = { ..d, operator_symbols: [""], }
  @expect.expect(kinds_in("a + b", custom)).to_equal([
    Identifier,
    Operator("+"),
    Identifier,
  ])
  guard lex_raw({ module_name: None, text: "a & b", }, dialect=custom)
    is Err(errs) else {
    fail("expected KR-SCAN-003")
  }
  @expect.expect(errs.diagnostics.map(e => e.code)).to_equal(["KR-SCAN-003"])
}

///|
test "an exponent needs a digit" {
  let d = @dialect.Dialect::elm_0_19_1()
  @expect.expect(kinds_in("1e5", d)).to_equal([FloatLiteral])
  @expect.expect(kinds_in("1.5e-3", d)).to_equal([FloatLiteral])
  @expect.expect(kinds_in("2E+10", d)).to_equal([FloatLiteral])
  @expect.expect(kinds_in("1e", d)).to_equal([IntLiteral, Identifier])
  @expect.expect(kinds_in("1ex", d)).to_equal([IntLiteral, Identifier])
  @expect.expect(kinds_in("0x1F", d)).to_equal([IntLiteral])
}
