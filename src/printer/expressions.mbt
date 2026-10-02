///|
/// Where an expression is: this decides its parentheses (see the table in
/// the plan, and spec section 4.3).
priv enum ExprAt {
  AnyExpr
  Operand
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
    AnyExpr => false
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
        let (items, combine) = self.expr_plan(path, level, e)
        if needs_parens(e.value, at) {
          push_plan(items, docs => parens(combine(docs)))
        } else {
          push_plan(items, combine)
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
/// The items of `label = value` for each setter, two per setter.
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
    items.push(
      Leaf(() => self.lower_name(p.child("field", 0), s.value.field.value)),
    )
    items.push(
      Expr(p.child("expression", 0), level + 1, s.value.expression, AnyExpr),
    )
  }
  items
}

///|
/// The setter docs from `docs[from]` on, two per setter.
fn setter_docs(docs : Array[@pretty.Doc], from : Int) -> Array[@pretty.Doc] {
  let fields = []
  for i = from; i + 1 < docs.length(); i = i + 2 {
    fields.push(field(docs[i], "=", docs[i + 1]))
  }
  fields
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
    UnitExpr => done(@pretty.text("()"))
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
      (parts, docs => spaced(docs[0], docs[1:].to_owned()))
    }
    OperatorApplication(_, _, _, _) => self.chain_plan(path, level, e)
    FunctionOrValue(module_, name) =>
      done(self.qualified_value(path, module_, name))
    IfBlock(c, t, f) => if_plan(path, level, c, t, f)
    PrefixOperator(symbol) =>
      done(@pretty.text("(" + operator_symbol(path, symbol) + ")"))
    Operator(symbol) => done(@pretty.text(operator_symbol(path, symbol)))
    Integer(x) => done(number_doc(path, x, n => n.to_string()))
    Hex(x) => done(number_doc(path, x, hex_text))
    Floatable(x) => {
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
    Literal(s) => done(@pretty.text(string_literal(s)))
    CharLiteral(c) => done(@pretty.text(char_literal(c)))
    TupledExpression(items) => {
      guard items.length() >= 2 else {
        raise PrintError(path~, problem=ShortTuple)
      }
      (
        expr_items(path, "tupled", level, items),
        docs => sequence("(", ")", docs),
      )
    }
    ParenthesizedExpression(x) =>
      (
        [Expr(path.child("parenthesized", 0), level + 1, x, AnyExpr)],
        docs => parens(docs[0]),
      )
    LetExpression(b) => {
      guard !b.declarations.is_empty() else {
        raise PrintError(path~, problem=EmptyLet)
      }
      let parts = []
      for i, dn in b.declarations {
        let p = path.child("declarations", i)
        match dn.value {
          LetFunction(f) => parts.push(self.function_plan(p, level + 1, f))
          LetDestructuring(pattern, value) =>
            parts.push(
              Plan(
                [
                  Leaf(() => {
                    // Elm reads a destructuring pattern as a term: `(Wrap w) =`.
                    self.pattern_doc(
                      p.child("pattern", 0),
                      level + 1,
                      pattern,
                      PatternArg,
                    )
                  }),
                  Expr(p.child("expression", 0), level + 1, value, AnyExpr),
                ],
                docs => {
                  docs[0] +
                  @pretty.text(" =") +
                  @pretty.nest(4, @pretty.hardline() + docs[1])
                },
              ),
            )
        }
      }
      parts.push(
        Expr(path.child("expression", 0), level + 1, b.expression, AnyExpr),
      )
      (
        parts,
        docs => {
          let last = docs.length() - 1
          let mut decls = @pretty.empty()
          for i in 0..<last {
            decls = decls +
              (if i == 0 {
                @pretty.hardline()
              } else {
                @pretty.hardline() + @pretty.hardline()
              }) +
              docs[i]
          }
          @pretty.align(
            @pretty.text("let") +
            @pretty.tab(4, decls) +
            @pretty.hardline() +
            @pretty.text("in") +
            @pretty.hardline() +
            docs[last],
          )
        },
      )
    }
    CaseExpression(b) => {
      guard !b.cases.is_empty() else {
        raise PrintError(path~, problem=EmptyCase)
      }
      let parts = [
        Expr(path.child("expression", 0), level + 1, b.expression, AnyExpr),
      ]
      for i, c in b.cases {
        let p = path.child("cases", i)
        parts.push(
          Leaf(() => {
            self.pattern_doc(
              p.child("pattern", 0),
              level + 1,
              c.pattern,
              AnyPattern,
            )
          }),
        )
        parts.push(
          Expr(p.child("expression", 0), level + 1, c.expression, AnyExpr),
        )
      }
      (
        parts,
        docs => {
          let head = @pretty.group(
            @pretty.text("case") +
            @pretty.tab(4, @pretty.line() + docs[0]) +
            @pretty.line() +
            @pretty.text("of"),
          )
          let mut branches = @pretty.empty()
          for i = 1; i + 1 < docs.length(); i = i + 2 {
            branches = branches +
              (if i == 1 {
                @pretty.hardline()
              } else {
                @pretty.hardline() + @pretty.hardline()
              }) +
              docs[i] +
              @pretty.text(" ->") +
              @pretty.nest(4, @pretty.hardline() + docs[i + 1])
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
      for i, a in l.args {
        let p = path.child("patterns", i)
        parts.push(Leaf(() => self.pattern_doc(p, level + 1, a, PatternArg)))
      }
      parts.push(
        Expr(path.child("expression", 0), level + 1, l.expression, AnyExpr),
      )
      (
        parts,
        docs => {
          let last = docs.length() - 1
          let mut head = @pretty.text("\\")
          for i in 0..<last {
            if i > 0 {
              head = head + @pretty.text(" ")
            }
            head = head + docs[i]
          }
          // The body indents to the next tab stop right of the `\\`.
          @pretty.align(
            head +
            @pretty.text(" ->") +
            @pretty.group(@pretty.tab(4, @pretty.line() + docs[last])),
          )
        },
      )
    }
    RecordExpr(setters) =>
      (
        self.setter_items(path, "record", level, setters),
        docs => sequence("{", "}", setter_docs(docs, 0)),
      )
    ListExpr(items) =>
      (expr_items(path, "list", level, items), docs => sequence("[", "]", docs))
    RecordAccess(_, _) => {
      let names : Array[(@syntax.NodePath, String)] = []
      let mut node = e
      let mut p = path
      while node.value is RecordAccess(target, name) {
        names.push((p.child("name", 0), name.value))
        p = p.child("expression", 0)
        node = target
      }
      let parts = [Expr(p, level + 1, node, Target)]
      for i = names.length() - 1; i >= 0; i = i - 1 {
        let (np, name) = names[i]
        parts.push(Leaf(() => self.lower_name(np, name)))
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
        Leaf(() => self.lower_name(path.child("name", 0), name.value)),
      ]
      parts.append(self.setter_items(path, "updates", level, setters))
      (parts, docs => extension(docs[0], setter_docs(docs, 1)))
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
/// An `Expr` item for each item, at `path.child(field_name, i)`.
fn expr_items(
  path : @syntax.NodePath,
  field_name : String,
  level : Int,
  items : ArrayView[@ast.Node[@ast.Expression]],
) -> Array[Work] {
  let parts = []
  for i, x in items {
    parts.push(Expr(path.child(field_name, i), level + 1, x, AnyExpr))
  }
  parts
}

///|
/// `if c then a else if d then b else e`, the `else if` chain flattened
/// without recursion: a clause and a branch per `if`, then the last `else`.
fn if_plan(
  path : @syntax.NodePath,
  level : Int,
  c : @ast.Node[@ast.Expression],
  t : @ast.Node[@ast.Expression],
  f : @ast.Node[@ast.Expression],
) -> (Array[Work], (Array[@pretty.Doc]) -> @pretty.Doc) raise PrintError {
  let parts = []
  let mut p = path
  let mut cond = c
  let mut then_ = t
  let mut else_ = f
  let mut more = true
  while more {
    parts.push(Expr(p.child("clause", 0), level + 1, cond, AnyExpr))
    parts.push(Expr(p.child("then", 0), level + 1, then_, AnyExpr))
    match else_.value {
      IfBlock(c2, t2, f2) => {
        p = p.child("else", 0)
        check_level(p, level)
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
      let last = docs.length() - 1
      let mut d = @pretty.empty()
      for i = 0; i + 1 < last; i = i + 2 {
        if i > 0 {
          d = d + @pretty.text(" ")
        }
        d = d +
          @pretty.group(
            @pretty.text("if") +
            @pretty.tab(4, @pretty.line() + docs[i]) +
            @pretty.line() +
            @pretty.text("then"),
          ) +
          @pretty.tab(4, @pretty.hardline() + docs[i + 1]) +
          @pretty.hardline() +
          @pretty.hardline() +
          @pretty.text("else")
      }
      @pretty.align(d + @pretty.tab(4, @pretty.hardline() + docs[last]))
    },
  )
}

///|
/// A step of an operator chain, in source order.
priv enum ChainStep {
  Expand(@syntax.NodePath, @ast.Node[@ast.Expression]) // flatten this operator application
  Operand(@syntax.NodePath, @ast.Node[@ast.Expression], Bool) // true: an operator application in parentheses
  Symbol(String)
}

///|
/// Whether a child operator application can stay in its parent's chain
/// without parentheses and parse back to the same tree.
fn joins(
  parent : @dialect.OperatorDef,
  child : @dialect.OperatorDef,
  on_left : Bool,
) -> Bool {
  if child.precedence != parent.precedence {
    child.precedence > parent.precedence
  } else if on_left {
    parent.direction is Left && child.direction is Left
  } else {
    parent.direction is Right && child.direction is Right
  }
}

///|
fn Ctx::chain_step(
  self : Ctx,
  parent : @dialect.OperatorDef,
  path : @syntax.NodePath,
  child : @ast.Node[@ast.Expression],
  on_left : Bool,
) -> ChainStep raise PrintError {
  match child.value {
    OperatorApplication(symbol, _, _, _) =>
      if joins(parent, self.operator_def(path, symbol), on_left) {
        Expand(path, child)
      } else {
        Operand(path, child, true)
      }
    _ => Operand(path, child, false)
  }
}

///|
/// `a + b * c`: the first operand, then each operator and its operand on a
/// new line indented by 4 when the chain breaks. elm-format treats the
/// whole binary-operator expression as one chain. Flattened with an
/// explicit stack; every operator is checked before any operand.
fn Ctx::chain_plan(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  e : @ast.Node[@ast.Expression],
) -> (Array[Work], (Array[@pretty.Doc]) -> @pretty.Doc) raise PrintError {
  let steps : Array[ChainStep] = []
  let stack : Array[ChainStep] = [Expand(path, e)]
  while stack.pop() is Some(step) {
    match step {
      Expand(p, node) =>
        if node.value is OperatorApplication(symbol, _, left, right) {
          let def = self.operator_def(p, symbol)
          stack.push(self.chain_step(def, p.child("right", 0), right, false))
          stack.push(Symbol(symbol))
          stack.push(self.chain_step(def, p.child("left", 0), left, true))
        }
      _ => steps.push(step)
    }
  }
  let last = steps.length() - 1
  let parts = []
  let symbols = []
  for i, step in steps {
    match step {
      Symbol(s) => symbols.push(s)
      Operand(p, node, wrapped) =>
        parts.push(
          if wrapped {
            Plan([Expr(p, level + 1, node, AnyExpr)], docs => parens(docs[0]))
          } else {
            Expr(p, level + 1, node, if i == last { AnyExpr } else { Operand })
          },
        )
      Expand(_, _) => ()
    }
  }
  (parts, docs => @pretty.group(binary_doc(docs, symbols)))
}

///|
/// The operands and operators of a chain in the elm-format 0.8.7 layout
/// (its `formatBinary`), without the group. Each operator other than `<|`
/// starts a line at the next tab stop. A `<|` ends its line (`f x <|`), or
/// goes on its own line when operators come before it in its segment; the
/// rest of the chain is a new chain at the next tab stop:
/// `f x <|\n    g y <|\n        h z`. Built from the last segment back,
/// without recursion.
fn binary_doc(
  docs : Array[@pretty.Doc],
  symbols : Array[String],
) -> @pretty.Doc {
  // A segment starts at the first operand and after each `<|`.
  let starts = [0]
  for i, s in symbols {
    if s == "<|" {
      starts.push(i + 1)
    }
  }
  let mut result = @pretty.empty()
  for k = starts.length() - 1; k >= 0; k = k - 1 {
    let start = starts[k]
    let end = if k + 1 < starts.length() {
      starts[k + 1] - 1
    } else {
      symbols.length()
    }
    let mut rest = @pretty.empty()
    for i in start..<end {
      rest = rest +
        @pretty.line() +
        @pretty.text(symbols[i] + " ") +
        docs[i + 1]
    }
    let segment = docs[start] + @pretty.tab(4, rest)
    result = if k + 1 == starts.length() {
      segment
    } else {
      let pipe = if end > start {
        @pretty.line() + @pretty.text("<|")
      } else {
        @pretty.text(" <|")
      }
      segment + pipe + @pretty.tab(4, @pretty.line() + result)
    }
  }
  result
}
