///|
let r0 : @ast.Range = {
  start: { row: 0, column: 0, },
  end: { row: 0, column: 0, },
}

///|
fn[T] n(value : T) -> @ast.Node[T] {
  { range: r0, value, }
}

///|
fn typed(
  name : String,
  args : Array[@ast.Node[@ast.TypeAnnotation]],
) -> @ast.Node[@ast.TypeAnnotation] {
  n(Typed(n(([][:], name)), args[:]))
}

///|
fn tvar(name : String) -> @ast.Node[@ast.TypeAnnotation] {
  n(GenericType(name))
}

///|
fn arrow(
  a : @ast.Node[@ast.TypeAnnotation],
  b : @ast.Node[@ast.TypeAnnotation],
) -> @ast.Node[@ast.TypeAnnotation] {
  n(FunctionTypeAnnotation(a, b))
}

///|
fn pvar(name : String) -> @ast.Node[@ast.Pattern] {
  n(VarPattern(name))
}

///|
fn ctor(
  name : String,
  args : Array[@ast.Node[@ast.Pattern]],
) -> @ast.Node[@ast.Pattern] {
  n(NamedPattern({ module_name: [][:], name, }, args[:]))
}

///|
/// The problem and the path steps of a print error.
fn[T] problem_of(
  f : () -> T raise @printer.PrintError,
) -> (@printer.PrintProblem, Array[@syntax.PathStep])? {
  try {
    ignore(f())
    None
  } catch {
    PrintError(path~, problem~) => Some((problem, path.steps()))
  }
}
