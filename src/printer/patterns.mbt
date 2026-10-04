///|
/// Where a pattern is: this decides its parentheses (checked against
/// elm-syntax: `Just x :: xs` and `a :: b as c` need none).
priv enum PatternAt {
  AnyPattern // case branch, let, tuple and list item, inside parentheses, right of `::`
  ConsLeft // left of `::`: `::` and `as` patterns need parentheses
  AsInner // the pattern of an `as`: `::` and `as` patterns need parentheses
  PatternArg // argument or destructuring pattern: also a constructor with arguments
}

///|
fn Ctx::pattern_doc(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  p : @ast.Node[@ast.Pattern],
  at : PatternAt,
) -> @pretty.Doc raise PrintError {
  check_level(path, level)
  let lead = self.leading(p.range)
  let d = self.pattern_body(path, level, p, at)
  lead + d + self.trailing(p.range)
}

///|
/// The pattern without its own comments. Patterns are on one line, so a
/// line comment in a pattern is followed by a line break indented by 4
/// (`Ctx::after`).
fn Ctx::pattern_body(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  p : @ast.Node[@ast.Pattern],
  at : PatternAt,
) -> @pretty.Doc raise PrintError {
  match p.value {
    AllPattern => @pretty.text("_")
    UnitPattern =>
      @pretty.text("(") + self.inner_alone(p.range) + @pretty.text(")")
    CharPattern(c) => @pretty.text(char_literal(c))
    StringPattern(s) => @pretty.text(string_literal(s))
    IntPattern(v) => {
      guard v >= 0L else { raise PrintError(path~, problem=NegativePattern) }
      @pretty.text(v.to_string())
    }
    HexPattern(v) => {
      guard v >= 0L else { raise PrintError(path~, problem=NegativePattern) }
      @pretty.text(hex_text(v))
    }
    FloatPattern(x) => {
      guard !x.is_nan() && !x.is_inf() else {
        raise PrintError(path~, problem=NonFiniteFloat(x))
      }
      guard !is_negative(x) else {
        raise PrintError(path~, problem=NegativePattern)
      }
      @pretty.text(float_text(x))
    }
    TuplePattern(items) => {
      guard items.length() >= 2 else {
        raise PrintError(path~, problem=ShortTuple)
      }
      self.flat_sequence(
        "(",
        ")",
        p.range,
        self.pattern_items(path, level, items),
      )
    }
    ListPattern(items) =>
      self.flat_sequence(
        "[",
        "]",
        p.range,
        self.pattern_items(path, level, items),
      )
    RecordPattern(names) => {
      let docs = []
      for i, x in names {
        let name = self.lower_name(path.child("value", i), x.value)
        docs.push((self.with_comments(x.range, name), x.range))
      }
      self.flat_sequence("{", "}", p.range, docs)
    }
    VarPattern(name) => self.lower_name(path, name)
    NamedPattern(name_ref, args) => {
      let head = qualified_upper(path, name_ref.module_name, name_ref.name)
      guard !args.is_empty() else { return head }
      let mut d = head + @pretty.text(" ")
      for i, a in args {
        if i > 0 {
          d = d + self.after(args[i - 1].range, " ")
        }
        d = d +
          self.pattern_doc(path.child("patterns", i), level + 1, a, PatternArg)
      }
      match at {
        PatternArg => d = d + self.after(args[args.length() - 1].range, "")
        AnyPattern | ConsLeft | AsInner => ()
      }
      match at {
        PatternArg => flat_parens(d)
        AnyPattern | ConsLeft | AsInner => d
      }
    }
    UnConsPattern(_, _) => {
      let mut node = p
      let mut q = path
      let mut d = @pretty.empty()
      while node.value is UnConsPattern(left, right) {
        if node.range != p.range {
          d = d + self.leading(node.range)
        }
        let moved = self.after_token(left.range)
        d = d +
          self.pattern_doc(q.child("left", 0), level + 1, left, ConsLeft) +
          self.separator(left.range, " ::", moved) +
          @pretty.text(" ")
        q = q.child("right", 0)
        node = right
      }
      d = d + self.pattern_doc(q, level + 1, node, AnyPattern)
      match at {
        AnyPattern => d
        ConsLeft | AsInner | PatternArg => flat_parens(d)
      }
    }
    AsPattern(inner, name) => {
      let moved = self.after_token(inner.range)
      let d = self.pattern_doc(
          path.child("pattern", 0),
          level + 1,
          inner,
          AsInner,
        ) +
        self.separator(inner.range, " as", moved) +
        @pretty.text(" ") +
        self.with_comments(
          name.range,
          self.lower_name(path.child("name", 0), name.value),
        )
      match at {
        AnyPattern => d
        ConsLeft | AsInner | PatternArg => flat_parens(d)
      }
    }
    ParenthesizedPattern(x) =>
      flat_parens(
        self.pattern_doc(path.child("value", 0), level + 1, x, AnyPattern) +
        self.after(x.range, "") +
        self.inline_inner(p.range),
      )
  }
}

///|
fn Ctx::pattern_items(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  items : ArrayView[@ast.Node[@ast.Pattern]],
) -> Array[(@pretty.Doc, @ast.Range)] raise PrintError {
  let docs = []
  for i, x in items {
    docs.push(
      (
        self.pattern_doc(path.child("value", i), level + 1, x, AnyPattern),
        x.range,
      ),
    )
  }
  docs
}

///|
/// `[ a, b ]` always on one line (see `flat_sequence`), with the comments
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
