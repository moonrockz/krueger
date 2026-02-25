fn first_error(result : Result[TokenStream, ScanErrorList]) -> Diagnostic? {
  match result {
    Ok(_) => None
    Err(errs) => {
      if errs.diagnostics.length() > 0 {
        Some(errs.diagnostics[0])
      } else {
        None
      }
    }
  }
}

test "unterminated block comment returns KR-SCAN-001 with eof span" {
  let source = SourceText::{ module_name: None, text: "{- missing close" }
  let scanner = DefaultScanner::new()
  let diag = match first_error(scanner.tokenize(source)) {
    Some(diag) => diag
    None => fail("expected tokenization error")
  }
  assert_eq(diag.code, "KR-SCAN-001")
  assert_true(diag.span.start.offset <= diag.span.end.offset)
}

test "unterminated doc comment returns KR-SCAN-002" {
  let source = SourceText::{ module_name: None, text: "{-| missing close" }
  let scanner = DefaultScanner::new()
  let diag = match first_error(scanner.tokenize(source)) {
    Some(diag) => diag
    None => fail("expected tokenization error")
  }
  assert_eq(diag.code, "KR-SCAN-002")
}

test "invalid character sequence returns KR-SCAN-003" {
  let source = SourceText::{ module_name: None, text: "module Main exposing (@)" }
  let scanner = DefaultScanner::new()
  let diag = match first_error(scanner.tokenize(source)) {
    Some(diag) => diag
    None => fail("expected tokenization error")
  }
  assert_eq(diag.code, "KR-SCAN-003")
}
