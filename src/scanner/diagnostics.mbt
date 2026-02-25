fn scanner_error(code : String, message : String, span : Span) -> Diagnostic {
  Diagnostic::{ code, severity: Severity::Error, message, span }
}

pub fn unterminated_block_comment(span : Span) -> Diagnostic {
  scanner_error(
    "KR-SCAN-001",
    "Unterminated block comment",
    span,
  )
}

pub fn malformed_doc_comment(span : Span) -> Diagnostic {
  scanner_error(
    "KR-SCAN-002",
    "Malformed doc comment",
    span,
  )
}

pub fn invalid_sequence(span : Span) -> Diagnostic {
  scanner_error(
    "KR-SCAN-003",
    "Invalid or unknown character sequence",
    span,
  )
}
