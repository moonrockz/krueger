///|
pub(all) struct Identifier(String) derive(Eq, Show)

///|
pub(all) struct ModuleName(Identifier) derive(Eq, Show)

///|
pub(all) struct ValueName(Identifier) derive(Eq, Show)

///|
pub(all) struct TypeName(Identifier) derive(Eq, Show)

///|
pub(all) struct TypeVarName(Identifier) derive(Eq, Show)

///|
pub(all) struct ConstructorName(Identifier) derive(Eq, Show)

///|
pub(all) struct OperatorName(String) derive(Eq, Show)

///|
pub(all) enum ExposedName {
  Value(ValueName)
} derive(Eq, Show)

///|
pub(all) struct DocComment {
  text : String
  span : @scanner.Span
} derive(Eq, Show)

///|
pub(all) struct DeclMeta {
  doc_comment : DocComment?
  span : @scanner.Span
} derive(Eq, Show)

///|
pub(all) struct UnparsedExpr {
  tokens : Array[@scanner.Token]
} derive(Eq, Show)

///|
pub(all) enum Expr {
  Var(ValueName)
  IntLiteral(Int)
  BinaryOp(Expr, OperatorName, Expr)
  Unparsed(UnparsedExpr)
} derive(Eq, Show)

///|
pub(all) struct UnparsedTypeExpr {
  tokens : Array[@scanner.Token]
} derive(Eq, Show)

///|
pub(all) enum TypeExpr {
  TypeRef(TypeName)
  TypeVar(TypeVarName)
  TypeApp(TypeName, Array[TypeExpr])
  Unparsed(UnparsedTypeExpr)
} derive(Eq, Show)

///|
pub(all) struct FunctionDeclaration {
  name : ValueName
  args : Array[ValueName]
  body : Expr
  meta : DeclMeta
} derive(Eq, Show)

///|
pub(all) struct TypeAliasDeclaration {
  name : TypeName
  type_params : Array[TypeVarName]
  body : TypeExpr
  meta : DeclMeta
} derive(Eq, Show)

///|
pub(all) struct UnionTypeCase {
  name : ConstructorName
  args : Array[TypeExpr]
} derive(Eq, Show)

///|
pub(all) struct UnionTypeDeclaration {
  name : TypeName
  type_params : Array[TypeVarName]
  cases : Array[UnionTypeCase]
  meta : DeclMeta
} derive(Eq, Show)

///|
pub(all) enum Declaration {
  FunctionDecl(FunctionDeclaration)
  TypeAliasDecl(TypeAliasDeclaration)
  UnionTypeDecl(UnionTypeDeclaration)
} derive(Eq, Show)

///|
pub(all) struct ImportDecl {
  module_name : ModuleName
  exposing : Array[ExposedName]?
  span : @scanner.Span
} derive(Eq, Show)

///|
pub(all) struct ModuleAst {
  module_name : ModuleName?
  exposing : Array[ExposedName]
  imports : Array[ImportDecl]
  declarations : Array[Declaration]
  span : @scanner.Span?
} derive(Eq, Show)
