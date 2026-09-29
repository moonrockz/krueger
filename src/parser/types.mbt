///|
/// Result of parsing one Elm module.
///
/// `ast` is the elm-syntax AST, present when the module header is valid.
/// `cst` keeps every token and every declaration. `diagnostics` lists scanner
/// and parser problems, including syntax the parser cannot produce yet
/// (`KR-PARSE-005`).
pub(all) struct ParseResult {
  ast : @ast.File?
  cst : @cst.ModuleCst?
  diagnostics : Array[@scanner.Diagnostic]
} derive(Eq, Debug)
