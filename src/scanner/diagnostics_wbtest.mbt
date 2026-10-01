///|
fn first_error(result : Result[TokenStream, ScanErrorList]) -> Diagnostic? {
  match result {
    Ok(_) => None
    Err(errs) =>
      if errs.diagnostics.length() > 0 {
        Some(errs.diagnostics[0])
      } else {
        None
      }
  }
}

///|
test "unterminated block comment returns KR-SCAN-001 with eof span" {
  let source = SourceText::{ module_name: None, text: "{- missing close", }
  let scanner = DefaultScanner::new()
  let diag = match first_error(scanner.tokenize(source)) {
    Some(diag) => diag
    None => fail("expected tokenization error")
  }
  assert_eq(diag.code, "KR-SCAN-001")
  assert_true(diag.span.start.offset <= diag.span.end.offset)
}

///|
test "unterminated doc comment returns KR-SCAN-002" {
  let source = SourceText::{ module_name: None, text: "{-| missing close", }
  let scanner = DefaultScanner::new()
  let diag = match first_error(scanner.tokenize(source)) {
    Some(diag) => diag
    None => fail("expected tokenization error")
  }
  assert_eq(diag.code, "KR-SCAN-002")
}

///|
test "invalid character sequence returns KR-SCAN-003" {
  let source = SourceText::{
    module_name: None,
    text: "module Main exposing (@)",
  }
  let scanner = DefaultScanner::new()
  let diag = match first_error(scanner.tokenize(source)) {
    Some(diag) => diag
    None => fail("expected tokenization error")
  }
  assert_eq(diag.code, "KR-SCAN-003")
}

///|
fn title_of(text : String) -> String {
  match
    first_error(DefaultScanner::new().tokenize({ module_name: None, text, })) {
    Some(d) => d.title
    None => "no error"
  }
}

///|
test "scanner errors have elm make titles" {
  @expect.expect_all(s => {
    s.expect(title_of("f =\n\tx")).to_equal("NO TABS")
    s.expect(title_of("x = \"abc")).to_equal("ENDLESS STRING")
    s.expect(title_of("x = \"\"\"abc")).to_equal("ENDLESS STRING")
    s.expect(title_of("x = 'a")).to_equal("MISSING SINGLE QUOTE")
    s.expect(title_of("x = [glsl| void")).to_equal("ENDLESS SHADER")
    s.expect(title_of("x = 1 {- abc")).to_equal("ENDLESS COMMENT")
    s.expect(title_of("{-| abc")).to_equal("ENDLESS COMMENT")
    s.expect(title_of("x = y @ 1")).to_equal("UNEXPECTED SYMBOL")
    s.expect(title_of("x = y ; 1")).to_equal("UNEXPECTED SEMICOLON")
    s.expect(title_of("x = y ` 1")).to_equal("UNEXPECTED CHARACTER")
  })
}

///|
test "scanner reports excerpt the error line and mark where elm make does" {
  @expect.expect_all(soft => {
    guard first_error(
        DefaultScanner::new().tokenize({
          module_name: None,
          text: "x =\n  {- abc",
        }),
      )
      is Some(d) else {
      fail("expected an error")
    }
    guard d.report.iter().find_first(b => b is Excerpt(_))
      is Some(Excerpt(context~, highlight~)) else {
      fail("expected an excerpt")
    }
    soft.expect((context.start.line, context.end.line)).to_equal((2, 2))
    // The opening `{-` is marked.
    soft.expect((highlight.start.column, highlight.end.column)).to_equal((3, 5))
    guard first_error(
        DefaultScanner::new().tokenize({
          module_name: None,
          text: "x = \"abc\ny = 1",
        }),
      )
      is Some(s) else {
      fail("expected an error")
    }
    guard s.report.iter().find_first(b => b is Excerpt(_))
      is Some(Excerpt(highlight~, ..)) else {
      fail("expected an excerpt")
    }
    // The end of the line is marked.
    soft.expect((highlight.start.line, highlight.start.column)).to_equal((1, 9))
  })
}
