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
pub(all) struct ParseResult {
  ast : @ast.ModuleAst?
  cst : @cst.ModuleCst?
  diagnostics : Array[@scanner.Diagnostic]
} derive(Eq, Show)
