///|
/// elm-syntax 7.3.9 model. `Elm.Syntax.Comments.Comment` is not re-exported
/// because the scanner's `Comment` type uses the same name.
pub using @ast {
  type Location,
  type Range,
  type Node,
  type ModuleName,
  type File,
  type Module,
  type DefaultModuleData,
  type EffectModuleData,
  type Exposing,
  type TopLevelExpose,
  type ExposedType,
  type Import,
  type Declaration,
  type Function,
  type FunctionImplementation,
  type Signature,
  type Documentation,
  type TypeAlias,
  type Type,
  type ValueConstructor,
  type TypeAnnotation,
  type RecordField,
  type RecordDefinition,
  type Pattern,
  type QualifiedNameRef,
  type Expression,
  type RecordSetter,
  type LetBlock,
  type LetDeclaration,
  type Lambda,
  type CaseBlock,
  type Case,
  type Cases,
  type Infix,
  type InfixDirection,
  type DecodeError,
}

///|
/// Scanner types: source text, tokens, trivia, positions, spans and
/// diagnostics (with their report blocks).
pub using @scanner {
  trait Scanner,
  type Severity,
  type Position,
  type Span,
  type SourceText,
  type Diagnostic,
  type Block,
  type Chunk,
  type Color,
  type CommentKind,
  type KeywordKind,
  type Comment,
  type Trivia,
  type TokenKind,
  type Token,
  type TokenStream,
  type ScanErrorList,
  is_lower_start,
  is_upper_start,
  is_name_part,
}

///|
/// Concrete syntax tree: every token and top-level declaration, with trivia.
pub using @cst {
  type ModuleHeaderCst,
  type ImportCst,
  type FunctionCst,
  type TypeAliasCst,
  type UnionTypeCst,
  type DeclarationCst,
  type ModuleCst,
}

///|
/// The parse result and doc-comment attributes.
pub using @parser {
  type ParseResult,
  type AttributeTarget,
  type DocAttribute,
  type AttributeGroup,
  encode_attributes,
  encode_attributes_with,
}

///|
/// Diagnostic renderers: `elm make` text (plain or with ANSI colors),
/// `elm make --report=json`, and krueger's own JSON.
pub using @report {
  render_plain,
  render_terminal,
  render_elm_json,
  encode_diagnostics,
}

///|
/// Read-only node model over a parse result, and its traversals (`walk`,
/// `fold`, `accept`, events, `TreeCursor`).
pub using @syntax {
  type NodeRef,
  type Tree,
  type Control,
  trait Visitor,
  kind_table,
  walk,
  fold,
  accept,
  type Event,
  type EnterEvent,
  type LeaveEvent,
  type NodePath,
  type PathStep,
  trait EventSource,
  type EventReader,
  trait Handler,
  push_events,
  type TreeCursor,
}

///|
/// Dialects: rejection rules, operator table and other extension data.
pub using @dialect {
  type Dialect,
  type OperatorDef,
  type AttributeSyntax,
  type Rule,
  standard_operators,
}

///|
/// Elm source from an AST, in the elm-format layout and fitted to a line
/// width (default 120).
pub using @printer {
  print_file,
  print_declaration,
  print_expression,
  print_pattern,
  print_type_annotation,
  type PrintError,
  type PrintProblem,
  type NameKind,
}

///|
/// The version of krueger, the same as `version` in `moon.mod`.
///
/// ```mbt check
/// test {
///   inspect(@krueger.version().split(".").count(), content="3")
/// }
/// ```
pub fn version() -> String {
  "0.3.0"
}

///|
/// Tokenize `source` in `dialect` (default: Elm 0.19.1).
///
/// The stream is lossless: each token's `trivia_before`, `lexeme` and
/// `trivia_after` rebuild the source. Whitespace and comments are trivia,
/// not tokens. A scan error (for example an unterminated string) gives `Err`
/// with the diagnostics. Use the same dialect for `parse_tokens`.
///
/// ```mbt check
/// test {
///   let source = @krueger.SourceText::new("x = 1 -- one\n")
///   guard @krueger.tokenize(source) is Ok(stream) else { fail("scan error") }
///   debug_inspect(
///     stream.tokens.map(t => t.lexeme),
///     content=(
///       #|["x", "=", "1"]
///     ),
///   )
///   // The comment is trivia after the last token.
///   inspect(stream.tokens[2].trivia_after.length() > 0, content="true")
///   let bad = @krueger.SourceText::new("s = \"abc\n")
///   guard @krueger.tokenize(bad) is Err(errors) else { fail("no error") }
///   inspect(errors.diagnostics[0].code, content="KR-SCAN-004")
/// }
/// ```
pub fn tokenize(
  source : SourceText,
  dialect? : Dialect = Dialect::elm_0_19_1(),
) -> Result[TokenStream, ScanErrorList] {
  @scanner.DefaultScanner::new(dialect~).tokenize(source)
}

///|
/// Tokenize and parse `source` in `dialect` (default: Elm 0.19.1).
///
/// The result has the elm-syntax AST (`ast`), the CST (`cst`), the
/// diagnostics and the doc-comment attributes. The parser does not stop at
/// the first error: a declaration that does not parse is left out of the
/// AST and the CST, and is reported. `ast` is `None` only when the module
/// header is missing or malformed, or when the source does not scan. Check
/// `diagnostics` for an entry with severity `Error` before you trust the
/// AST.
///
/// ```mbt check
/// test {
///   let source = @krueger.SourceText::new(
///     "module Main exposing (main)\n\nmain =\n    1 + 2\n",
///   )
///   let result = @krueger.parse_module(source)
///   inspect(result.diagnostics.length(), content="0")
///   guard result.ast is Some(file) else { fail("no AST") }
///   guard file.declarations[0].value is FunctionDeclaration(f) else {
///     fail("not a function")
///   }
///   inspect(f.declaration.value.name.value, content="main")
///   debug_inspect(
///     f.declaration.value.name.range,
///     content="{ start: { row: 3, column: 1 }, end: { row: 3, column: 5 } }",
///   )
/// }
/// ```
///
/// A syntax error is a diagnostic with a code, a title and a message:
///
/// ```mbt check
/// test {
///   let source = @krueger.SourceText::new(
///     "module Main exposing (..)\n\nmain =\n    (1 + 2\n\nother = 3\n",
///   )
///   let result = @krueger.parse_module(source)
///   let d = result.diagnostics[0]
///   inspect(d.code, content="KR-PARSE-004")
///   inspect(d.title, content="UNFINISHED PARENTHESES")
///   debug_inspect(d.severity, content="Error")
///   // The declaration after the error still parses.
///   guard result.ast is Some(file) else { fail("no AST") }
///   inspect(file.declarations.length(), content="1")
/// }
/// ```
///
/// Pass a dialect to accept or reject other syntax. `elm make` rejects a
/// leading zero; elm-syntax 7.3.9 accepts it:
///
/// ```mbt check
/// test {
///   let source = @krueger.SourceText::new(
///     "module Main exposing (..)\n\nx =\n    007\n",
///   )
///   let strict = @krueger.parse_module(source)
///   inspect(
///     strict.diagnostics[0].message,
///     content="Malformed function declaration: numbers cannot start with zeros [rule: leading-zero]",
///   )
///   let lenient = @krueger.parse_module(
///     source,
///     dialect=@krueger.Dialect::elm_syntax_7_3_9(),
///   )
///   inspect(lenient.diagnostics.length(), content="0")
/// }
/// ```
pub fn parse_module(
  source : SourceText,
  dialect? : Dialect = Dialect::elm_0_19_1(),
) -> ParseResult {
  @parser.parse_module(source, @scanner.DefaultScanner::new(dialect~), dialect~)
}

///|
/// Parse a token stream in `dialect` (default: Elm 0.19.1).
///
/// Use it when you already have the tokens from `tokenize`. Tokenize and
/// parse with the same dialect: the dialect's reserved words and operator
/// symbols change the tokens. `parse_module` does both steps.
///
/// ```mbt check
/// test {
///   let dialect = @krueger.Dialect::elm_0_19_1()
///   let source = @krueger.SourceText::new("module Main exposing (..)\n\nx = 1\n")
///   guard @krueger.tokenize(source, dialect~) is Ok(tokens) else {
///     fail("scan error")
///   }
///   let result = @krueger.parse_tokens(tokens, dialect~)
///   inspect(result.diagnostics.length(), content="0")
///   inspect(result == @krueger.parse_module(source, dialect~), content="true")
/// }
/// ```
pub fn parse_tokens(
  tokens : TokenStream,
  dialect? : Dialect = Dialect::elm_0_19_1(),
) -> ParseResult {
  @parser.parse_tokens(tokens, dialect~)
}
