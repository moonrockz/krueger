///|
fn scanner_error(
  code : String,
  message : String,
  span : Span,
  title~ : String,
  report~ : Array[Block],
) -> Diagnostic {
  Diagnostic::{ code, severity: Severity::Error, message, span, title, report, }
}

///|
pub fn unterminated_block_comment(span : Span) -> Diagnostic {
  scanner_error(
    "KR-SCAN-001",
    "Unterminated block comment",
    span,
    title="ENDLESS COMMENT",
    report=[],
  )
}

///|
pub fn malformed_doc_comment(span : Span) -> Diagnostic {
  scanner_error(
    "KR-SCAN-002",
    "Malformed doc comment",
    span,
    title="SYNTAX PROBLEM",
    report=[],
  )
}

///|
pub fn invalid_sequence(span : Span) -> Diagnostic {
  scanner_error(
    "KR-SCAN-003",
    "Invalid or unknown character sequence",
    span,
    title="SYNTAX PROBLEM",
    report=[],
  )
}

///|
pub fn unterminated_literal(span : Span) -> Diagnostic {
  scanner_error(
    "KR-SCAN-004",
    "Unterminated string, char or GLSL literal",
    span,
    title="SYNTAX PROBLEM",
    report=[],
  )
}
