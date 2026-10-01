///|
/// The module header, from `module` (or `port module`, `effect module`) to
/// the end of its exposing list.
///
/// - `module_name` is the dotted name, such as `Some("Html.Events")`.
/// - `exposing` lists the exposed names in source order. It is empty for
///   `exposing (..)`. A type exposed with `(..)` gives only its name.
/// - `tokens` are the header's tokens, with their trivia.
/// - `span` runs from the first token to the end of the last token.
pub(all) struct ModuleHeaderCst {
  module_name : String?
  exposing : Array[String]
  tokens : Array[@scanner.Token]
  span : @scanner.Span
} derive(Eq, Debug)

///|
/// One import declaration.
///
/// - `module_name` is the dotted name of the imported module.
/// - `exposing` is `None` when there is no `exposing` clause, and
///   `Some([])` for `exposing (..)`. Otherwise it lists the exposed names.
/// - `tokens` and `span` cover the declaration, alias included.
pub(all) struct ImportCst {
  module_name : String
  exposing : Array[String]?
  tokens : Array[@scanner.Token]
  span : @scanner.Span
} derive(Eq, Debug)

///|
/// A top-level function or value declaration.
///
/// - `args` has one short text per argument pattern: the variable name, `_`,
///   `()`, the constructor name of a constructor pattern, or `_` for any
///   other pattern.
/// - `tokens` and `span` cover the signature (when there is one) and the
///   definition. A doc comment is trivia of the first token; `span` does not
///   include it.
pub(all) struct FunctionCst {
  name : String
  args : Array[String]
  tokens : Array[@scanner.Token]
  span : @scanner.Span
} derive(Eq, Debug)

///|
/// A `type alias` declaration. `type_params` are the type variable names,
/// in order.
pub(all) struct TypeAliasCst {
  name : String
  type_params : Array[String]
  tokens : Array[@scanner.Token]
  span : @scanner.Span
} derive(Eq, Debug)

///|
/// A custom type declaration (`type T = A | B`). `type_params` are the type
/// variable names, in order.
pub(all) struct UnionTypeCst {
  name : String
  type_params : Array[String]
  tokens : Array[@scanner.Token]
  span : @scanner.Span
} derive(Eq, Debug)

///|
/// A top-level declaration in the CST. Ports, infix declarations and
/// destructurings have no CST form, so they do not show here.
pub(all) enum DeclarationCst {
  Function(FunctionCst)
  TypeAlias(TypeAliasCst)
  UnionType(UnionTypeCst)
} derive(Eq, Debug)

///|
/// The concrete syntax tree of a module: every token, with its trivia, plus
/// the header, imports and top-level declarations as token ranges.
///
/// - `tokens` is the whole token stream, so it keeps every comment and all
///   whitespace except in a text with no tokens.
/// - `header` is `None` when the module header is missing or malformed.
/// - A declaration that does not parse is left out of `imports` and
///   `declarations`, and reported as a diagnostic.
/// - `span` runs from the first token to the end of the last token; it is
///   `None` when there is no token.
///
/// The parser makes it (`@parser.ParseResult::cst`). It is `None` there only
/// when the scan fails.
///
/// ```mbt check
/// test {
///   let source = @scanner.SourceText::new(
///     (
///       #|module Shapes exposing (Shape(..), area)
///       #|
///       #|import Html exposing (text)
///       #|
///       #|type Shape a = Circle a | Square a
///       #|
///       #|type alias Size = Float
///       #|
///       #|area : Shape Float -> Float
///       #|area shape = 0
///     ),
///   )
///   let result = @parser.parse_module(source, @scanner.DefaultScanner::new())
///   guard result.cst is Some(module_cst) else { fail("no CST") }
///   debug_inspect(
///     module_cst.header.map(h => (h.module_name, h.exposing)),
///     content="Some((Some(\"Shapes\"), [\"Shape\", \"area\"]))",
///   )
///   debug_inspect(
///     module_cst.imports.map(i => (i.module_name, i.exposing)),
///     content="[(\"Html\", Some([\"text\"]))]",
///   )
///   let declarations = module_cst.declarations.map(d => {
///     match d {
///       Function(f) => ("function", f.name, f.args)
///       TypeAlias(a) => ("alias", a.name, a.type_params)
///       UnionType(t) => ("type", t.name, t.type_params)
///     }
///   })
///   debug_inspect(
///     declarations,
///     content=(
///       #|[
///       #|  ("type", "Shape", ["a"]),
///       #|  ("alias", "Size", []),
///       #|  ("function", "area", ["shape"]),
///       #|]
///     ),
///   )
///   // The function covers its signature and its definition.
///   guard module_cst.declarations[2] is Function(area) else { fail("no area") }
///   inspect(area.tokens[0].lexeme, content="area")
///   debug_inspect((area.span.start.line, area.span.end.line), content="(9, 10)")
/// }
/// ```
pub(all) struct ModuleCst {
  tokens : Array[@scanner.Token]
  header : ModuleHeaderCst?
  imports : Array[ImportCst]
  declarations : Array[DeclarationCst]
  span : @scanner.Span?
} derive(Eq, Debug)
