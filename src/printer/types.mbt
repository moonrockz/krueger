///|
/// Where a type is: this decides its parentheses.
priv enum TypeAt {
  AnyType // nothing needs parentheses
  ArrowLeft // left of `->`: a function type needs them
  TypeArg // argument of a type application: also an application with arguments
}

///|
fn Ctx::type_doc(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  t : @ast.Node[@ast.TypeAnnotation],
  at : TypeAt,
) -> @pretty.Doc raise PrintError {
  check_level(path, level)
  match t.value {
    GenericType(name) => self.lower_name(path, name)
    Unit => @pretty.text("()")
    Typed(name, args) => {
      let (module_, base_name) = name.value
      let head = qualified_upper(path, module_, base_name)
      guard !args.is_empty() else { return head }
      let docs = []
      for i, a in args {
        docs.push(self.type_doc(path.child("args", i), level + 1, a, TypeArg))
      }
      let d = spaced(head, docs)
      if at is TypeArg {
        parens(d)
      } else {
        d
      }
    }
    Tupled(items) => {
      guard items.length() >= 2 else {
        raise PrintError(path~, problem=ShortTuple)
      }
      let docs = []
      for i, x in items {
        docs.push(self.type_doc(path.child("values", i), level + 1, x, AnyType))
      }
      sequence("(", ")", docs)
    }
    Record(fields) =>
      sequence("{", "}", self.record_fields(path, "value", level, fields))
    GenericRecord(name, fields) => {
      guard !fields.value.is_empty() else {
        raise PrintError(path~, problem=NoFields)
      }
      extension(
        self.lower_name(path.child("name", 0), name.value),
        self.record_fields(path, "values", level, fields.value),
      )
    }
    FunctionTypeAnnotation(_, _) => {
      let d = @pretty.group(self.arrow_chain(path, level, t))
      if at is AnyType {
        d
      } else {
        parens(d)
      }
    }
  }
}

///|
/// `a : A` for each field, at `path.child(field_name, i)`.
fn Ctx::record_fields(
  self : Ctx,
  path : @syntax.NodePath,
  field_name : String,
  level : Int,
  fields : @ast.RecordDefinition,
) -> Array[@pretty.Doc] raise PrintError {
  let docs = []
  for i, f in fields {
    let p = path.child(field_name, i)
    docs.push(
      field(
        self.lower_name(p.child("name", 0), f.value.name.value),
        ":",
        self.type_doc(
          p.child("typeAnnotation", 0),
          level + 1,
          f.value.type_annotation,
          AnyType,
        ),
      ),
    )
  }
  docs
}

///|
/// `a -> b -> c`, flattened without recursion and without its own group (a
/// signature shares its group with `name :`). Not a function type: the type
/// itself.
fn Ctx::arrow_chain(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  t : @ast.Node[@ast.TypeAnnotation],
) -> @pretty.Doc raise PrintError {
  let mut node = t
  let mut p = path
  let mut d = @pretty.empty()
  let mut first = true
  while node.value is FunctionTypeAnnotation(left, right) {
    let l = self.type_doc(p.child("left", 0), level + 1, left, ArrowLeft)
    d = if first { l } else { d + @pretty.line() + @pretty.text("-> ") + l }
    first = false
    p = p.child("right", 0)
    node = right
  }
  let last = self.type_doc(p, level + 1, node, AnyType)
  if first {
    last
  } else {
    d + @pretty.line() + @pretty.text("-> ") + last
  }
}
