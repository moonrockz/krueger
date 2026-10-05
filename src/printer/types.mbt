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
  let (lead, d, trail) = self.type_parts(path, level, t, at)
  lead + d + trail
}

///|
/// The leading comments, the type and the trailing comments, taken in that
/// order.
fn Ctx::type_parts(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  t : @ast.Node[@ast.TypeAnnotation],
  at : TypeAt,
) -> (@pretty.Doc, @pretty.Doc, @pretty.Doc) raise PrintError {
  check_level(path, level)
  let lead = self.leading(t.range)
  let d = self.type_body(path, level, t, at)
  (lead, d, self.trailing(t.range))
}

///|
/// The type without its own comments.
fn Ctx::type_body(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  t : @ast.Node[@ast.TypeAnnotation],
  at : TypeAt,
) -> @pretty.Doc raise PrintError {
  match t.value {
    GenericType(name) => self.lower_name(path, name)
    Unit => @pretty.text("(") + self.inner_alone(t.range) + @pretty.text(")")
    Typed(name, args) => {
      let (module_, base_name) = name.value
      let head = qualified_upper(path, module_, base_name)
      guard !args.is_empty() else { return head }
      let docs = []
      for i, a in args {
        docs.push(self.type_doc(path.child("args", i), level + 1, a, TypeArg))
      }
      // elm-format Parse/Type.hs app (`checkMultiline`): a line break
      // anywhere in the application puts each argument on its own line
      // (`FASplitFirst`); else `FAJoinFirst JoinAll`.
      let split = self.split_within({
        start: name.range.start,
        end: args[args.length() - 1].range.end,
      })
      let d = application(split, self.join(), head, docs)
      if at is TypeArg {
        parens(self.join(), d)
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
      // elm-format Parse/Type.hs tuple (`checkMultiline`).
      sequence(
        self.split_within(t.range),
        "(",
        ")",
        docs,
        inner=@pretty.nest(2, self.inner_close(t.range)),
      )
    }
    Record(fields) => {
      let (docs, leads) = self.record_fields(path, "value", level, fields)
      let inner = match fields.last() {
        Some(f) => self.inner(t.range, last=Some(f.range))
        None => self.inner_alone(t.range, brace=true)
      }
      // elm-format Parse/Type.hs record (`checkMultiline`).
      sequence(self.split_within(t.range), "{", "}", docs, leads~, inner~)
    }
    GenericRecord(name, fields) => {
      guard !fields.value.is_empty() else {
        raise PrintError(path~, problem=NoFields)
      }
      let base = self.with_comments(
        name.range,
        self.lower_name(path.child("name", 0), name.value),
      )
      let (docs, leads) = self.record_fields(
        path,
        "values",
        level,
        fields.value,
      )
      // elm-format Parse/Type.hs record (`checkMultiline`).
      extension(
        self.split_within(t.range),
        base,
        docs,
        leads~,
        inner=self.inner(t.range, last=fields.value.last().map(f => f.range)),
      )
    }
    FunctionTypeAnnotation(_, _) => {
      let d = @pretty.group(self.arrow_chain(path, level, t))
      if at is AnyType {
        d
      } else {
        parens(self.join(), d)
      }
    }
  }
}

///|
/// `a : A` for each field, at `path.child(field_name, i)`, and the comments
/// before the `,` of each (see `Ctx::before_item`).
fn Ctx::record_fields(
  self : Ctx,
  path : @syntax.NodePath,
  field_name : String,
  level : Int,
  fields : @ast.RecordDefinition,
) -> (Array[@pretty.Doc], Array[@pretty.Doc]) raise PrintError {
  let docs = []
  let leads = []
  for i, f in fields {
    let p = path.child(field_name, i)
    let name = f.value.name
    let previous = if i > 0 { Some(fields[i - 1].range) } else { None }
    leads.push(
      match previous {
        Some(r) => self.before_item(Some(r), f.range)
        None => @pretty.empty()
      },
    )
    let lead = self.after_comma(previous, f.range)
    let moved = self.after_token(name.range)
    let label = self.with_comments(
      name.range,
      self.lower_name(p.child("name", 0), name.value),
    )
    // The comments after the type go after the field, outside its group.
    let value_trail = self.take(Trailing, f.value.type_annotation.range)
    let value = self.type_doc(
      p.child("typeAnnotation", 0),
      level + 1,
      f.value.type_annotation,
      AnyType,
    )
    // elm-format Parse/Common.hs pair (`checkMultiline`): a line break
    // from the label to the end of the type.
    let split = self.split_within({
      start: name.range.start,
      end: f.value.type_annotation.range.end,
    })
    docs.push(
      lead +
      field(split, label, self.separator(name.range, " :", moved), value) +
      comments_after(value_trail) +
      self.trailing_before_comma(f.range, fields.get(i + 1).map(n => n.range)),
    )
  }
  (docs, leads)
}

///|
/// `a -> b -> c`, flattened without recursion and without its own group (a
/// signature shares its group with `name :`). Not a function type: the type
/// itself. The comments before a flattened function type go before its
/// `->`.
///
/// In the `ElmFormat` layout (elm-format Box.hs `FunctionType`), a line
/// break anywhere in the type (Parse/Helpers.hs `separated`) puts each `->`
/// on its own line, and a multi-line type after a `->` goes on the next
/// line at the next tab stop (`prefixOrIndented`). The comments after a
/// `->` go after it.
fn Ctx::arrow_chain(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  t : @ast.Node[@ast.TypeAnnotation],
) -> @pretty.Doc raise PrintError {
  let split = self.split_within(t.range)
  let mut node = t
  let mut p = path
  let mut d = @pretty.empty()
  let mut first = true
  let mut lead = @pretty.empty()
  // The comments after a `->` that trail the type before it.
  let mut moved = []
  // `-> t`, with the comments `after` the `->`.
  let arrow = (
    lead : @pretty.Doc,
    after : Array[@ast.Node[String]],
    parts : (@pretty.Doc, @pretty.Doc, @pretty.Doc),
  ) => {
    let (l_lead, l_body, l_trail) = parts
    match split {
      Fit =>
        @pretty.line() +
        lead +
        @pretty.text("->") +
        comments_after(after) +
        @pretty.text(" ") +
        l_lead +
        l_body +
        l_trail
      Join | Split =>
        split_line(split) +
        lead +
        @pretty.text("->") +
        @pretty.group(
          @pretty.tab(
            4,
            @pretty.line() +
            comments_joined(after, @pretty.text(" ")) +
            l_lead +
            l_body,
          ),
        ) +
        l_trail
    }
  }
  while node.value is FunctionTypeAnnotation(left, right) {
    let after_arrow = moved
    moved = match split {
      Fit => self.after_token(left.range)
      Join | Split => {
        let next = self.token_after(left.range.end)
        self.take_if(Trailing, left.range, c => !ends_before(c, next))
      }
    }
    let l = self.type_parts(p.child("left", 0), level + 1, left, ArrowLeft)
    d = if first {
      let (l_lead, l_body, l_trail) = l
      l_lead + l_body + l_trail
    } else {
      d + arrow(lead, after_arrow, l)
    }
    first = false
    p = p.child("right", 0)
    node = right
    lead = if node.value is FunctionTypeAnnotation(_, _) {
      self.leading(node.range)
    } else {
      @pretty.empty()
    }
  }
  if first {
    self.type_doc(p, level + 1, node, AnyType)
  } else {
    // A signature's type has no `type_doc` of its own: its comments are
    // taken here.
    let own = self.leading(t.range)
    let last = self.type_parts(p, level + 1, node, AnyType)
    own + d + arrow(lead, moved, last) + self.trailing(t.range)
  }
}
