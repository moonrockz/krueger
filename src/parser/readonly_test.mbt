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
/// Compiles only while the lists in doc attributes are read-only views.
fn read_only_attribute_lists(
  group : @parser.AttributeGroup,
  attribute : @parser.DocAttribute,
) -> Unit {
  read_only(group.attributes)
  match attribute {
    Attribute(arguments~, ..) => read_only(arguments)
    Docs(names~, ..) => read_only(names)
  }
}

///|
test "every doc-attribute list is a read-only view" {
  ignore(read_only_attribute_lists)
}
