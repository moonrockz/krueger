///|
pub(all) struct ModuleHeaderCst {
  module_name : String?
  exposing : Array[String]
  tokens : Array[@scanner.Token]
  span : @scanner.Span
} derive(Eq, Debug)

///|
pub(all) struct ImportCst {
  module_name : String
  exposing : Array[String]?
  tokens : Array[@scanner.Token]
  span : @scanner.Span
} derive(Eq, Debug)

///|
pub(all) struct FunctionCst {
  name : String
  args : Array[String]
  tokens : Array[@scanner.Token]
  span : @scanner.Span
} derive(Eq, Debug)

///|
pub(all) struct TypeAliasCst {
  name : String
  type_params : Array[String]
  tokens : Array[@scanner.Token]
  span : @scanner.Span
} derive(Eq, Debug)

///|
pub(all) struct UnionTypeCst {
  name : String
  type_params : Array[String]
  tokens : Array[@scanner.Token]
  span : @scanner.Span
} derive(Eq, Debug)

///|
pub(all) enum DeclarationCst {
  Function(FunctionCst)
  TypeAlias(TypeAliasCst)
  UnionType(UnionTypeCst)
} derive(Eq, Debug)

///|
pub(all) struct ModuleCst {
  tokens : Array[@scanner.Token]
  header : ModuleHeaderCst?
  imports : Array[ImportCst]
  declarations : Array[DeclarationCst]
  span : @scanner.Span?
} derive(Eq, Debug)
