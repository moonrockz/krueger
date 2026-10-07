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
  let d = match self.type_paren_comments(t) {
    Some((pre, post)) => {
      // elm-format Parse/Type.hs tuple: parentheses that hold comments are
      // `TypeParens`, printed as `parens (formatCommented ...)`.
      let (inner, flat) = commented(
        pre,
        self.type_body(path, level, t, AnyType),
        post,
      )
      @pretty.group(
        @pretty.align(
          @pretty.text("(") +
          @pretty.nest(1, inner) +
          (if flat { @pretty.softline() } else { @pretty.hardline() }) +
          @pretty.text(")"),
        ),
      )
    }
    None => self.type_body(path, level, t, at)
  }
  (lead, d, self.trailing(t.range))
}

///|
/// The source parentheses around type `t`: the starts of the first and the
/// last token in them. elm-syntax keeps no node for these parentheses; the
/// range of `t` then starts at the `(` and ends after the `)`. `None` when
/// there is no source or there are no parentheses.
fn Ctx::type_parens(
  self : Ctx,
  t : @ast.Node[@ast.TypeAnnotation],
) -> (@ast.Location, @ast.Location)? {
  guard self.source is Some(facts) else { return None }
  // A type that starts with its first child has no parentheses of its own.
  let first_child = match t.value {
    Unit | Tupled(_) => return None
    Typed(name, _) => Some(name.range.start)
    FunctionTypeAnnotation(left, _) => Some(left.range.start)
    GenericType(_) | Record(_) | GenericRecord(_, _) => None
  }
  guard facts.token_at(t.range.start) is Some(open) &&
    facts.lexemes[open] == "(" &&
    !(first_child is Some(s) && compare_location(s, t.range.start) == 0) else {
    return None
  }
  let close = facts.first_at_or_after(t.range.end) - 1
  guard close > open + 1 && facts.lexemes[close] == ")" else { return None }
  Some((facts.starts[open + 1], facts.starts[close - 1]))
}

///|
/// The comments in the source parentheses around type `t` (see
/// `Ctx::type_parens`) before and after the type in them; marks them
/// printed. elm-format keeps such parentheses. `None` when there are no
/// such comments.
fn Ctx::type_paren_comments(
  self : Ctx,
  t : @ast.Node[@ast.TypeAnnotation],
) -> (Array[@ast.Node[String]], Array[@ast.Node[String]])? {
  guard self.type_parens(t) is Some((first, last)) else { return None }
  let before = (c : @ast.Node[String]) => at_or_before(c.range.end, first)
  let after = (c : @ast.Node[String]) => {
    compare_location(last, c.range.start) < 0
  }
  // The comments before the name of a type application lead its first
  // argument, and the comments after its last part trail that part.
  let (first_part, last_part) = match t.value {
    Typed(_, args) if !args.is_empty() =>
      (Some(args[0].range), Some(args[args.length() - 1].range))
    FunctionTypeAnnotation(left, right) => {
      let mut r = right
      while r.value is FunctionTypeAnnotation(_, next) {
        r = next
      }
      (Some(left.range), Some(r.range))
    }
    _ => (None, None)
  }
  let pre = match first_part {
    Some(r) => self.take_if(Leading, r, before)
    None => []
  }
  pre.append(self.take_if(Inner, t.range, before))
  let post = self.take_if(Inner, t.range, after)
  match last_part {
    Some(r) => post.append(self.take_if(Trailing, r, after))
    None => ()
  }
  post.sort_by((a, b) => compare_location(a.range.start, b.range.start))
  pre.sort_by((a, b) => compare_location(a.range.start, b.range.start))
  if pre.is_empty() && post.is_empty() {
    None
  } else {
    Some((pre, post))
  }
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
        if i > 0 {
          // elm-format Box.hs TupleType (`formatC2Eol`): the comments before
          // a `,` go under the item before it.
          let comma = self.token_before(x.range.start)
          let cs = self.take_if(Leading, x.range, c => ends_before(c, comma))
          if !cs.is_empty() {
            docs[i - 1] = docs[i - 1] + @pretty.hardline() + comment_box(cs)
          }
        }
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
      // elm-format Box.hs formatRecordLike: the comments before the `|`
      // follow the base (`formatCommented`), in its column.
      let bar = self.token_before(fields.value[0].range.start)
      let base_post = self.take_if(Leading, fields.value[0].range, c => {
        ends_before(c, bar)
      })
      let base = @pretty.align(
        self.with_comments(
          name.range,
          self.lower_name(path.child("name", 0), name.value),
        ) +
        (if base_post.iter().all(one_line) {
          comments_after(base_post)
        } else {
          @pretty.hardline() + comment_block(base_post)
        }),
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
    // elm-format Box.hs formatPair: the comments between the label and
    // the `:` follow the label (`formatTailCommented`). When one of them
    // is not one line, the label, each comment, the `:` and the type go on
    // lines of their own, the last two at the next tab stop.
    let colon = self.token_after(name.range.end)
    let label_post = self.take_if(Trailing, name.range, c => {
      is_line_comment(c) && ends_before(c, colon)
    })
    label_post.append(
      self.take_if(Leading, f.value.type_annotation.range, c => {
        ends_before(c, colon)
      }),
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
    let pair = if label_post.iter().all(one_line) {
      field(
        split,
        label + comments_after(label_post),
        self.separator(name.range, " :", moved),
        value,
      )
    } else {
      label +
      @pretty.hardline() +
      comment_block(label_post) +
      @pretty.tab(
        4,
        @pretty.hardline() +
        @pretty.text(":") +
        comments_after(moved) +
        @pretty.hardline() +
        value,
      )
    }
    docs.push(
      lead +
      pair +
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
  eol? : Array[@ast.Node[String]] = [],
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
  // elm-format Box.hs FunctionType: a function type in parentheses after
  // a `->` is a term of its own (`typeParens ForLambda`), so the source
  // parentheses stay.
  let flattens = (n : @ast.Node[@ast.TypeAnnotation]) => {
    n.value is FunctionTypeAnnotation(_, _) &&
    !(self.layout is ElmFormat && self.type_parens(n) is Some(_))
  }
  while node.value is FunctionTypeAnnotation(left, right) &&
        (first || flattens(node)) {
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
    lead = if flattens(node) {
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
    let (l_lead, l_body, l_trail) = self.type_parts(
      p,
      level + 1,
      node,
      ArrowLeft,
    )
    let last = (l_lead, l_body, l_trail + comments_after(eol))
    own + d + arrow(lead, moved, last) + self.trailing(t.range)
  }
}
