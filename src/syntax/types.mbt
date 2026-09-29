// MoonBit mirror of the stil4m/elm-syntax 7.3.9 AST (Elm.Syntax.*).
// Each type maps one-to-one to its elm-syntax counterpart. Elm tuples used as
// named records (RecordField, RecordSetter, Case) become structs whose fields
// keep the JSON key names.

///|
/// Elm.Syntax.Range.Location
pub(all) struct Location {
  row : Int
  column : Int
} derive(Eq, Debug)

///|
/// Elm.Syntax.Range.Range
pub(all) struct Range {
  start : Location
  end : Location
} derive(Eq, Debug)

///|
/// Elm.Syntax.Node.Node
pub(all) struct Node[T] {
  range : Range
  value : T
} derive(Eq, Debug)

///|
/// Elm.Syntax.ModuleName.ModuleName
pub type ModuleName = Array[String]

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
  imports : Array[Node[Import]]
  declarations : Array[Node[Declaration]]
  comments : Array[Node[Comment]]
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
  Explicit(Array[Node[TopLevelExpose]])
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
  generics : Array[Node[String]]
  type_annotation : Node[TypeAnnotation]
} derive(Eq, Debug)

///|
/// Elm.Syntax.Type.Type
pub(all) struct Type {
  documentation : Node[Documentation]?
  name : Node[String]
  generics : Array[Node[String]]
  constructors : Array[Node[ValueConstructor]]
} derive(Eq, Debug)

///|
/// Elm.Syntax.Type.ValueConstructor
pub(all) struct ValueConstructor {
  name : Node[String]
  arguments : Array[Node[TypeAnnotation]]
} derive(Eq, Debug)

///|
/// Elm.Syntax.TypeAnnotation.TypeAnnotation
pub(all) enum TypeAnnotation {
  GenericType(String)
  Typed(Node[(ModuleName, String)], Array[Node[TypeAnnotation]])
  Unit
  Tupled(Array[Node[TypeAnnotation]])
  Record(RecordDefinition)
  GenericRecord(Node[String], Node[RecordDefinition])
  FunctionTypeAnnotation(Node[TypeAnnotation], Node[TypeAnnotation])
} derive(Eq, Debug)

///|
/// Elm.Syntax.TypeAnnotation.RecordDefinition
pub type RecordDefinition = Array[Node[RecordField]]

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
  TuplePattern(Array[Node[Pattern]])
  RecordPattern(Array[Node[String]])
  UnConsPattern(Node[Pattern], Node[Pattern])
  ListPattern(Array[Node[Pattern]])
  VarPattern(String)
  NamedPattern(QualifiedNameRef, Array[Node[Pattern]])
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
  arguments : Array[Node[Pattern]]
  expression : Node[Expression]
} derive(Eq, Debug)

///|
/// Elm.Syntax.Expression.Expression
pub(all) enum Expression {
  UnitExpr
  Application(Array[Node[Expression]])
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
  TupledExpression(Array[Node[Expression]])
  ParenthesizedExpression(Node[Expression])
  LetExpression(LetBlock)
  CaseExpression(CaseBlock)
  LambdaExpression(Lambda)
  RecordExpr(Array[Node[RecordSetter]])
  ListExpr(Array[Node[Expression]])
  RecordAccess(Node[Expression], Node[String])
  RecordAccessFunction(String)
  RecordUpdateExpression(Node[String], Array[Node[RecordSetter]])
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
  declarations : Array[Node[LetDeclaration]]
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
  args : Array[Node[Pattern]]
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
pub type Cases = Array[Case]
