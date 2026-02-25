///|
pub using @ast {
  type DocComment,
  type DeclMeta,
  type FunctionDeclaration,
  type TypeAliasDeclaration,
  type UnionTypeCase,
  type UnionTypeDeclaration,
  type Declaration,
  type ImportDecl,
  type ModuleAst,
}

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
  ast : @ast.ModuleAst?
  cst : ModuleCst?
  diagnostics : Array[@scanner.Diagnostic]
} derive(Eq, Show)
