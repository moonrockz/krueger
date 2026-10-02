///|
/// The kind of name that a `PrintProblem::InvalidName` is about.
pub(all) enum NameKind {
  /// A value, variable, field or type variable: `x`, `map`.
  Lower
  /// A module segment, type or constructor: `Maybe`, `Just`.
  Upper
  /// An operator symbol: `|>`.
  Operator
} derive(Eq, Debug)

///|
/// Why an AST cannot print as valid Elm.
pub(all) enum PrintProblem {
  /// A name that the scanner does not accept, a reserved word, or an
  /// operator symbol that is not in the dialect's operator table (Elm 0.19
  /// has no user-defined operators).
  InvalidName(NameKind, String)
  /// A module name with no segments.
  EmptyModuleName
  /// NaN or infinity; Elm has no literal for them.
  NonFiniteFloat(Double)
  /// An `Integer` or `Hex` equal to the smallest `Int64`: its negation has
  /// no positive literal.
  UnrepresentableInt(Int64)
  /// A negative `IntPattern`, `HexPattern` or `FloatPattern`; Elm has no
  /// negative literal pattern.
  NegativePattern
  /// An application with fewer than 2 items.
  ShortApplication
  /// A tuple with fewer than 2 items.
  ShortTuple
  /// A record update, an extensible record type or an effect module
  /// `where` clause with no fields.
  NoFields
  /// An explicit exposing list with no items.
  EmptyExposing
  /// A `case` with no branches.
  EmptyCase
  /// A `let` with no declarations.
  EmptyLet
  /// A custom type with no constructors.
  NoConstructors
  /// A lambda with no arguments.
  NoLambdaArguments
  /// An operator that is not in the dialect's operator table.
  UnknownOperator(String)
  /// An infix declaration whose precedence is not 0 to 9.
  InvalidPrecedence(Int)
  /// GLSL text that holds `|]`.
  InvalidGlsl
  /// Documentation that does not start with `{-|` and end with `-}`.
  InvalidDocumentation
  /// Documentation on a function in a `let`; Elm has no doc comments there.
  LetDocumentation
  /// More than 400 nested printer levels.
  TooDeep
} derive(Eq, Debug)

///|
/// An AST that cannot print as valid Elm. `path` leads from the node given
/// to the printer to the bad node, with elm-syntax JSON field names (see
/// `NodePath`); for `print_file` it starts at the file.
pub suberror PrintError {
  PrintError(path~ : @syntax.NodePath, problem~ : PrintProblem)
} derive(Debug)

///|
/// Settings for one print call.
priv struct Ctx {
  dialect : @dialect.Dialect
  layout : Layout
  /// The facts of the parsed source; `None` for an AST built by hand.
  source : SourceFacts?
}

///|
fn Ctx::new(
  dialect : @dialect.Dialect,
  layout? : Layout = Width(120),
  source? : SourceFacts? = None,
) -> Ctx {
  { dialect, layout, source, }
}

///|
/// The deepest nesting the printer accepts. Operator chains, record access
/// chains, function type arrows, `else if` chains and application items do
/// not add levels, so every AST the parser returns is inside this limit.
let max_level : Int = 400

///|
fn check_level(path : @syntax.NodePath, level : Int) -> Unit raise PrintError {
  if level > max_level {
    raise PrintError(path~, problem=TooDeep)
  }
}
