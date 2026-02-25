///|
pub(all) struct ModuleAst {
  module_name : String?
} derive(Eq, Show)

///|
pub(all) struct ModuleCst {
  module_name : String?
} derive(Eq, Show)

///|
pub(all) struct ParseResult {
  ast : ModuleAst?
  cst : ModuleCst?
  diagnostics : Array[@scanner.Diagnostic]
} derive(Eq, Show)
