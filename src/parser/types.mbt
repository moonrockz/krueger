///|
/// Result of parsing one Elm module.
///
/// The parser does not stop at the first error. A declaration that does not
/// parse is left out of `ast` and `cst`, and a diagnostic reports it. Check
/// `diagnostics` for an entry with severity `Error` before you use the AST
/// as a full copy of the source.
///
/// ```mbt check
/// test {
///   let source = @scanner.SourceText::new(
///     "module Main exposing (x)\n\n{-| The answer. -}\nx = 42\n",
///   )
///   let result = @parser.parse_module(source, @scanner.DefaultScanner::new())
///   inspect(result.diagnostics.length(), content="0")
///   guard result.ast is Some(file) else { fail("no AST") }
///   inspect(file.declarations.length(), content="1")
///   guard result.cst is Some(cst) else { fail("no CST") }
///   inspect(cst.declarations.length(), content="1")
///   inspect(result.attributes.length(), content="0")
/// }
/// ```
pub(all) struct ParseResult {
  /// The elm-syntax 7.3.9 AST. It is `None` when the module header is
  /// missing or malformed (`KR-PARSE-001`, `KR-PARSE-006`) or when the
  /// source does not scan.
  ast : @ast.File?
  /// The concrete syntax tree: every token, with its trivia, and every
  /// declaration that parses. It is `None` only when the source does not
  /// scan; without a valid module header its `header` is `None`.
  cst : @cst.ModuleCst?
  /// Scanner and parser problems, in source order. Each has a code
  /// (`KR-SCAN-*`, `KR-PARSE-*`, `KR-ATTR-*`), a severity, a message, a span,
  /// the `elm make` title and a long report.
  diagnostics : Array[@scanner.Diagnostic]
  /// Attributes from doc comments (see `DocAttribute`), in source order. It
  /// is empty when the dialect turns attributes off.
  attributes : Array[AttributeGroup]
} derive(Eq, Debug)

///|
/// What a group of doc-comment attributes belongs to: the module (its
/// documentation comment) or one top-level declaration, by name and range.
pub(all) enum AttributeTarget {
  Module
  Declaration(name~ : String, range~ : @ast.Range)
} derive(Eq, Debug)

///|
/// One attribute line in a doc comment: `@name value...`, or the built-in
/// `@docs a, b` list.
///
/// `Attribute` holds the name and the values as elm-syntax expressions.
/// Values are Elm data: literals, lists, records, tuples, names and
/// constructor applications. `range` covers the attribute in the file. A
/// malformed attribute is warning `KR-ATTR-001` and is not in the list.
///
/// ```mbt check
/// test {
///   let text =
///     #|module Main exposing (price)
///     #|
///     #|{-| Prices.
///     #|
///     #|@docs price
///     #|-}
///     #|
///     #|{-| A price.
///     #|
///     #|@unit "EUR"
///     #|-}
///     #|price : Float
///     #|price =
///     #|    9.5
///     #|
///   let source = @scanner.SourceText::new(text)
///   let result = @parser.parse_module(source, @scanner.DefaultScanner::new())
///   inspect(result.diagnostics.length(), content="0")
///   // The first doc comment documents the module.
///   debug_inspect(result.attributes[0].target, content="Module")
///   guard result.attributes[0].attributes[0] is Docs(names~, ..) else {
///     fail("not @docs")
///   }
///   inspect(names[0].value, content="price")
///   // A later doc comment documents the declaration after it.
///   let group = result.attributes[1]
///   guard group.target is Declaration(name~, ..) else {
///     fail("not a declaration")
///   }
///   inspect(name, content="price")
///   guard group.attributes[0] is Attribute(name~, arguments~, ..) else {
///     fail("not an attribute")
///   }
///   inspect(name.value, content="unit")
///   debug_inspect(
///     arguments[0].value,
///     content=(
///       #|Literal("EUR")
///     ),
///   )
/// }
/// ```
pub(all) enum DocAttribute {
  Attribute(
    name~ : @ast.Node[String],
    arguments~ : ArrayView[@ast.Node[@ast.Expression]],
    range~ : @ast.Range
  )
  Docs(names~ : ArrayView[@ast.Node[String]], range~ : @ast.Range)
} derive(Eq, Debug)

///|
/// The attributes of the module or of one declaration, in source order. Only
/// a target with at least one attribute has a group.
pub(all) struct AttributeGroup {
  target : AttributeTarget
  attributes : ArrayView[DocAttribute]
} derive(Eq, Debug)
