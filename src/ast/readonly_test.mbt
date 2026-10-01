///|
/// Implemented only by `ArrayView`. A generic `[V : ReadOnly]` parameter takes
/// a value as it is, so an `Array` (which converts to a view in a typed
/// binding) fails this check.
trait ReadOnly {
  fn size(Self) -> Int
}

///|
impl[T] ReadOnly for ArrayView[T] with fn size(self) {
  self.length()
}

///|
fn[V : ReadOnly] read_only(list : V) -> Unit {
  ignore(list.size())
}

///|
/// Compiles only while every list in the AST is a read-only `ArrayView`: a
/// parsed tree cannot be changed through any value reachable from it.
fn read_only_lists(
  file : @ast.File,
  exposing : @ast.Exposing,
  type_alias : @ast.TypeAlias,
  custom : @ast.Type,
  value_constructor : @ast.ValueConstructor,
  annotation : @ast.TypeAnnotation,
  pattern : @ast.Pattern,
  implementation : @ast.FunctionImplementation,
  expression : @ast.Expression,
  block : @ast.LetBlock,
  lambda : @ast.Lambda,
  name : @ast.ModuleName,
  record : @ast.RecordDefinition,
  cases : @ast.Cases,
  case_block : @ast.CaseBlock,
  import_ : @ast.Import,
  default_data : @ast.DefaultModuleData,
  effect_data : @ast.EffectModuleData,
  qualified_ref : @ast.QualifiedNameRef,
) -> Unit {
  read_only(file.imports)
  read_only(file.declarations)
  read_only(file.comments)
  if exposing is Explicit(items) {
    read_only(items)
  }
  read_only(type_alias.generics)
  read_only(custom.generics)
  read_only(custom.constructors)
  read_only(value_constructor.arguments)
  match annotation {
    Typed(qualified, args) => {
      read_only(qualified.value.0)
      read_only(args)
    }
    Tupled(items) => read_only(items)
    _ => ()
  }
  match pattern {
    TuplePattern(items) | ListPattern(items) | NamedPattern(_, items) =>
      read_only(items)
    RecordPattern(fields) => read_only(fields)
    _ => ()
  }
  read_only(implementation.arguments)
  match expression {
    Application(items) | TupledExpression(items) | ListExpr(items) =>
      read_only(items)
    RecordExpr(setters) | RecordUpdateExpression(_, setters) =>
      read_only(setters)
    _ => ()
  }
  read_only(block.declarations)
  read_only(lambda.args)
  read_only(name)
  read_only(record)
  read_only(cases)
  // Fields typed with the aliases above.
  read_only(case_block.cases)
  read_only(import_.module_name.value)
  if import_.module_alias is Some(a) {
    read_only(a.value)
  }
  read_only(default_data.module_name.value)
  read_only(effect_data.module_name.value)
  read_only(qualified_ref.module_name)
  match annotation {
    Record(fields) => read_only(fields)
    GenericRecord(_, fields) => read_only(fields.value)
    _ => ()
  }
  if expression is FunctionOrValue(module_name, _) {
    read_only(module_name)
  }
}

///|
test "every AST list is a read-only view" {
  // The check is the type of `read_only_lists`; there is nothing to run.
  ignore(read_only_lists)
}
