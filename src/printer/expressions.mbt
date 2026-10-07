///|
/// Where an expression is: this decides its parentheses (see the table in
/// the plan, and spec section 4.3).
priv enum ExprAt {
  AnyExpr
  /// An operand of an operator chain, other than the last.
  Operand
  /// The last operand of a chain, after an operator other than `<|`.
  LastOperand
  /// The last operand of a chain, after `<|`.
  Piped
  ExprArg
  Head
  Negated
  Target
}

///|
fn is_negative_literal(e : @ast.Expression) -> Bool {
  match e {
    Integer(x) | Hex(x) => x < 0L
    Floatable(x) => is_negative(x)
    _ => false
  }
}

///|
fn is_atom(e : @ast.Expression) -> Bool {
  match e {
    Application(_)
    | OperatorApplication(_, _, _, _)
    | Negation(_)
    | IfBlock(_, _, _)
    | CaseExpression(_)
    | LetExpression(_)
    | LambdaExpression(_) => false
    _ => !is_negative_literal(e)
  }
}

///|
fn needs_parens(e : @ast.Expression, at : ExprAt) -> Bool {
  match at {
    AnyExpr | LastOperand | Piped => false
    Operand =>
      e
      is (LambdaExpression(_)
      | IfBlock(_, _, _)
      | CaseExpression(_)
      | LetExpression(_))
    ExprArg => !is_atom(e) && !(e is Negation(_)) && !is_negative_literal(e)
    Head => !is_atom(e)
    Negated => !is_atom(e) || e is RecordAccessFunction(_)
    // The parser reads `.f` after a lower-case name, a record, a record
    // update or a closing parenthesis as a record access; after anything
    // else (`"s".f`, `[].f`, `( a, b ).f`, `1.f`, `Just.f`) it reads a
    // record access function or rejects the text.
    Target =>
      match e {
        FunctionOrValue(_, name) => is_upper(name)
        RecordExpr(_)
        | RecordUpdateExpression(_, _)
        | ParenthesizedExpression(_)
        | RecordAccess(_, _) => false
        _ => true
      }
  }
}

///|
/// elm-format's syntax context (Box.hs `SyntaxContext`): what an
/// expression is, and what its place allows without parentheses.
priv enum SyntaxContext {
  SyntaxSeparated
  SpaceSeparated
  InfixSeparated
  AmbiguousEnd
}

///|
/// The context of an expression (the first part of elm-format's
/// `formatExpression` result): an application is `SpaceSeparated`, an
/// operator chain `InfixSeparated`, a lambda, `if`, `case` or `let`
/// `AmbiguousEnd` (it ends at the end of the text), anything else
/// `SyntaxSeparated`.
fn syntax_context(e : @ast.Expression) -> SyntaxContext {
  match e {
    Application(_) => SpaceSeparated
    OperatorApplication(_, _, _, _) => InfixSeparated
    LambdaExpression(_)
    | IfBlock(_, _, _)
    | CaseExpression(_)
    | LetExpression(_) => AmbiguousEnd
    _ => SyntaxSeparated
  }
}

///|
/// The context that a place gives (the `syntaxParens` calls of
/// elm-format's `formatExpression` and `formatBinops`).
fn place_context(at : ExprAt) -> SyntaxContext {
  match at {
    AnyExpr => SyntaxSeparated
    Operand | LastOperand | Head => InfixSeparated
    Piped => AmbiguousEnd
    ExprArg | Negated | Target => SpaceSeparated
  }
}

///|
/// Whether elm-format writes `e` at `at` in parentheses (Box.hs
/// `needsParensInContext`).
fn elm_format_parens(e : @ast.Expression, at : ExprAt) -> Bool {
  match (syntax_context(e), place_context(at)) {
    (SpaceSeparated, SpaceSeparated)
    | (InfixSeparated, SpaceSeparated)
    | (InfixSeparated, InfixSeparated)
    | (AmbiguousEnd, SpaceSeparated)
    | (AmbiguousEnd, InfixSeparated)
    | (InfixSeparated, AmbiguousEnd) => true
    _ => false
  }
}

///|
/// The parentheses around `e` at `at`: the ones that the parser needs
/// (`needs_parens`) and the ones that elm-format writes. elm-format writes
/// a lambda, `if`, `case` or `let` at the end of a chain in parentheses,
/// except after `<|`; the parser does not need them.
fn parens_at(e : @ast.Expression, at : ExprAt) -> Bool {
  needs_parens(e, at) || elm_format_parens(e, at)
}

///|
/// An item of the expression printer's work stack. The printer does not
/// recurse per nesting level: `Ctx::run` pops items until the stack is
/// empty, so deep ASTs do not overflow the call stack (wasm overflows at a
/// few hundred frames).
priv enum Work {
  /// Print this expression: check its level, then push its plan.
  Expr(@syntax.NodePath, Int, @ast.Node[@ast.Expression], ExprAt)
  /// Make a doc that has no nested expression (a name, a pattern, a type).
  /// It runs when it is popped, so errors come in source order.
  Leaf(() -> @pretty.Doc raise PrintError)
  /// Run these items in order, then combine their docs into one.
  Plan(Array[Work], (Array[@pretty.Doc]) -> @pretty.Doc)
  /// Pop this many docs and push their combination.
  Build(Int, (Array[@pretty.Doc]) -> @pretty.Doc)
}

///|
/// Runs the work stack from `start` and returns its one doc. Items give
/// their docs in order: each `Plan` and `Expr` pushes a `Build`, then its
/// items in reverse, so the first item runs first.
fn Ctx::run(self : Ctx, start : Work) -> @pretty.Doc raise PrintError {
  let work : Array[Work] = [start]
  let results : Array[@pretty.Doc] = []
  fn push_plan(items : Array[Work], combine) {
    work.push(Build(items.length(), combine))
    for i = items.length() - 1; i >= 0; i = i - 1 {
      work.push(items[i])
    }
  }

  while work.pop() is Some(item) {
    match item {
      Expr(path, level, e, at) => {
        check_level(path, level)
        // The leading comments are taken now, before the parts; the
        // trailing comments after them.
        let lead = self.leading(e.range)
        let wrap = (d : @pretty.Doc) => lead + d + self.trailing(e.range)
        // elm-format Box.hs formatExpression `Parens`: parentheses with
        // no comments inside go, and the expression in them takes their
        // place (see `normalize_file`).
        if e.value is ParenthesizedExpression(x) &&
          !parens_at(x.value, at) &&
          !self.comment_in_parens(e.range, x.range) {
          push_plan([Expr(path.child("parenthesized", 0), level + 1, x, at)], docs => {
            wrap(docs[0])
          })
          continue
        }
        let (items, combine) = self.expr_plan(path, level, e)
        if parens_at(e.value, at) {
          let split = self.join()
          push_plan(items, docs => wrap(parens(split, combine(docs))))
        } else {
          push_plan(items, docs => wrap(combine(docs)))
        }
      }
      Leaf(f) => results.push(f())
      Plan(items, combine) => push_plan(items, combine)
      Build(count, combine) => {
        let start = results.length() - count
        let docs = []
        for i in start..<results.length() {
          docs.push(results[i])
        }
        results.truncate(start)
        results.push(combine(docs))
      }
    }
  }
  results[0]
}

///|
fn Ctx::expr_doc(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  e : @ast.Node[@ast.Expression],
  at : ExprAt,
) -> @pretty.Doc raise PrintError {
  self.run(Expr(path, level, e, at))
}

///|
/// A plan with no items: the doc is already known.
fn done(d : @pretty.Doc) -> (Array[Work], (Array[@pretty.Doc]) -> @pretty.Doc) {
  ([], _ => d)
}

///|
/// The items of `label = value` for each setter, four per setter: the
/// comments before its `,` (see `Ctx::before_item`), the label, the value
/// and the comments after the setter.
fn Ctx::setter_items(
  self : Ctx,
  path : @syntax.NodePath,
  field_name : String,
  level : Int,
  setters : ArrayView[@ast.Node[@ast.RecordSetter]],
) -> Array[Work] {
  let items = []
  for i, s in setters {
    let p = path.child(field_name, i)
    let name = s.value.field
    let previous = if i > 0 { Some(setters[i - 1].range) } else { None }
    let next = setters.get(i + 1).map(n => n.range)
    items.push(
      Leaf(() => {
        match previous {
          Some(r) => self.before_item(Some(r), s.range)
          None => @pretty.empty()
        }
      }),
    )
    let value = s.value.expression
    // The comments after the value go after the field, outside its group:
    // taken before the value.
    let value_trail = []
    items.push(
      Leaf(() => {
        let label = self.lower_name(p.child("field", 0), name.value)
        value_trail.append(self.take(Trailing, value.range))
        let moved = self.after_token(name.range)
        self.after_comma(previous, s.range) +
        self.with_comments(name.range, label) +
        self.separator(name.range, " =", moved)
      }),
    )
    items.push(Expr(p.child("expression", 0), level + 1, value, AnyExpr))
    items.push(
      Leaf(() => {
        comments_after(value_trail) + self.trailing_before_comma(s.range, next)
      }),
    )
  }
  items
}

///|
/// The setter docs from `docs[from]` on, four per setter (see
/// `Ctx::setter_items`), and the comments before each.
fn Ctx::setter_docs(
  self : Ctx,
  setters : ArrayView[@ast.Node[@ast.RecordSetter]],
  docs : Array[@pretty.Doc],
  from : Int,
) -> (Array[@pretty.Doc], Array[@pretty.Doc]) {
  let fields = []
  let leads = []
  for k, s in setters {
    let i = from + 4 * k
    leads.push(docs[i])
    // elm-format Parse/Common.hs pair (`checkMultiline`): a line break
    // anywhere from the label to the end of the value puts the value on
    // the next line.
    let split = self.split_within({
      start: s.value.field.range.start,
      end: s.value.expression.range.end,
    })
    fields.push(
      field(split, docs[i + 1], @pretty.empty(), docs[i + 2]) + docs[i + 3],
    )
  }
  (fields, leads)
}

///|
/// The last setter's range, if any.
fn last_range(setters : ArrayView[@ast.Node[@ast.RecordSetter]]) -> @ast.Range? {
  setters.last().map(s => s.range)
}

///|
/// A number literal: `digits(x)`, or a negation of it for a negative `x`.
fn number_doc(
  path : @syntax.NodePath,
  x : Int64,
  digits : (Int64) -> String,
) -> @pretty.Doc raise PrintError {
  if x >= 0L {
    @pretty.text(digits(x))
  } else if is_min_int(x) {
    raise PrintError(path~, problem=UnrepresentableInt(x))
  } else {
    @pretty.text("-" + digits(-x))
  }
}

///|
/// The work items of an expression's direct parts, in source order, and how
/// their docs combine. It checks the expression itself (its shape, its
/// literal text) before any part; nested expressions are `Expr` items.
fn Ctx::expr_plan(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  e : @ast.Node[@ast.Expression],
) -> (Array[Work], (Array[@pretty.Doc]) -> @pretty.Doc) raise PrintError {
  match e.value {
    UnitExpr =>
      done(@pretty.text("(") + self.inner_alone(e.range) + @pretty.text(")"))
    Application(items) => {
      guard items.length() >= 2 else {
        raise PrintError(path~, problem=ShortApplication)
      }
      let parts = [
        Expr(path.child("application", 0), level + 1, items[0], Head),
      ]
      for i in 1..<items.length() {
        parts.push(
          Expr(path.child("application", i), level + 1, items[i], ExprArg),
        )
      }
      // elm-format Parse/Expression.hs appExpr: `FASplitFirst` when the
      // source has a line break in the function or in or before the first
      // argument; `FAJoinFirst SplitAll` when it has one in or before a
      // later argument.
      let first = self.split_within({
        start: items[0].range.start,
        end: items[1].range.end,
      })
      // With one argument there are no later arguments: `rest` is not used.
      let rest = if items.length() > 2 {
        self.split_from({ start: items[2].range.start, end: e.range.end, })
      } else {
        self.join()
      }
      (parts, docs => application(first, rest, docs[0], docs[1:].to_owned()))
    }
    OperatorApplication(_, _, _, _) => self.chain_plan(path, level, e)
    FunctionOrValue(module_, name) =>
      done(self.qualified_value(path, module_, name))
    IfBlock(c, t, f) => self.if_plan(path, level, c, t, f)
    PrefixOperator(symbol) =>
      done(@pretty.text("(" + self.operator_symbol(path, symbol) + ")"))
    Operator(symbol) => done(@pretty.text(self.operator_symbol(path, symbol)))
    Integer(x) => done(number_doc(path, x, n => self.integer_text(e.range, n)))
    Hex(x) => done(number_doc(path, x, n => self.hex_literal_text(e.range, n)))
    Floatable(x) => {
      if self.float_lexeme_text(e.range, x) is Some(text) {
        return done(@pretty.text(text))
      }
      guard !x.is_nan() && !x.is_inf() else {
        raise PrintError(path~, problem=NonFiniteFloat(x))
      }
      if is_negative(x) {
        done(@pretty.text("-" + float_text(-x)))
      } else {
        done(@pretty.text(float_text(x)))
      }
    }
    Negation(x) =>
      (
        [Expr(path.child("negation", 0), level + 1, x, Negated)],
        docs => @pretty.text("-") + docs[0],
      )
    Literal(s) => done(self.string_doc(e.range, s))
    CharLiteral(c) => done(@pretty.text(char_literal(c)))
    TupledExpression(items) => {
      guard items.length() >= 2 else {
        raise PrintError(path~, problem=ShortTuple)
      }
      let after : Array[Array[@ast.Node[String]]] = Array::makei(
        items.length(),
        _ => [],
      )
      (
        self.sequence_items(path, "tupled", level, items, after=Some(after)),
        docs => {
          let (items, leads) = item_docs(docs)
          // elm-format Box.hs Tuple (`formatC2Eol`): the comments before a
          // `,` go under the item before it.
          for i, cs in after {
            if !cs.is_empty() {
              items[i] = items[i] + @pretty.hardline() + comment_box(cs)
            }
          }
          // elm-format Parse/Helpers.hs surround (`parens`): a line break
          // anywhere inside the parentheses.
          // A comment before the `)` goes in the column of the items.
          sequence(
            self.split_within(e.range),
            "(",
            ")",
            items,
            leads~,
            inner=@pretty.nest(2, self.inner_close(e.range)),
          )
        },
      )
    }
    ParenthesizedExpression(x) =>
      (
        [Expr(path.child("parenthesized", 0), level + 1, x, AnyExpr)],
        // elm-format Box.hs `Parens` has no source rule: the parentheses
        // break only when the expression in them is multi-line.
        // A comment before the `)` goes in the column after the `(`.
        docs => parens(self.join(), docs[0], inner=self.inner_close(e.range)),
      )
    LetExpression(b) => {
      guard !b.declarations.is_empty() else {
        raise PrintError(path~, problem=EmptyLet)
      }
      // Two docs per declaration: its comments, then the declaration. The
      // comments after a declaration go before the next one (elm-format).
      let parts = []
      for i, dn in b.declarations {
        let p = path.child("declarations", i)
        let previous = if i > 0 {
          Some(b.declarations[i - 1].range)
        } else {
          None
        }
        parts.push(Leaf(() => self.moved_then_leading(previous, dn.range)))
        match dn.value {
          LetFunction(f) =>
            parts.push(self.function_plan(p, level + 1, f, in_let=true))
          LetDestructuring(pattern, value) =>
            parts.push(
              Plan(
                [
                  Leaf(() => {
                    let moved = self.after_token(pattern.range)
                    // Elm reads a destructuring pattern as a term: `(Wrap w) =`.
                    self.pattern_doc(
                      p.child("pattern", 0),
                      level + 1,
                      pattern,
                      PatternArg,
                    ) +
                    self.separator(pattern.range, " =", moved)
                  }),
                  Expr(p.child("expression", 0), level + 1, value, AnyExpr),
                ],
                docs => {
                  @pretty.nest(4, docs[0]) +
                  @pretty.nest(4, @pretty.hardline() + docs[1])
                },
              ),
            )
        }
      }
      // The comments before `in`: after the last declaration, and before
      // the body when the source has them before `in`.
      let last_decl = b.declarations[b.declarations.length() - 1].range
      let body = b.expression
      parts.push(
        Leaf(() => {
          let cs = self.take(Trailing, last_decl)
          if self.token_before(body.range.start) is Some(in_at) {
            cs.append(
              self.take_if(Leading, body.range, c => {
                at_or_before(c.range.end, in_at)
              }),
            )
          }
          if cs.is_empty() {
            @pretty.empty()
          } else {
            @pretty.hardline() + comment_block(cs, before=true)
          }
        }),
      )
      parts.push(Expr(path.child("expression", 0), level + 1, body, AnyExpr))
      (
        parts,
        docs => {
          let count = b.declarations.length()
          let mut decls = @pretty.empty()
          for i in 0..<count {
            decls = decls +
              (if i == 0 {
                @pretty.hardline()
              } else {
                @pretty.hardline() + @pretty.hardline()
              }) +
              docs[2 * i] +
              docs[2 * i + 1]
          }
          @pretty.align(
            @pretty.text("let") +
            @pretty.tab(4, decls + docs[2 * count]) +
            @pretty.hardline() +
            @pretty.text("in") +
            @pretty.hardline() +
            docs[2 * count + 1],
          )
        },
      )
    }
    CaseExpression(b) => {
      guard !b.cases.is_empty() else {
        raise PrintError(path~, problem=EmptyCase)
      }
      // Three docs per branch: its comments, the pattern with ` ->`, the
      // body. The comments after a branch go before the next one
      // (elm-format).
      let parts = [
        Expr(path.child("expression", 0), level + 1, b.expression, AnyExpr),
      ]
      for i, c in b.cases {
        let p = path.child("cases", i)
        let previous = if i > 0 {
          Some(case_range(b.cases[i - 1]))
        } else {
          None
        }
        parts.push(Leaf(() => self.moved_then_leading(previous, case_range(c))))
        parts.push(
          Leaf(() => {
            let moved = self.after_token(c.pattern.range)
            @pretty.nest(
              4,
              self.pattern_doc(
                p.child("pattern", 0),
                level + 1,
                c.pattern,
                AnyPattern,
              ) +
              self.separator(c.pattern.range, " ->", moved),
            )
          }),
        )
        parts.push(
          Expr(p.child("expression", 0), level + 1, c.expression, AnyExpr),
        )
      }
      // elm-format Parse/Expression.hs caseExpr (`trackNewline` around the
      // padded subject): a line break after `case`, in the subject or
      // before `of`. The range ends at the first pattern, after `of`.
      let subject_split = self.split_from({
        start: b.expression.range.start,
        end: b.cases[0].pattern.range.start,
      })
      (
        parts,
        docs => {
          let head = @pretty.group(
            @pretty.text("case") +
            @pretty.tab(4, split_line(subject_split) + docs[0]) +
            split_line(subject_split) +
            @pretty.text("of"),
          )
          let mut branches = @pretty.empty()
          for i = 1; i + 2 < docs.length(); i = i + 3 {
            branches = branches +
              (if i == 1 {
                @pretty.hardline()
              } else {
                @pretty.hardline() + @pretty.hardline()
              }) +
              docs[i] +
              docs[i + 1] +
              @pretty.nest(4, @pretty.hardline() + docs[i + 2])
          }
          @pretty.align(head + @pretty.tab(4, branches))
        },
      )
    }
    LambdaExpression(l) => {
      guard !l.args.is_empty() else {
        raise PrintError(path~, problem=NoLambdaArguments)
      }
      let parts = []
      let last = l.args.length() - 1
      for i, a in l.args {
        let p = path.child("patterns", i)
        parts.push(
          Leaf(() => {
            let moved = if i == last { self.after_token(a.range) } else { [] }
            @pretty.nest(
              4,
              self.pattern_doc(p, level + 1, a, PatternArg) +
              self.separator(
                a.range,
                if i == last {
                  " ->"
                } else {
                  " "
                },
                moved,
              ),
            )
          }),
        )
      }
      parts.push(
        Expr(path.child("expression", 0), level + 1, l.expression, AnyExpr),
      )
      let split = self.split_within(e.range)
      (
        parts,
        docs => {
          let last = docs.length() - 1
          let mut head = @pretty.text("\\")
          for i in 0..<last {
            head = head + docs[i]
          }
          // The body indents to the next tab stop right of the `\\`.
          // elm-format Parse/Expression.hs lambdaExpr (`trackNewline`): a
          // line break anywhere in the lambda puts the body on the next
          // line.
          @pretty.align(
            head + @pretty.group(@pretty.tab(4, split_line(split) + docs[last])),
          )
        },
      )
    }
    RecordExpr(setters) =>
      (
        self.setter_items(path, "record", level, setters),
        docs => {
          let (fields, leads) = self.setter_docs(setters, docs, 0)
          let inner = if setters.is_empty() {
            self.inner_alone(e.range, brace=true)
          } else {
            self.inner(e.range, last=last_range(setters))
          }
          // elm-format Parse/Expression.hs recordTerm (`checkMultiline`):
          // a line break anywhere inside the braces.
          sequence(self.split_within(e.range), "{", "}", fields, leads~, inner~)
        },
      )
    ListExpr(items) =>
      (
        self.sequence_items(path, "list", level, items),
        docs => {
          let (items, leads) = item_docs(docs)
          // elm-format Parse/Expression.hs listTerm (`checkMultiline`): a
          // line break anywhere inside the brackets.
          sequence(
            self.split_within(e.range),
            "[",
            "]",
            items,
            leads~,
            inner=self.inner_for(e.range, items.length()),
          )
        },
      )
    RecordAccess(_, _) => {
      let names : Array[(@syntax.NodePath, @ast.Node[String])] = []
      let mut node = e
      let mut p = path
      while node.value is RecordAccess(target, name) {
        names.push((p.child("name", 0), name))
        p = p.child("expression", 0)
        node = target
      }
      let parts = [Expr(p, level + 1, node, Target)]
      for i = names.length() - 1; i >= 0; i = i - 1 {
        let (np, name) = names[i]
        parts.push(
          Leaf(() => {
            self.with_comments(name.range, self.lower_name(np, name.value))
          }),
        )
      }
      (
        parts,
        docs => {
          let mut d = docs[0]
          for i in 1..<docs.length() {
            d = d + @pretty.text(".") + docs[i]
          }
          d
        },
      )
    }
    RecordAccessFunction(s) => {
      // elm-syntax keeps the dot: ".name".
      let name = StringBuilder()
      for i, c in s {
        if i > 0 {
          name.write_char(c)
        }
      }
      guard s.has_prefix(".") && self.is_lower(name.to_string()) else {
        raise PrintError(path~, problem=InvalidName(Lower, s))
      }
      done(@pretty.text(s))
    }
    RecordUpdateExpression(name, setters) => {
      guard !setters.is_empty() else {
        raise PrintError(path~, problem=NoFields)
      }
      let parts = [
        Leaf(() => {
          self.with_comments(
            name.range,
            self.lower_name(path.child("name", 0), name.value),
          )
        }),
      ]
      parts.append(self.setter_items(path, "updates", level, setters))
      (
        parts,
        docs => {
          let (fields, leads) = self.setter_docs(setters, docs, 1)
          // elm-format Parse/Expression.hs recordTerm (`checkMultiline`).
          extension(
            self.split_within(e.range),
            docs[0],
            fields,
            leads~,
            inner=self.inner(e.range, last=last_range(setters)),
          )
        },
      )
    }
    GLSLExpression(s) => {
      guard !s.contains("|]") else {
        raise PrintError(path~, problem=InvalidGlsl)
      }
      done(@pretty.verbatim("[glsl|" + s + "|]"))
    }
  }
}

///|
/// Four items for each item of a list or tuple, at
/// `path.child(field_name, i)`: the comments that the source has after the
/// next `,` among the item's trailing comments (taken before the item, so
/// that they go after that `,`; the doc is empty), the comments before its
/// `,` (see `Ctx::before_item`), those moved comments after its `,`, then
/// the item.
fn Ctx::sequence_items(
  self : Ctx,
  path : @syntax.NodePath,
  field_name : String,
  level : Int,
  items : ArrayView[@ast.Node[@ast.Expression]],
  after? : Array[Array[@ast.Node[String]]]? = None,
) -> Array[Work] {
  let moved : Array[Array[@ast.Node[String]]] = Array::makei(
    items.length() + 1,
    _ => [],
  )
  let parts = []
  for i, x in items {
    let next = items.get(i + 1).map(n => n.range.start)
    parts.push(
      Leaf(() => {
        if next is Some(start) {
          let comma = self.token_before(start)
          moved[i + 1] = self.take_if(Trailing, x.range, c => {
            !ends_before(c, comma)
          })
        }
        @pretty.empty()
      }),
    )
    parts.push(
      Leaf(() => {
        match (i, after) {
          (0, _) => @pretty.empty()
          // A tuple: the comments before the `,` go to `after` of the item
          // before it.
          (_, Some(a)) => {
            let comma = self.token_before(x.range.start)
            a[i - 1] = self.take_if(Leading, x.range, c => ends_before(c, comma))
            @pretty.empty()
          }
          (_, None) => self.before_item(None, x.range)
        }
      }),
    )
    parts.push(Leaf(() => comments_before(moved[i], x.range.start)))
    parts.push(Expr(path.child(field_name, i), level + 1, x, AnyExpr))
  }
  parts
}

///|
/// The items and the comments before their `,`, from the docs of
/// `Ctx::sequence_items`.
fn item_docs(
  docs : Array[@pretty.Doc],
) -> (Array[@pretty.Doc], Array[@pretty.Doc]) {
  let items = []
  let leads = []
  for i = 0; i + 3 < docs.length(); i = i + 4 {
    leads.push(docs[i + 1])
    items.push(docs[i] + docs[i + 2] + docs[i + 3])
  }
  (items, leads)
}

///|
/// `if c then a else if d then b else e`, the `else if` chain flattened
/// without recursion: a clause and a branch per `if`, then the last `else`.
/// Each `else if` after the first `if` has one more doc first: the comments
/// before its `if`.
fn Ctx::if_plan(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  c : @ast.Node[@ast.Expression],
  t : @ast.Node[@ast.Expression],
  f : @ast.Node[@ast.Expression],
) -> (Array[Work], (Array[@pretty.Doc]) -> @pretty.Doc) raise PrintError {
  let parts = []
  // Per clause: the comments before `then` and those before `else`.
  let before_then : Array[Array[@ast.Node[String]]] = []
  let before_else : Array[Array[@ast.Node[String]]] = []
  let mut p = path
  let mut cond = c
  let mut then_ = t
  let mut else_ = f
  let mut more = true
  while more {
    // elm-format Parse/Expression.hs ifClause: the comments before `then`
    // follow the condition, and the comments before `else` follow the
    // branch. Take them before the condition and the branch take theirs.
    let (cr, tr, er) = (cond.range, then_.range, else_.range)
    parts.push(
      Leaf(() => {
        let then_at = self.token_before(tr.start)
        let cs = self.take(Trailing, cr)
        cs.append(self.take_if(Leading, tr, c => ends_before(c, then_at)))
        before_then.push(cs)
        let else_at = self.token_back_to(er.start, "else", 1)
        let es = self.take(Trailing, tr)
        es.append(self.take_if(Leading, er, c => ends_before(c, else_at)))
        before_else.push(es)
        @pretty.empty()
      }),
    )
    parts.push(Expr(p.child("clause", 0), level + 1, cond, AnyExpr))
    parts.push(Expr(p.child("then", 0), level + 1, then_, AnyExpr))
    match else_.value {
      IfBlock(c2, t2, f2) => {
        p = p.child("else", 0)
        check_level(p, level)
        let r = else_.range
        parts.push(Leaf(() => self.leading(r)))
        cond = c2
        then_ = t2
        else_ = f2
      }
      _ => {
        parts.push(Expr(p.child("else", 0), level + 1, else_, AnyExpr))
        more = false
      }
    }
  }
  (
    parts,
    docs => {
      // Per clause: an empty doc (the comments are in `before_then` and
      // `before_else`), the condition and the branch; before a nested
      // `if`, its leading comments; at the end, the last branch.
      let last = docs.length() - 1
      let mut d = @pretty.empty()
      let mut i = 0
      let mut k = 0
      while i + 1 < last {
        if i > 0 {
          d = d + @pretty.text(" ") + docs[i]
          i = i + 1
        }
        let (cond_doc, _) = commented([], docs[i + 1], before_then[k])
        let after_branch = before_else[k]
        d = d +
          @pretty.group(
            @pretty.text("if") +
            @pretty.tab(4, @pretty.line() + cond_doc) +
            @pretty.line() +
            @pretty.text("then"),
          ) +
          @pretty.tab(
            4,
            @pretty.hardline() +
            docs[i + 2] +
            (if after_branch.is_empty() {
              @pretty.empty()
            } else {
              @pretty.hardline() + comment_box(after_branch)
            }),
          ) +
          @pretty.hardline() +
          @pretty.hardline() +
          @pretty.text("else")
        i = i + 3
        k = k + 1
      }
      @pretty.align(d + @pretty.tab(4, @pretty.hardline() + docs[last]))
    },
  )
}

///|
/// The range of a case branch, as the syntax tree gives it: from the
/// pattern to the end of the body.
fn case_range(c : @ast.Case) -> @ast.Range {
  { start: c.pattern.range.start, end: c.expression.range.end, }
}
