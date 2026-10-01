// MoonBit mirror of the stil4m/elm-syntax 7.3.9 AST (Elm.Syntax.*).
// Each type maps one-to-one to its elm-syntax counterpart. Elm tuples used as
// named records (RecordField, RecordSetter, Case) become structs whose fields
// keep the JSON key names.

///|
/// Elm.Syntax.Range.Location: a point in the source. `row` is the line and
/// `column` the column, both counted from 1. Columns count code points, so a
/// character outside the BMP (a surrogate pair) is one column.
pub(all) struct Location {
  row : Int
  column : Int
} derive(Eq, Debug)

///|
/// Elm.Syntax.Range.Range: the source from `start` up to `end`. `end` is
/// the location just after the last character, so `x` in column 1 has the
/// range 1:1 to 1:2. elm-syntax writes it as `[startRow, startColumn,
/// endRow, endColumn]`.
///
/// ```mbt check
/// test {
///   let source = @scanner.SourceText::new(
///     "module Main exposing (..)\n\nname = \"\u{1F600}\" ++ x\n",
///   )
///   let result = @parser.parse_module(source, @scanner.DefaultScanner::new())
///   guard result.ast is Some(file) else { fail("no AST") }
///   let decl = file.declarations[0]
///   debug_inspect(
///     decl.range,
///     content="{ start: { row: 3, column: 1 }, end: { row: 3, column: 16 } }",
///   )
///   inspect(@ast.encode_range(decl.range).stringify(), content="[3,1,3,16]")
/// }
/// ```
pub(all) struct Range {
  start : Location
  end : Location
} derive(Eq, Debug)

///|
/// Elm.Syntax.Node.Node: a value with its source range. Most parts of the
/// AST are nodes: names, expressions, patterns, type annotations and
/// declarations.
pub(all) struct Node[T] {
  range : Range
  value : T
} derive(Eq, Debug)

///|
/// Elm.Syntax.ModuleName.ModuleName
pub type ModuleName = ArrayView[String]

///|
/// Elm.Syntax.Documentation.Documentation
pub type Documentation = String

///|
/// Elm.Syntax.Comments.Comment
pub type Comment = String

///|
/// Elm.Syntax.File.File
pub(all) struct File {
  module_definition : Node[Module]
  imports : ArrayView[Node[Import]]
  declarations : ArrayView[Node[Declaration]]
  comments : ArrayView[Node[Comment]]
} derive(Eq, Debug)

///|
/// Elm.Syntax.Module.Module
pub(all) enum Module {
  NormalModule(DefaultModuleData)
  PortModule(DefaultModuleData)
  EffectModule(EffectModuleData)
} derive(Eq, Debug)

///|
/// Elm.Syntax.Module.DefaultModuleData
pub(all) struct DefaultModuleData {
  module_name : Node[ModuleName]
  exposing_list : Node[Exposing]
} derive(Eq, Debug)

///|
/// Elm.Syntax.Module.EffectModuleData
pub(all) struct EffectModuleData {
  module_name : Node[ModuleName]
  exposing_list : Node[Exposing]
  command : Node[String]?
  subscription : Node[String]?
} derive(Eq, Debug)

///|
/// Elm.Syntax.Exposing.Exposing
pub(all) enum Exposing {
  All(Range)
  Explicit(ArrayView[Node[TopLevelExpose]])
} derive(Eq, Debug)

///|
/// Elm.Syntax.Exposing.TopLevelExpose
pub(all) enum TopLevelExpose {
  InfixExpose(String)
  FunctionExpose(String)
  TypeOrAliasExpose(String)
  TypeExpose(ExposedType)
} derive(Eq, Debug)

///|
/// Elm.Syntax.Exposing.ExposedType
pub(all) struct ExposedType {
  name : String
  open : Range?
} derive(Eq, Debug)

///|
/// Elm.Syntax.Import.Import
pub(all) struct Import {
  module_name : Node[ModuleName]
  module_alias : Node[ModuleName]?
  exposing_list : Node[Exposing]?
} derive(Eq, Debug)

///|
/// Elm.Syntax.Declaration.Declaration
pub(all) enum Declaration {
  FunctionDeclaration(Function)
  AliasDeclaration(TypeAlias)
  CustomTypeDeclaration(Type)
  PortDeclaration(Signature)
  InfixDeclaration(Infix)
  Destructuring(Node[Pattern], Node[Expression])
} derive(Eq, Debug)

///|
/// Elm.Syntax.Infix.Infix
pub(all) struct Infix {
  direction : Node[InfixDirection]
  precedence : Node[Int]
  operator : Node[String]
  function : Node[String]
} derive(Eq, Debug)

///|
/// Elm.Syntax.Infix.InfixDirection
pub(all) enum InfixDirection {
  Left
  Right
  Non
} derive(Eq, Debug)

///|
/// Elm.Syntax.Signature.Signature
pub(all) struct Signature {
  name : Node[String]
  type_annotation : Node[TypeAnnotation]
} derive(Eq, Debug)

///|
/// Elm.Syntax.TypeAlias.TypeAlias
pub(all) struct TypeAlias {
  documentation : Node[Documentation]?
  name : Node[String]
  generics : ArrayView[Node[String]]
  type_annotation : Node[TypeAnnotation]
} derive(Eq, Debug)

///|
/// Elm.Syntax.Type.Type
pub(all) struct Type {
  documentation : Node[Documentation]?
  name : Node[String]
  generics : ArrayView[Node[String]]
  constructors : ArrayView[Node[ValueConstructor]]
} derive(Eq, Debug)

///|
/// Elm.Syntax.Type.ValueConstructor
pub(all) struct ValueConstructor {
  name : Node[String]
  arguments : ArrayView[Node[TypeAnnotation]]
} derive(Eq, Debug)

///|
/// Elm.Syntax.TypeAnnotation.TypeAnnotation
pub(all) enum TypeAnnotation {
  GenericType(String)
  Typed(Node[(ModuleName, String)], ArrayView[Node[TypeAnnotation]])
  Unit
  Tupled(ArrayView[Node[TypeAnnotation]])
  Record(RecordDefinition)
  GenericRecord(Node[String], Node[RecordDefinition])
  FunctionTypeAnnotation(Node[TypeAnnotation], Node[TypeAnnotation])
} derive(Eq, Debug)

///|
/// Elm.Syntax.TypeAnnotation.RecordDefinition
pub type RecordDefinition = ArrayView[Node[RecordField]]

///|
/// Elm.Syntax.TypeAnnotation.RecordField (an Elm tuple `( Node String, Node TypeAnnotation )`)
pub(all) struct RecordField {
  name : Node[String]
  type_annotation : Node[TypeAnnotation]
} derive(Eq, Debug)

///|
/// Elm.Syntax.Pattern.Pattern
pub(all) enum Pattern {
  AllPattern
  UnitPattern
  CharPattern(Char)
  StringPattern(String)
  IntPattern(Int64)
  HexPattern(Int64)
  FloatPattern(Double)
  TuplePattern(ArrayView[Node[Pattern]])
  RecordPattern(ArrayView[Node[String]])
  UnConsPattern(Node[Pattern], Node[Pattern])
  ListPattern(ArrayView[Node[Pattern]])
  VarPattern(String)
  NamedPattern(QualifiedNameRef, ArrayView[Node[Pattern]])
  AsPattern(Node[Pattern], Node[String])
  ParenthesizedPattern(Node[Pattern])
} derive(Eq, Debug)

///|
/// Elm.Syntax.Pattern.QualifiedNameRef
pub(all) struct QualifiedNameRef {
  module_name : ModuleName
  name : String
} derive(Eq, Debug)

///|
/// Elm.Syntax.Expression.Function
pub(all) struct Function {
  documentation : Node[Documentation]?
  signature : Node[Signature]?
  declaration : Node[FunctionImplementation]
} derive(Eq, Debug)

///|
/// Elm.Syntax.Expression.FunctionImplementation
pub(all) struct FunctionImplementation {
  name : Node[String]
  arguments : ArrayView[Node[Pattern]]
  expression : Node[Expression]
} derive(Eq, Debug)

///|
/// Elm.Syntax.Expression.Expression
pub(all) enum Expression {
  UnitExpr
  Application(ArrayView[Node[Expression]])
  OperatorApplication(
    String,
    InfixDirection,
    Node[Expression],
    Node[Expression]
  )
  FunctionOrValue(ModuleName, String)
  IfBlock(Node[Expression], Node[Expression], Node[Expression])
  PrefixOperator(String)
  Operator(String)
  Integer(Int64)
  Hex(Int64)
  Floatable(Double)
  Negation(Node[Expression])
  Literal(String)
  CharLiteral(Char)
  TupledExpression(ArrayView[Node[Expression]])
  ParenthesizedExpression(Node[Expression])
  LetExpression(LetBlock)
  CaseExpression(CaseBlock)
  LambdaExpression(Lambda)
  RecordExpr(ArrayView[Node[RecordSetter]])
  ListExpr(ArrayView[Node[Expression]])
  RecordAccess(Node[Expression], Node[String])
  RecordAccessFunction(String)
  RecordUpdateExpression(Node[String], ArrayView[Node[RecordSetter]])
  GLSLExpression(String)
} derive(Eq, Debug)

///|
/// Elm.Syntax.Expression.RecordSetter (an Elm tuple `( Node String, Node Expression )`)
pub(all) struct RecordSetter {
  field : Node[String]
  expression : Node[Expression]
} derive(Eq, Debug)

///|
/// Elm.Syntax.Expression.LetBlock
pub(all) struct LetBlock {
  declarations : ArrayView[Node[LetDeclaration]]
  expression : Node[Expression]
} derive(Eq, Debug)

///|
/// Elm.Syntax.Expression.LetDeclaration
pub(all) enum LetDeclaration {
  LetFunction(Function)
  LetDestructuring(Node[Pattern], Node[Expression])
} derive(Eq, Debug)

///|
/// Elm.Syntax.Expression.Lambda
pub(all) struct Lambda {
  args : ArrayView[Node[Pattern]]
  expression : Node[Expression]
} derive(Eq, Debug)

///|
/// Elm.Syntax.Expression.CaseBlock
pub(all) struct CaseBlock {
  expression : Node[Expression]
  cases : Cases
} derive(Eq, Debug)

///|
/// Elm.Syntax.Expression.Case (an Elm tuple `( Node Pattern, Node Expression )`)
pub(all) struct Case {
  pattern : Node[Pattern]
  expression : Node[Expression]
} derive(Eq, Debug)

///|
/// Elm.Syntax.Expression.Cases
pub type Cases = ArrayView[Case]
