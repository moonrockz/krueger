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
