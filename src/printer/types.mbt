///|
/// Where a type is: this decides its parentheses.
priv enum TypeAt {
  AnyType // nothing needs parentheses
  ArrowLeft // left of `->`: a function type needs them
  TypeArg // argument of a type application: also an application with arguments
}

///|
/// The type at `path` with its comments. It runs on the work stack
/// (`Ctx::run`), so nested types do not recurse: a type of any depth
/// prints on every target.
fn Ctx::type_doc(
  self : Ctx,
  path : @syntax.NodePath,
  t : @ast.Node[@ast.TypeAnnotation],
  at : TypeAt,
) -> @pretty.Doc raise PrintError {
  self.run(Type(path, t, at))
}

///|
/// The three items of a type: its leading comments, its body and its
/// trailing comments, in that order (an arrow chain places them apart).
/// Build them when their `Parts` item is popped, not while the plan of
/// the type above is built: the leaves then run, and errors come, in
/// source order, and nothing recurses per level.
fn Ctx::type_parts_plan(
  self : Ctx,
  path : @syntax.NodePath,
  t : @ast.Node[@ast.TypeAnnotation],
  at : TypeAt,
) -> Array[Work] raise PrintError {
  // The comments in the type's own parentheses lie inside its range, so
  // taking them before its leading comments changes nothing.
  let paren_comments = self.type_paren_comments(t)
  let (items, combine) = match paren_comments {
    Some(_) => self.type_body_plan(path, t, AnyType)
    None => self.type_body_plan(path, t, at)
  }
  let body = Plan(items, docs => {
    let d = combine(docs)
    match paren_comments {
      Some((pre, post)) => {
        // elm-format Parse/Type.hs tuple: parentheses that hold comments
        // are `TypeParens`, printed as `parens (formatCommented ...)`.
        let (inner, flat) = commented(pre, d, post)
        @pretty.group(
          @pretty.align(
            @pretty.text("(") +
            @pretty.nest(1, inner) +
            (if flat { @pretty.softline() } else { @pretty.hardline() }) +
            @pretty.text(")"),
          ),
        )
      }
      None => d
    }
  })
  [Leaf(() => self.leading(t.range)), body, Leaf(() => self.trailing(t.range))]
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
/// The plan of a type without its own comments. The leaves take comments
/// in source order; a nested type is a `Type` work item.
fn Ctx::type_body_plan(
  self : Ctx,
  path : @syntax.NodePath,
  t : @ast.Node[@ast.TypeAnnotation],
  at : TypeAt,
) -> (Array[Work], (Array[@pretty.Doc]) -> @pretty.Doc) raise PrintError {
  match t.value {
    GenericType(name) => done(self.lower_name(path, name))
    Unit =>
      leaf(() => {
        @pretty.text("(") + self.inner_alone(t.range) + @pretty.text(")")
      })
    Typed(name, args) => {
      let (module_, base_name) = name.value
      let head = qualified_upper(path, module_, base_name)
      guard !args.is_empty() else { return done(head) }
      let items : Array[Work] = []
      for i, a in args {
        items.push(Type(path.child("args", i), a, TypeArg))
      }
      // elm-format Parse/Type.hs app (`checkMultiline`): a line break
      // anywhere in the application puts each argument on its own line
      // (`FASplitFirst`); else `FAJoinFirst JoinAll`.
      let split = self.split_within({
        start: name.range.start,
        end: args[args.length() - 1].range.end,
      })
      (
        items,
        docs => {
          let d = application(split, self.join(), head, docs)
          if at is TypeArg {
            parens(self.join(), d)
          } else {
            d
          }
        },
      )
    }
    Tupled(items) => {
      guard items.length() >= 2 else {
        raise PrintError(path~, problem=ShortTuple)
      }
      let count = items.length()
      let work : Array[Work] = []
      for i, x in items {
        if i > 0 {
          // elm-format Box.hs TupleType (`formatC2Eol`): the comments before
          // a `,` go under the item before it.
          work.push(
            Leaf(() => {
              let comma = self.token_before(x.range.start)
              let cs = self.take_if(Leading, x.range, c => ends_before(c, comma))
              if cs.is_empty() {
                @pretty.empty()
              } else {
                @pretty.hardline() + comment_box(cs)
              }
            }),
          )
        }
        work.push(Type(path.child("values", i), x, AnyType))
      }
      work.push(Leaf(() => @pretty.nest(2, self.inner_close(t.range))))
      // elm-format Parse/Type.hs tuple (`checkMultiline`).
      let split = self.split_within(t.range)
      (
        work,
        docs => {
          // docs: item 0, then (comma comments, item) per later item, then
          // the inner comments.
          let ds = [docs[0]]
          for i in 1..<count {
            ds[i - 1] = ds[i - 1] + docs[2 * i - 1]
            ds.push(docs[2 * i])
          }
          sequence(split, "(", ")", ds, inner=docs[2 * count - 1])
        },
      )
    }
    Record(fields) => {
      let (work, combine_fields) = self.record_fields_plan(
        path, "value", fields,
      )
      let last = fields.last().map(f => f.range)
      work.push(
        Leaf(() => {
          match last {
            Some(r) => self.inner(t.range, last=Some(r))
            None => self.inner_alone(t.range, brace=true)
          }
        }),
      )
      // elm-format Parse/Type.hs record (`checkMultiline`).
      let split = self.split_within(t.range)
      (
        work,
        docs => {
          let (ds, leads) = combine_fields(docs, 0)
          sequence(split, "{", "}", ds, leads~, inner=docs[docs.length() - 1])
        },
      )
    }
    GenericRecord(name, fields) => {
      guard !fields.value.is_empty() else {
        raise PrintError(path~, problem=NoFields)
      }
      let work : Array[Work] = [
        Leaf(() => {
          // elm-format Box.hs formatRecordLike: the comments before the `|`
          // follow the base (`formatCommented`), in its column.
          let bar = self.token_before(fields.value[0].range.start)
          let base_post = self.take_if(Leading, fields.value[0].range, c => {
            ends_before(c, bar)
          })
          @pretty.align(
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
        }),
      ]
      let (field_work, combine_fields) = self.record_fields_plan(
        path,
        "values",
        fields.value,
      )
      work.append(field_work)
      let last = fields.value.last().map(f => f.range)
      work.push(Leaf(() => self.inner(t.range, last~)))
      // elm-format Parse/Type.hs record (`checkMultiline`).
      let split = self.split_within(t.range)
      (
        work,
        docs => {
          let (ds, leads) = combine_fields(docs, 1)
          extension(split, docs[0], ds, leads~, inner=docs[docs.length() - 1])
        },
      )
    }
    FunctionTypeAnnotation(_, _) => {
      let (work, combine) = self.arrow_chain_plan(path, t)
      (
        work,
        docs => {
          let d = @pretty.group(combine(docs))
          if at is AnyType {
            d
          } else {
            parens(self.join(), d)
          }
        },
      )
    }
  }
}

///|
/// The comments and docs of one record field that are taken before its
/// type prints (see `Ctx::record_fields_plan`).
priv struct FieldParts {
  /// The comments before the `,` of the field (see `Ctx::before_item`).
  lead_before : @pretty.Doc
  /// The comments between the label and the `:`.
  label_post : Array[@ast.Node[String]]
  /// The comments after the `,` (see `Ctx::after_comma`).
  lead : @pretty.Doc
  /// The comments after the `:`.
  moved : Array[@ast.Node[String]]
  label : @pretty.Doc
  /// The comments after the type, printed after the field.
  value_trail : Array[@ast.Node[String]]
}

///|
/// The plan of `a : A` for each field, at `path.child(field_name, i)`:
/// three items per field (the comments taken before the type, the type,
/// the comments before the next `,`). The combine function reads the
/// docs from `start` and gives the field docs and the comments before each
/// `,` (see `Ctx::before_item`).
fn Ctx::record_fields_plan(
  self : Ctx,
  path : @syntax.NodePath,
  field_name : String,
  fields : @ast.RecordDefinition,
) -> (
  Array[Work],
  (Array[@pretty.Doc], Int32) -> (Array[@pretty.Doc], Array[@pretty.Doc]),
) {
  let work : Array[Work] = []
  let parts : Array[FieldParts] = []
  let splits : Array[Split] = []
  for i, f in fields {
    let p = path.child(field_name, i)
    let name = f.value.name
    let previous = if i > 0 { Some(fields[i - 1].range) } else { None }
    let value = f.value.type_annotation
    // elm-format Parse/Common.hs pair (`checkMultiline`): a line break
    // from the label to the end of the type.
    splits.push(
      self.split_within({ start: name.range.start, end: value.range.end, }),
    )
    work.push(
      Leaf(() => {
        let lead_before = match previous {
          Some(r) => self.before_item(Some(r), f.range)
          None => @pretty.empty()
        }
        // elm-format Box.hs formatPair: the comments between the label and
        // the `:` follow the label (`formatTailCommented`). When one of them
        // is not one line, the label, each comment, the `:` and the type go
        // on lines of their own, the last two at the next tab stop.
        let colon = self.token_after(name.range.end)
        let label_post = self.take_if(Trailing, name.range, c => {
          is_line_comment(c) && ends_before(c, colon)
        })
        label_post.append(
          self.take_if(Leading, value.range, c => ends_before(c, colon)),
        )
        let lead = self.after_comma(previous, f.range)
        let moved = self.after_token(name.range)
        let label = self.with_comments(
          name.range,
          self.lower_name(p.child("name", 0), name.value),
        )
        // The comments after the type go after the field, outside its group.
        let value_trail = self.take(Trailing, value.range)
        parts.push({ lead_before, label_post, lead, moved, label, value_trail, })
        @pretty.empty()
      }),
    )
    work.push(Type(p.child("typeAnnotation", 0), value, AnyType))
    let next = fields.get(i + 1).map(n => n.range)
    work.push(Leaf(() => self.trailing_before_comma(f.range, next)))
  }
  (
    work,
    (docs, start) => {
      let ds = []
      let leads = []
      for i in 0..<fields.length() {
        let part = parts[i]
        let value = docs[start + 3 * i + 1]
        let trail = docs[start + 3 * i + 2]
        leads.push(part.lead_before)
        let pair = if part.label_post.iter().all(one_line) {
          field(
            splits[i],
            part.label + comments_after(part.label_post),
            self.separator(fields[i].value.name.range, " :", part.moved),
            value,
          )
        } else {
          part.label +
          @pretty.hardline() +
          comment_block(part.label_post) +
          @pretty.tab(
            4,
            @pretty.hardline() +
            @pretty.text(":") +
            comments_after(part.moved) +
            @pretty.hardline() +
            value,
          )
        }
        ds.push(part.lead + pair + comments_after(part.value_trail) + trail)
      }
      (ds, leads)
    },
  )
}

///|
/// `a -> b -> c` as a doc (see `Ctx::arrow_chain_plan`); for a signature,
/// which has no `Type` item of its own.
fn Ctx::arrow_chain(
  self : Ctx,
  path : @syntax.NodePath,
  t : @ast.Node[@ast.TypeAnnotation],
  eol~ : Array[@ast.Node[String]] = [],
) -> @pretty.Doc raise PrintError {
  let (items, combine) = self.arrow_chain_plan(path, t, eol~)
  self.run(Plan(items, combine))
}

///|
/// The plan of `a -> b -> c`, flattened without recursion and without its
/// own group (a signature shares its group with `name :`). Not a function
/// type: the type itself. The comments before a flattened function type go
/// before its `->`.
///
/// In the `ElmFormat` layout (elm-format Box.hs `FunctionType`), a line
/// break anywhere in the type (Parse/Helpers.hs `separated`) puts each `->`
/// on its own line, and a multi-line type after a `->` goes on the next
/// line at the next tab stop (`prefixOrIndented`). The comments after a
/// `->` go after it.
fn Ctx::arrow_chain_plan(
  self : Ctx,
  path : @syntax.NodePath,
  t : @ast.Node[@ast.TypeAnnotation],
  eol~ : Array[@ast.Node[String]] = [],
) -> (Array[Work], (Array[@pretty.Doc]) -> @pretty.Doc) {
  let split = self.split_within(t.range)
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
  let work : Array[Work] = []
  // Per step: the comments after the `->` that trail the type before it
  // (taken before that type prints), and the leading comments of the
  // flattened type after the `->`.
  let moved : Array[Array[@ast.Node[String]]] = []
  let leads : Array[@pretty.Doc] = []
  let mut node = t
  let mut p = path
  let mut first = true
  let mut steps = 0
  while node.value is FunctionTypeAnnotation(left, right) &&
        (first || flattens(node)) {
    work.push(
      Leaf(() => {
        moved.push(
          match split {
            Fit => self.after_token(left.range)
            Join | Split => {
              let next = self.token_after(left.range.end)
              self.take_if(Trailing, left.range, c => !ends_before(c, next))
            }
          },
        )
        @pretty.empty()
      }),
    )
    work.push(Parts(p.child("left", 0), left, ArrowLeft))
    first = false
    p = p.child("right", 0)
    node = right
    let next = node
    if flattens(next) {
      work.push(
        Leaf(() => {
          leads.push(self.leading(next.range))
          @pretty.empty()
        }),
      )
    } else {
      work.push(
        Leaf(() => {
          leads.push(@pretty.empty())
          @pretty.empty()
        }),
      )
    }
    steps += 1
  }
  if first {
    return ([Parts(p, node, AnyType)], docs => docs[0] + docs[1] + docs[2])
  }
  // A signature's type has no `Type` item of its own: its comments are
  // taken here.
  work.push(Leaf(() => self.leading(t.range)))
  work.push(Parts(p, node, ArrowLeft))
  work.push(Leaf(() => self.trailing(t.range)))
  (
    work,
    docs => {
      // Per step five docs: the moved marker, lead, body, trail, the lead
      // marker. Then the chain's own leading comments, the last type's
      // three docs and the chain's trailing comments.
      let parts = (k : Int32) => {
        (docs[5 * k + 1], docs[5 * k + 2], docs[5 * k + 3])
      }
      let (f_lead, f_body, f_trail) = parts(0)
      let mut d = f_lead + f_body + f_trail
      for k in 1..<steps {
        d = d + arrow(leads[k - 1], moved[k - 1], parts(k))
      }
      let base = 5 * steps
      let own = docs[base]
      let last = (
        docs[base + 1],
        docs[base + 2],
        docs[base + 3] + comments_after(eol),
      )
      own + d + arrow(leads[steps - 1], moved[steps - 1], last) + docs[base + 4]
    },
  )
}
