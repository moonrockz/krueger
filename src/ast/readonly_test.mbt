///|
/// Implemented only by `ArrayView`. A generic `[V : ReadOnly]` parameter takes
/// a value as it is, so an `Array` (which converts to a view in a typed
/// binding) fails this check.
trait ReadOnly {}

///|
impl[T] ReadOnly for ArrayView[T]

///|
fn[V : ReadOnly] read_only(_ : V) -> Unit {
  ()
}

///|
/// Compiles only while every list in the AST is a read-only `ArrayView`: a
/// parsed tree cannot be changed through any value reachable from it.
fn read_only_lists(
  file : @ast.File,
  exposing : @ast.Exposing,
  alias : @ast.TypeAlias,
  custom : @ast.Type,
  constructor : @ast.ValueConstructor,
  annotation : @ast.TypeAnnotation,
  pattern : @ast.Pattern,
  implementation : @ast.FunctionImplementation,
  expression : @ast.Expression,
  block : @ast.LetBlock,
  lambda : @ast.Lambda,
  name : @ast.ModuleName,
  record : @ast.RecordDefinition,
  cases : @ast.Cases,
) -> Unit {
  read_only(file.imports)
  read_only(file.declarations)
  read_only(file.comments)
  if exposing is Explicit(items) {
    read_only(items)
  }
  read_only(alias.generics)
  read_only(custom.generics)
  read_only(custom.constructors)
  read_only(constructor.arguments)
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
}

///|
test "every AST list is a read-only view" {
  // The check is the type of `read_only_lists`; there is nothing to run.
  ignore(read_only_lists)
}
