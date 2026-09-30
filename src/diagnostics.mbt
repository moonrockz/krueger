///|
/// Description of each scanner and parser diagnostic code, for reports and
/// documentation. A diagnostic's own `message` can add detail (for example the
/// unsupported construct); this is the fixed meaning of the code.
let diagnostic_descriptions : Map[String, String] = {
  "KR-SCAN-001": "Unterminated block comment",
  "KR-SCAN-002": "Malformed doc comment",
  "KR-SCAN-003": "Invalid or unknown character sequence",
  "KR-SCAN-004": "Unterminated string, char or GLSL literal",
  "KR-PARSE-001": "Malformed module header (no AST)",
  "KR-PARSE-002": "Malformed import declaration",
  "KR-PARSE-003": "Malformed type declaration",
  "KR-PARSE-004": "Malformed function declaration",
  "KR-PARSE-005": "Unsupported syntax: the parser cannot produce this construct yet",
  "KR-PARSE-006": "Missing module header (no AST)",
  "KR-PARSE-007": "Unexpected syntax that elm-syntax rejects (skipped tokens, stray doc comments)",
  "KR-PARSE-008": "Syntax error in a port or infix declaration",
  "KR-PARSE-009": "Number literal out of range (warning)",
}

///|
/// The fixed meaning of a diagnostic code, or `None` for an unknown code.
pub fn diagnostic_description(code : String) -> String? {
  diagnostic_descriptions.get(code)
}
