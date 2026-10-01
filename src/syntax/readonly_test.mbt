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
/// Compiles only while the lists in node payloads are read-only views.
fn read_only_payloads(n : @syntax.NodeRef) -> Unit {
  match n {
    File(_, groups) => read_only(groups)
    ModuleName(name) => read_only(name.value)
    Declaration(_, attributes) => read_only(attributes)
    _ => ()
  }
}

///|
test "every node payload list is a read-only view" {
  ignore(read_only_payloads)
}
