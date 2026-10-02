///|
/// Why `format` gives no text.
pub suberror FormatError {
  /// The source has a diagnostic with severity `Error`.
  ParseFailed(Array[@scanner.Diagnostic])
  /// The parsed file cannot print (for example a comment that the printer
  /// cannot place).
  Unprintable(PrintError)
} derive(Debug)

///|
/// Formats Elm source as elm-format 0.8.7 does (`layout=ElmFormat`, the
/// default), or with the line-width layout of `print_file`
/// (`layout=Width(n)`). Comments stay in place. Raises `ParseFailed` when
/// the source has a syntax error in `dialect`.
///
/// ```mbt nocheck
/// test {
///   let source = "module A exposing (a)\n\na = f x\n  y\n"
///   inspect(
///     @printer.format(source),
///     content=(
///       #|module A exposing (a)
///       #|
///       #|
///       #|a =
///       #|    f x
///       #|        y
///       #|
///     ),
///   )
/// }
/// ```
pub fn format(
  source : String,
  layout? : Layout = ElmFormat,
  dialect? : @dialect.Dialect = @dialect.Dialect::elm_0_19_1(),
) -> String raise FormatError {
  let result = @parser.parse_module(
    @scanner.SourceText::new(source),
    @scanner.DefaultScanner::new(dialect~),
    dialect~,
  )
  format_parsed(result, layout~, dialect~)
}

///|
/// Formats a parse result. Give the dialect that parsed it: the printer
/// uses its operator table. Raises `ParseFailed` when the result has a
/// diagnostic with severity `Error`.
pub fn format_parsed(
  result : @parser.ParseResult,
  layout? : Layout = ElmFormat,
  dialect? : @dialect.Dialect = @dialect.Dialect::elm_0_19_1(),
) -> String raise FormatError {
  let errors = result.diagnostics.filter(d => d.severity is Error)
  guard errors.is_empty() && result.ast is Some(file) && result.cst is Some(cst) else {
    raise ParseFailed(errors)
  }
  let ctx = Ctx::new(
    dialect,
    layout~,
    source=Some(SourceFacts::from_tokens(cst.tokens)),
  )
  let doc = ctx.file_doc(file) catch { e => raise Unprintable(e) }
  @pretty.render(doc, width=layout.render_width())
}
