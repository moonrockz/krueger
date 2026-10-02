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
  match p.value {
    AllPattern => @pretty.text("_")
    UnitPattern => @pretty.text("()")
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
      flat_sequence("(", ")", self.pattern_items(path, level, items))
    }
    ListPattern(items) =>
      flat_sequence("[", "]", self.pattern_items(path, level, items))
    RecordPattern(names) => {
      let docs = []
      for i, x in names {
        docs.push(self.lower_name(path.child("value", i), x.value))
      }
      flat_sequence("{", "}", docs)
    }
    VarPattern(name) => self.lower_name(path, name)
    NamedPattern(name_ref, args) => {
      let head = qualified_upper(path, name_ref.module_name, name_ref.name)
      guard !args.is_empty() else { return head }
      let mut d = head
      for i, a in args {
        d = d +
          @pretty.text(" ") +
          self.pattern_doc(path.child("patterns", i), level + 1, a, PatternArg)
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
        d = d +
          self.pattern_doc(q.child("left", 0), level + 1, left, ConsLeft) +
          @pretty.text(" :: ")
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
      let d = self.pattern_doc(
          path.child("pattern", 0),
          level + 1,
          inner,
          AsInner,
        ) +
        @pretty.text(" as ") +
        self.lower_name(path.child("name", 0), name.value)
      match at {
        AnyPattern => d
        ConsLeft | AsInner | PatternArg => flat_parens(d)
      }
    }
    ParenthesizedPattern(x) =>
      flat_parens(
        self.pattern_doc(path.child("value", 0), level + 1, x, AnyPattern),
      )
  }
}

///|
fn Ctx::pattern_items(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  items : ArrayView[@ast.Node[@ast.Pattern]],
) -> Array[@pretty.Doc] raise PrintError {
  let docs = []
  for i, x in items {
    docs.push(
      self.pattern_doc(path.child("value", i), level + 1, x, AnyPattern),
    )
  }
  docs
}
