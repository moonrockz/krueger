///|
/// Result of parsing one Elm module.
///
/// `ast` is the elm-syntax AST, present when the module header is valid.
/// `cst` keeps every token and every declaration that parses. `diagnostics`
/// lists scanner and parser problems.
pub(all) struct ParseResult {
  ast : @ast.File?
  cst : @cst.ModuleCst?
  diagnostics : Array[@scanner.Diagnostic]
  /// Attributes from doc comments (see `DocAttribute`), in source order.
  attributes : Array[AttributeGroup]
} derive(Eq, Debug)

///|
/// What a group of doc-comment attributes belongs to.
pub(all) enum AttributeTarget {
  Module
  Declaration(name~ : String, range~ : @ast.Range)
} derive(Eq, Debug)

///|
/// One attribute line in a doc comment: `@name value...`, or the built-in
/// `@docs a, b` list.
pub(all) enum DocAttribute {
  Attribute(
    name~ : @ast.Node[String],
    arguments~ : Array[@ast.Node[@ast.Expression]],
    range~ : @ast.Range
  )
  Docs(names~ : Array[@ast.Node[String]], range~ : @ast.Range)
} derive(Eq, Debug)

///|
/// The attributes of the module or of one declaration, in source order.
pub(all) struct AttributeGroup {
  target : AttributeTarget
  attributes : Array[DocAttribute]
} derive(Eq, Debug)
