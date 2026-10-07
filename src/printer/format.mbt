///|
/// Why `format` gives no text.
///
/// ```mbt check
/// test {
///   let failed = try @printer.format("module A exposing (a)\n\na = (\n") catch {
///     ParseFailed(diagnostics) => diagnostics.length() > 0
///     Unprintable(_) => false
///   } noraise {
///     _ => false
///   }
///   inspect(failed, content="true")
/// }
/// ```
pub suberror FormatError {
  /// The source has a diagnostic with severity `Error` (the diagnostics
  /// with that severity). Render them with `@report.render_plain` or
  /// `@report.render_terminal`.
  ParseFailed(Array[@scanner.Diagnostic])
  /// The parsed file cannot print: a comment that the printer cannot place
  /// (`UnplacedComment`), or a problem that `print_file` also raises.
  Unprintable(PrintError)
} derive(Debug)

///|
/// Formats Elm source as elm-format 0.8.7 does (`layout=ElmFormat`, the
/// default), or with the line-width layout of `print_file`
/// (`layout=Width(n)`).
///
/// - The output is the source of `normalize_file(ast)`: exposed items and
///   imports in elm-format's order, elm-format's parentheses and literal
///   forms, and doc comments with their Markdown and Elm code formatted.
/// - Every regular comment prints once, where elm-format puts it: a
///   comment leads the node after it, trails the node before it on its
///   line, or goes before the closing token of its container. A comment
///   moves with an exposed item or an import that elm-format reorders. A
///   block comment gets elm-format's form (`{-a-}` gives `{- a -}`).
///   No comment is dropped: one that the printer cannot place raises
///   `Unprintable` with `UnplacedComment`.
/// - Raises `ParseFailed` when the source has a syntax error in
///   `dialect`.
///
/// `format(format(s)) == format(s)`, except for the doc comments on which
/// elm-format 0.8.7 is not idempotent (see `normalize_file`).
///
/// ```mbt check
/// test {
///   let source = "module A exposing (a)\n\na = f x -- why\n  y\n"
///   inspect(
///     @printer.format(source),
///     content=(
///       #|module A exposing (a)
///       #|
///       #|
///       #|a =
///       #|    f x
///       #|        -- why
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
  format_source(source, layout, dialect, 0)
}

///|
/// `format` for code inside `doc_depth` doc comments.
fn format_source(
  source : String,
  layout : Layout,
  dialect : @dialect.Dialect,
  doc_depth : Int,
) -> String raise FormatError {
  let result = @parser.parse_module(
    @scanner.SourceText::new(source),
    @scanner.DefaultScanner::new(dialect~),
    dialect~,
  )
  format_parsed_at(result, layout, dialect, doc_depth)
}

///|
/// Formats a parse result, as `format` formats source. Give the dialect
/// that parsed it: the printer uses its operator table. Raises
/// `ParseFailed` when the result has a diagnostic with severity `Error`.
/// Use it when the parse result is already there, for example after a
/// check of its diagnostics.
///
/// ```mbt check
/// test {
///   let result = @parser.parse_module(
///     @scanner.SourceText::new("module A exposing (a)\n\na = [1,2]\n"),
///     @scanner.DefaultScanner::new(),
///   )
///   inspect(
///     @printer.format_parsed(result, layout=Width(40)),
///     content=(
///       #|module A exposing (a)
///       #|
///       #|
///       #|a =
///       #|    [ 1, 2 ]
///       #|
///     ),
///   )
/// }
/// ```
pub fn format_parsed(
  result : @parser.ParseResult,
  layout? : Layout = ElmFormat,
  dialect? : @dialect.Dialect = @dialect.Dialect::elm_0_19_1(),
) -> String raise FormatError {
  format_parsed_at(result, layout, dialect, 0)
}

///|
/// `format_parsed` for code inside `doc_depth` doc comments.
fn format_parsed_at(
  result : @parser.ParseResult,
  layout : Layout,
  dialect : @dialect.Dialect,
  doc_depth : Int,
) -> String raise FormatError {
  let errors = result.diagnostics.filter(d => d.severity is Error)
  guard errors.is_empty() && result.ast is Some(file) && result.cst is Some(cst) else {
    raise ParseFailed(errors)
  }
  let comments = place_comments(file)
  let ctx = Ctx::new(
    dialect,
    layout~,
    source=Some(SourceFacts::from_tokens(cst.tokens)),
    comments=Some(comments),
    doc_depth~,
  )
  let doc = ctx.file_doc(file) catch { e => raise Unprintable(e) }
  if comments.unprinted() is Some(r) {
    raise Unprintable(
      PrintError(path=@syntax.NodePath::root(), problem=UnplacedComment(r)),
    )
  }
  @pretty.render(doc, width=layout.render_width())
}
