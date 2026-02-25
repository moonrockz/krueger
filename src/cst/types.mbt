///|
pub(all) struct ModuleHeaderCst {
  tokens : Array[@scanner.Token]
  span : @scanner.Span?
} derive(Eq, Show)

///|
pub(all) struct ImportCst {
  tokens : Array[@scanner.Token]
  span : @scanner.Span?
} derive(Eq, Show)

///|
pub(all) struct FunctionCst {
  tokens : Array[@scanner.Token]
  span : @scanner.Span?
} derive(Eq, Show)

///|
pub(all) struct TypeAliasCst {
  tokens : Array[@scanner.Token]
  span : @scanner.Span?
} derive(Eq, Show)

///|
pub(all) struct UnionTypeCst {
  tokens : Array[@scanner.Token]
  span : @scanner.Span?
} derive(Eq, Show)

///|
pub(all) enum DeclarationCst {
  Function(FunctionCst)
  TypeAlias(TypeAliasCst)
  UnionType(UnionTypeCst)
} derive(Eq, Show)

///|
pub(all) struct ModuleCst {
  tokens : Array[@scanner.Token]
  header : ModuleHeaderCst?
  imports : Array[ImportCst]
  declarations : Array[DeclarationCst]
  span : @scanner.Span?
} derive(Eq, Show)
