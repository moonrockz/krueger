// MoonBit mirror of the stil4m/elm-syntax 7.3.9 AST (Elm.Syntax.*).
// Each type maps one-to-one to its elm-syntax counterpart. Elm tuples used as
// named records (RecordField, RecordSetter, Case) become structs whose fields
// keep the JSON key names.

///|
/// Elm.Syntax.Range.Location: a point in the source. `row` is the line and
/// `column` the column, both counted from 1. Columns count code points, so a
/// character outside the BMP (a surrogate pair) is one column.
#derive(Eq, Debug)
pub(all) struct Location {
  row : Int32
  column : Int32
}

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
#derive(Eq, Debug)
pub(all) struct Range {
  start : Location
  end : Location
}

///|
/// Elm.Syntax.Node.Node: a value with its source range. Most parts of the
/// AST are nodes: names, expressions, patterns, type annotations and
/// declarations.
#derive(Eq, Debug)
pub(all) struct Node[T] {
  range : Range
  value : T
}

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
#derive(Eq, Debug)
pub(all) struct File {
  module_definition : Node[Module]
  imports : ArrayView[Node[Import]]
  declarations : ArrayView[Node[Declaration]]
  comments : ArrayView[Node[Comment]]
}

///|
/// Elm.Syntax.Module.Module
#derive(Eq, Debug)
pub(all) enum Module {
  NormalModule(DefaultModuleData)
  PortModule(DefaultModuleData)
  EffectModule(EffectModuleData)
}

///|
/// Elm.Syntax.Module.DefaultModuleData
#derive(Eq, Debug)
pub(all) struct DefaultModuleData {
  module_name : Node[ModuleName]
  exposing_list : Node[Exposing]
}

///|
/// Elm.Syntax.Module.EffectModuleData
#derive(Eq, Debug)
pub(all) struct EffectModuleData {
  module_name : Node[ModuleName]
  exposing_list : Node[Exposing]
  command : Node[String]?
  subscription : Node[String]?
}

///|
/// Elm.Syntax.Exposing.Exposing
#derive(Eq, Debug)
pub(all) enum Exposing {
  All(Range)
  Explicit(ArrayView[Node[TopLevelExpose]])
}

///|
/// Elm.Syntax.Exposing.TopLevelExpose
#derive(Eq, Debug)
pub(all) enum TopLevelExpose {
  InfixExpose(String)
  FunctionExpose(String)
  TypeOrAliasExpose(String)
  TypeExpose(ExposedType)
}

///|
/// Elm.Syntax.Exposing.ExposedType
#derive(Eq, Debug)
pub(all) struct ExposedType {
  name : String
  open : Range?
}

///|
/// Elm.Syntax.Import.Import
#derive(Eq, Debug)
pub(all) struct Import {
  module_name : Node[ModuleName]
  module_alias : Node[ModuleName]?
  exposing_list : Node[Exposing]?
}

///|
/// Elm.Syntax.Declaration.Declaration
#derive(Eq, Debug)
pub(all) enum Declaration {
  FunctionDeclaration(Function)
  AliasDeclaration(TypeAlias)
  CustomTypeDeclaration(Type)
  PortDeclaration(Signature)
  InfixDeclaration(Infix)
  Destructuring(Node[Pattern], Node[Expression])
}

///|
/// Elm.Syntax.Infix.Infix
#derive(Eq, Debug)
pub(all) struct Infix {
  direction : Node[InfixDirection]
  precedence : Node[Int32]
  operator : Node[String]
  function : Node[String]
}

///|
/// Elm.Syntax.Infix.InfixDirection
#derive(Eq, Debug)
pub(all) enum InfixDirection {
  Left
  Right
  Non
}

///|
/// Elm.Syntax.Signature.Signature
#derive(Eq, Debug)
pub(all) struct Signature {
  name : Node[String]
  type_annotation : Node[TypeAnnotation]
}

///|
/// Elm.Syntax.TypeAlias.TypeAlias
#derive(Eq, Debug)
pub(all) struct TypeAlias {
  documentation : Node[Documentation]?
  name : Node[String]
  generics : ArrayView[Node[String]]
  type_annotation : Node[TypeAnnotation]
}

///|
/// Elm.Syntax.Type.Type
#derive(Eq, Debug)
pub(all) struct Type {
  documentation : Node[Documentation]?
  name : Node[String]
  generics : ArrayView[Node[String]]
  constructors : ArrayView[Node[ValueConstructor]]
}

///|
/// Elm.Syntax.Type.ValueConstructor
#derive(Eq, Debug)
pub(all) struct ValueConstructor {
  name : Node[String]
  arguments : ArrayView[Node[TypeAnnotation]]
}

///|
/// Elm.Syntax.TypeAnnotation.TypeAnnotation
#derive(Eq, Debug)
pub(all) enum TypeAnnotation {
  GenericType(String)
  Typed(Node[(ModuleName, String)], ArrayView[Node[TypeAnnotation]])
  Unit
  Tupled(ArrayView[Node[TypeAnnotation]])
  Record(RecordDefinition)
  GenericRecord(Node[String], Node[RecordDefinition])
  FunctionTypeAnnotation(Node[TypeAnnotation], Node[TypeAnnotation])
}

///|
/// Elm.Syntax.TypeAnnotation.RecordDefinition
pub type RecordDefinition = ArrayView[Node[RecordField]]

///|
/// Elm.Syntax.TypeAnnotation.RecordField (an Elm tuple `( Node String, Node TypeAnnotation )`)
#derive(Eq, Debug)
pub(all) struct RecordField {
  name : Node[String]
  type_annotation : Node[TypeAnnotation]
}

///|
/// Elm.Syntax.Pattern.Pattern
#derive(Eq, Debug)
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
}

///|
/// Elm.Syntax.Pattern.QualifiedNameRef
#derive(Eq, Debug)
pub(all) struct QualifiedNameRef {
  module_name : ModuleName
  name : String
}

///|
/// Elm.Syntax.Expression.Function
#derive(Eq, Debug)
pub(all) struct Function {
  documentation : Node[Documentation]?
  signature : Node[Signature]?
  declaration : Node[FunctionImplementation]
}

///|
/// Elm.Syntax.Expression.FunctionImplementation
#derive(Eq, Debug)
pub(all) struct FunctionImplementation {
  name : Node[String]
  arguments : ArrayView[Node[Pattern]]
  expression : Node[Expression]
}

///|
/// Elm.Syntax.Expression.Expression
#derive(Eq, Debug)
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
}

///|
/// Elm.Syntax.Expression.RecordSetter (an Elm tuple `( Node String, Node Expression )`)
#derive(Eq, Debug)
pub(all) struct RecordSetter {
  field : Node[String]
  expression : Node[Expression]
}

///|
/// Elm.Syntax.Expression.LetBlock
#derive(Eq, Debug)
pub(all) struct LetBlock {
  declarations : ArrayView[Node[LetDeclaration]]
  expression : Node[Expression]
}

///|
/// Elm.Syntax.Expression.LetDeclaration
#derive(Eq, Debug)
pub(all) enum LetDeclaration {
  LetFunction(Function)
  LetDestructuring(Node[Pattern], Node[Expression])
}

///|
/// Elm.Syntax.Expression.Lambda
#derive(Eq, Debug)
pub(all) struct Lambda {
  args : ArrayView[Node[Pattern]]
  expression : Node[Expression]
}

///|
/// Elm.Syntax.Expression.CaseBlock
#derive(Eq, Debug)
pub(all) struct CaseBlock {
  expression : Node[Expression]
  cases : Cases
}

///|
/// Elm.Syntax.Expression.Case (an Elm tuple `( Node Pattern, Node Expression )`)
#derive(Eq, Debug)
pub(all) struct Case {
  pattern : Node[Pattern]
  expression : Node[Expression]
}

///|
/// Elm.Syntax.Expression.Cases
pub type Cases = ArrayView[Case]
