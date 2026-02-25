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
pub(all) struct FunctionDeclaration {
  name : String
  args : Array[String]
  body_tokens : Array[@scanner.Token]
  meta : DeclMeta
} derive(Eq, Show)

///|
pub(all) struct TypeAliasDeclaration {
  name : String
  type_params : Array[String]
  alias_tokens : Array[@scanner.Token]
  meta : DeclMeta
} derive(Eq, Show)

///|
pub(all) struct UnionTypeCase {
  name : String
  args : Array[String]
} derive(Eq, Show)

///|
pub(all) struct UnionTypeDeclaration {
  name : String
  type_params : Array[String]
  cases : Array[UnionTypeCase]
  raw_tokens : Array[@scanner.Token]
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
  module_name : String
  exposing : Array[String]?
  span : @scanner.Span
} derive(Eq, Show)

///|
pub(all) struct ModuleAst {
  module_name : String?
  exposing : Array[String]
  imports : Array[ImportDecl]
  declarations : Array[Declaration]
  span : @scanner.Span?
} derive(Eq, Show)

///|
pub(all) struct CstDecl {
  kind : String
  span : @scanner.Span
  tokens : Array[@scanner.Token]
} derive(Eq, Show)

///|
pub(all) struct ModuleCst {
  tokens : Array[@scanner.Token]
  declarations : Array[CstDecl]
  span : @scanner.Span?
} derive(Eq, Show)

///|
pub(all) struct ParseResult {
  ast : ModuleAst?
  cst : ModuleCst?
  diagnostics : Array[@scanner.Diagnostic]
} derive(Eq, Show)
