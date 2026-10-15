///|
/// Where a pattern is: this decides its parentheses (see
/// `pattern_parens`).
priv enum PatternAt {
  AnyPattern // case branch, let, tuple and list item, inside parentheses
  ConsLeft // left of `::`: `::` and `as` patterns need parentheses
  ConsTail // the last pattern right of `::`
  AsInner // the pattern of an `as`: `::` and `as` patterns need parentheses
  PatternArg // argument or destructuring pattern: also a constructor with arguments
}

///|
/// Whether the printer writes `p` at `at` in parentheses. A `::` or `as`
/// pattern needs them left of `::`, in an `as` and as an argument; a
/// constructor with arguments needs them as an argument. elm-format also
/// writes a constructor with arguments in parentheses before and after
/// `::` and in an `as` (Box.hs `formatPattern`: those places are
/// `SpaceSeparated`). elm-syntax reads `a :: b as c` as `a :: (b as c)`,
/// so an `as` after `::` has none.
fn pattern_parens(p : @ast.Pattern, at : PatternAt) -> Bool {
  match (p, at) {
    (NamedPattern(_, args), PatternArg | ConsLeft | ConsTail | AsInner) =>
      !args.is_empty()
    (UnConsPattern(_, _) | AsPattern(_, _), PatternArg | ConsLeft | AsInner) =>
      true
    _ => false
  }
}

///|
/// The pattern at `path` with its comments. It runs on the work stack
/// (`Ctx::run`), so nested patterns do not recurse: a pattern of any depth
/// prints on every target.
fn Ctx::pattern_doc(
  self : Ctx,
  path : @syntax.NodePath,
  p : @ast.Node[@ast.Pattern],
  at : PatternAt,
) -> @pretty.Doc raise PrintError {
  self.run(Pat(path, p, at))
}

///|
/// The plan of a pattern: its leading comments, its body and its trailing
/// comments, in that order.
fn Ctx::pattern_plan(
  self : Ctx,
  path : @syntax.NodePath,
  p : @ast.Node[@ast.Pattern],
  at : PatternAt,
) -> (Array[Work], (Array[@pretty.Doc]) -> @pretty.Doc) raise PrintError {
  let (items, combine) = self.pattern_body_plan(path, p, at)
  (
    [
      Leaf(() => self.leading(p.range)),
      Plan(items, combine),
      Leaf(() => self.trailing(p.range)),
    ],
    docs => docs[0] + docs[1] + docs[2],
  )
}

///|
/// A plan with one leaf.
fn leaf(
  f : () -> @pretty.Doc raise PrintError,
) -> (Array[Work], (Array[@pretty.Doc]) -> @pretty.Doc) {
  ([Leaf(f)], docs => docs[0])
}

///|
fn join_docs(docs : Array[@pretty.Doc]) -> @pretty.Doc {
  let mut d = @pretty.empty()
  for x in docs {
    d = d + x
  }
  d
}

///|
/// The plan of a pattern without its own comments. Patterns are on one
/// line, so a line comment in a pattern is followed by a line break
/// indented by 4 (`Ctx::after`). The leaves take comments in source
/// order; the items of a nested pattern are `Pat` work items.
fn Ctx::pattern_body_plan(
  self : Ctx,
  path : @syntax.NodePath,
  p : @ast.Node[@ast.Pattern],
  at : PatternAt,
) -> (Array[Work], (Array[@pretty.Doc]) -> @pretty.Doc) raise PrintError {
  let parens = pattern_parens(p.value, at)
  let wrap = (d : @pretty.Doc) => if parens { flat_parens(d) } else { d }
  match p.value {
    AllPattern => done(@pretty.text("_"))
    UnitPattern =>
      leaf(() => {
        @pretty.text("(") + self.inner_alone(p.range) + @pretty.text(")")
      })
    CharPattern(c) => done(@pretty.text(char_literal(c)))
    StringPattern(s) => done(self.string_doc(p.range, s))
    IntPattern(v) => {
      guard v >= 0L else { raise PrintError(path~, problem=NegativePattern) }
      done(@pretty.text(self.integer_text(p.range, v)))
    }
    HexPattern(v) => {
      guard v >= 0L else { raise PrintError(path~, problem=NegativePattern) }
      done(@pretty.text(self.hex_literal_text(p.range, v)))
    }
    FloatPattern(x) => {
      if self.float_lexeme_text(p.range, x) is Some(text) {
        return done(@pretty.text(text))
      }
      guard !x.is_nan() && !x.is_inf() else {
        raise PrintError(path~, problem=NonFiniteFloat(x))
      }
      guard !is_negative(x) else {
        raise PrintError(path~, problem=NegativePattern)
      }
      done(@pretty.text(float_text(x)))
    }
    TuplePattern(items) => {
      guard items.length() >= 2 else {
        raise PrintError(path~, problem=ShortTuple)
      }
      self.flat_items_plan("(", ")", path, p.range, items)
    }
    ListPattern(items) => self.flat_items_plan("[", "]", path, p.range, items)
    RecordPattern(names) =>
      leaf(() => {
        let docs = []
        for i, x in names {
          let name = self.lower_name(path.child("value", i), x.value)
          docs.push((self.with_comments(x.range, name), x.range))
        }
        self.flat_sequence("{", "}", p.range, docs)
      })
    VarPattern(name) => done(self.lower_name(path, name))
    NamedPattern(name_ref, args) => {
      let head = qualified_upper(path, name_ref.module_name, name_ref.name)
      guard !args.is_empty() else { return done(head) }
      let items : Array[Work] = []
      for i, a in args {
        if i > 0 {
          let previous = args[i - 1].range
          items.push(Leaf(() => self.after(previous, " ")))
        }
        items.push(Pat(path.child("patterns", i), a, PatternArg))
      }
      if parens {
        let last = args[args.length() - 1].range
        items.push(Leaf(() => self.after(last, "")))
      }
      (items, docs => wrap(head + @pretty.text(" ") + join_docs(docs)))
    }
    UnConsPattern(_, _) => {
      let items : Array[Work] = []
      // The comments after each `::` that trail the pattern before it,
      // taken before that pattern prints (`Ctx::after_token`).
      let moved : Array[Array[@ast.Node[String]]] = []
      let mut node = p
      let mut q = path
      let mut step = 0
      while node.value is UnConsPattern(left, right) {
        if node.range != p.range {
          let r = node.range
          items.push(Leaf(() => self.leading(r)))
        }
        let k = step
        items.push(
          Leaf(() => {
            moved.push(self.after_token(left.range))
            @pretty.empty()
          }),
        )
        items.push(Pat(q.child("left", 0), left, ConsLeft))
        items.push(
          Leaf(() => {
            self.separator(left.range, " ::", moved[k]) + @pretty.text(" ")
          }),
        )
        q = q.child("right", 0)
        node = right
        step += 1
      }
      items.push(Pat(q, node, ConsTail))
      (items, docs => wrap(join_docs(docs)))
    }
    AsPattern(inner, name) => {
      let moved : Array[Array[@ast.Node[String]]] = []
      let items : Array[Work] = [
        Leaf(() => {
          moved.push(self.after_token(inner.range))
          @pretty.empty()
        }),
        Pat(path.child("pattern", 0), inner, AsInner),
        Leaf(() => {
          self.separator(inner.range, " as", moved[0]) +
          @pretty.text(" ") +
          self.with_comments(
            name.range,
            self.lower_name(path.child("name", 0), name.value),
          )
        }),
      ]
      (items, docs => wrap(join_docs(docs)))
    }
    ParenthesizedPattern(x) =>
      (
        [
          Pat(path.child("value", 0), x, AnyPattern),
          Leaf(() => self.after(x.range, "") + self.inline_inner(p.range)),
        ],
        docs => flat_parens(docs[0] + docs[1]),
      )
  }
}

///|
/// The plan of `( a, b )` or `[ a, b ]`, always on one line (see
/// `flat_sequence`): each item, the comments after it, and the comments of
/// the pattern at `owner` before the closing token.
fn Ctx::flat_items_plan(
  self : Ctx,
  open : String,
  close : String,
  path : @syntax.NodePath,
  owner : @ast.Range,
  items : ArrayView[@ast.Node[@ast.Pattern]],
) -> (Array[Work], (Array[@pretty.Doc]) -> @pretty.Doc) {
  guard !items.is_empty() else {
    return leaf(() => {
      @pretty.text(open) +
      self.inner_alone(owner, brace=open == "{") +
      @pretty.text(close)
    })
  }
  let count = items.length()
  let work : Array[Work] = []
  for i, x in items {
    work.push(Pat(path.child("value", i), x, AnyPattern))
    if i + 1 < count {
      let r = x.range
      work.push(Leaf(() => self.after(r, "")))
    }
  }
  let last = items[count - 1].range
  // The break after a line comment comes before the inner comments.
  work.push(Leaf(() => self.after(last, "") + self.inline_inner(owner)))
  (
    work,
    docs => {
      let ds = []
      for i in 0..<count {
        ds.push(
          if i + 1 < count {
            docs[2 * i] + docs[2 * i + 1]
          } else {
            docs[2 * i]
          },
        )
      }
      flat_sequence(open, close, ds, inner=docs[2 * count - 1])
    },
  )
}

///|
/// `{ a, b }` always on one line (see `flat_sequence`), with the comments
/// of the pattern at `owner` before the closing token.
fn Ctx::flat_sequence(
  self : Ctx,
  open : String,
  close : String,
  owner : @ast.Range,
  items : Array[(@pretty.Doc, @ast.Range)],
) -> @pretty.Doc {
  guard !items.is_empty() else {
    return @pretty.text(open) +
      self.inner_alone(owner, brace=open == "{") +
      @pretty.text(close)
  }
  let docs = []
  for i, item in items {
    let (d, r) = item
    docs.push(if i + 1 < items.length() { d + self.after(r, "") } else { d })
  }
  let (_, last) = items[items.length() - 1]
  // The break after a line comment comes before the inner comments.
  let end = self.after(last, "") + self.inline_inner(owner)
  flat_sequence(open, close, docs, inner=end)
}

///|
/// The inner comments of the node at `owner` on the line: ` {- a -}`. A
/// line comment is followed by a line break indented by 4.
fn Ctx::inline_inner(self : Ctx, owner : @ast.Range) -> @pretty.Doc {
  let mut d = @pretty.empty()
  for c in self.take(Inner, owner) {
    d = d + @pretty.text(" ") + comment_doc(c)
    if is_line_comment(c) {
      d = d + @pretty.nest(4, @pretty.hardline())
    }
  }
  d
}
