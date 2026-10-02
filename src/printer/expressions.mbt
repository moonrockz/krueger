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
    Target =>
      !is_atom(e) ||
      e
      is (Integer(_)
      | Hex(_)
      | Floatable(_)
      | RecordAccessFunction(_)
      | PrefixOperator(_)) ||
      (e is FunctionOrValue(_, name) && is_upper(name))
  }
}

///|
fn Ctx::expr_doc(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  e : @ast.Node[@ast.Expression],
  at : ExprAt,
) -> @pretty.Doc raise PrintError {
  check_level(path, level)
  let d = self.expr_body(path, level, e)
  if needs_parens(e.value, at) {
    parens(d)
  } else {
    d
  }
}

///|
fn Ctx::expr_items(
  self : Ctx,
  path : @syntax.NodePath,
  field_name : String,
  level : Int,
  items : ArrayView[@ast.Node[@ast.Expression]],
) -> Array[@pretty.Doc] raise PrintError {
  let docs = []
  for i, x in items {
    docs.push(self.expr_doc(path.child(field_name, i), level + 1, x, AnyExpr))
  }
  docs
}

///|
fn Ctx::setters(
  self : Ctx,
  path : @syntax.NodePath,
  field_name : String,
  level : Int,
  setters : ArrayView[@ast.Node[@ast.RecordSetter]],
) -> Array[@pretty.Doc] raise PrintError {
  let docs = []
  for i, s in setters {
    let p = path.child(field_name, i)
    docs.push(
      field(
        self.lower_name(p.child("field", 0), s.value.field.value),
        "=",
        self.expr_doc(
          p.child("expression", 0),
          level + 1,
          s.value.expression,
          AnyExpr,
        ),
      ),
    )
  }
  docs
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
fn Ctx::expr_body(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  e : @ast.Node[@ast.Expression],
) -> @pretty.Doc raise PrintError {
  match e.value {
    UnitExpr => @pretty.text("()")
    Application(items) => {
      guard items.length() >= 2 else {
        raise PrintError(path~, problem=ShortApplication)
      }
      let head = self.expr_doc(
        path.child("application", 0),
        level + 1,
        items[0],
        Head,
      )
      let args = []
      for i in 1..<items.length() {
        args.push(
          self.expr_doc(
            path.child("application", i),
            level + 1,
            items[i],
            ExprArg,
          ),
        )
      }
      spaced(head, args)
    }
    OperatorApplication(_, _, _, _) => self.chain_doc(path, level, e)
    FunctionOrValue(module_, name) => self.qualified_value(path, module_, name)
    IfBlock(c, t, f) => self.if_doc(path, level, c, t, f)
    PrefixOperator(symbol) =>
      @pretty.text("(" + operator_symbol(path, symbol) + ")")
    Operator(symbol) => @pretty.text(operator_symbol(path, symbol))
    Integer(x) => number_doc(path, x, n => n.to_string())
    Hex(x) => number_doc(path, x, hex_text)
    Floatable(x) => {
      guard !x.is_nan() && !x.is_inf() else {
        raise PrintError(path~, problem=NonFiniteFloat(x))
      }
      if is_negative(x) {
        @pretty.text("-" + float_text(-x))
      } else {
        @pretty.text(float_text(x))
      }
    }
    Negation(x) =>
      @pretty.text("-") +
      self.expr_doc(path.child("negation", 0), level + 1, x, Negated)
    Literal(s) => @pretty.text(string_literal(s))
    CharLiteral(c) => @pretty.text(char_literal(c))
    TupledExpression(items) => {
      guard items.length() >= 2 else {
        raise PrintError(path~, problem=ShortTuple)
      }
      sequence("(", ")", self.expr_items(path, "tupled", level, items))
    }
    ParenthesizedExpression(x) =>
      parens(
        self.expr_doc(path.child("parenthesized", 0), level + 1, x, AnyExpr),
      )
    LetExpression(b) => {
      guard !b.declarations.is_empty() else {
        raise PrintError(path~, problem=EmptyLet)
      }
      let mut decls = @pretty.empty()
      for i, dn in b.declarations {
        let p = path.child("declarations", i)
        let doc = match dn.value {
          LetFunction(f) => self.function_doc(p, level + 1, f)
          LetDestructuring(pattern, value) =>
            self.pattern_doc(
              p.child("pattern", 0),
              level + 1,
              pattern,
              AnyPattern,
            ) +
            @pretty.text(" =") +
            @pretty.nest(
              4,
              @pretty.hardline() +
              self.expr_doc(p.child("expression", 0), level + 1, value, AnyExpr),
            )
        }
        decls = decls +
          (if i == 0 {
            @pretty.hardline()
          } else {
            @pretty.hardline() + @pretty.hardline()
          }) +
          doc
      }
      @pretty.text("let") +
      @pretty.nest(4, decls) +
      @pretty.hardline() +
      @pretty.text("in") +
      @pretty.hardline() +
      self.expr_doc(
        path.child("expression", 0),
        level + 1,
        b.expression,
        AnyExpr,
      )
    }
    CaseExpression(b) => {
      guard !b.cases.is_empty() else {
        raise PrintError(path~, problem=EmptyCase)
      }
      let head = @pretty.group(
        @pretty.text("case") +
        @pretty.nest(
          4,
          @pretty.line() +
          self.expr_doc(
            path.child("expression", 0),
            level + 1,
            b.expression,
            AnyExpr,
          ),
        ) +
        @pretty.line() +
        @pretty.text("of"),
      )
      let mut branches = @pretty.empty()
      for i, c in b.cases {
        let p = path.child("cases", i)
        let branch = self.pattern_doc(
            p.child("pattern", 0),
            level + 1,
            c.pattern,
            AnyPattern,
          ) +
          @pretty.text(" ->") +
          @pretty.nest(
            4,
            @pretty.hardline() +
            self.expr_doc(
              p.child("expression", 0),
              level + 1,
              c.expression,
              AnyExpr,
            ),
          )
        branches = branches +
          (if i == 0 {
            @pretty.hardline()
          } else {
            @pretty.hardline() + @pretty.hardline()
          }) +
          branch
      }
      head + @pretty.nest(4, branches)
    }
    LambdaExpression(l) => {
      guard !l.args.is_empty() else {
        raise PrintError(path~, problem=NoLambdaArguments)
      }
      let mut head = @pretty.text("\\")
      for i, a in l.args {
        if i > 0 {
          head = head + @pretty.text(" ")
        }
        head = head +
          self.pattern_doc(path.child("patterns", i), level + 1, a, PatternArg)
      }
      head +
      @pretty.text(" ->") +
      @pretty.group(
        @pretty.nest(
          4,
          @pretty.line() +
          self.expr_doc(
            path.child("expression", 0),
            level + 1,
            l.expression,
            AnyExpr,
          ),
        ),
      )
    }
    RecordExpr(setters) =>
      sequence("{", "}", self.setters(path, "record", level, setters))
    ListExpr(items) =>
      sequence("[", "]", self.expr_items(path, "list", level, items))
    RecordAccess(_, _) => {
      let names : Array[(@syntax.NodePath, String)] = []
      let mut node = e
      let mut p = path
      while node.value is RecordAccess(target, name) {
        names.push((p.child("name", 0), name.value))
        p = p.child("expression", 0)
        node = target
      }
      let mut d = self.expr_doc(p, level + 1, node, Target)
      for i = names.length() - 1; i >= 0; i = i - 1 {
        let (np, name) = names[i]
        d = d + @pretty.text(".") + self.lower_name(np, name)
      }
      d
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
      @pretty.text(s)
    }
    RecordUpdateExpression(name, setters) => {
      guard !setters.is_empty() else {
        raise PrintError(path~, problem=NoFields)
      }
      extension(
        self.lower_name(path.child("name", 0), name.value),
        self.setters(path, "updates", level, setters),
      )
    }
    GLSLExpression(s) => {
      guard !s.contains("|]") else {
        raise PrintError(path~, problem=InvalidGlsl)
      }
      @pretty.verbatim("[glsl|" + s + "|]")
    }
  }
}

///|
/// `if c then a else if d then b else e`, the `else if` chain flattened
/// without recursion.
fn Ctx::if_doc(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  c : @ast.Node[@ast.Expression],
  t : @ast.Node[@ast.Expression],
  f : @ast.Node[@ast.Expression],
) -> @pretty.Doc raise PrintError {
  let mut d = @pretty.empty()
  let mut p = path
  let mut cond = c
  let mut then_ = t
  let mut else_ = f
  let mut result : @pretty.Doc? = None
  while result is None {
    d = d +
      @pretty.group(
        @pretty.text("if") +
        @pretty.nest(
          4,
          @pretty.line() +
          self.expr_doc(p.child("clause", 0), level + 1, cond, AnyExpr),
        ) +
        @pretty.line() +
        @pretty.text("then"),
      ) +
      @pretty.nest(
        4,
        @pretty.hardline() +
        self.expr_doc(p.child("then", 0), level + 1, then_, AnyExpr),
      ) +
      @pretty.hardline() +
      @pretty.hardline() +
      @pretty.text("else")
    match else_.value {
      IfBlock(c2, t2, f2) => {
        p = p.child("else", 0)
        check_level(p, level)
        cond = c2
        then_ = t2
        else_ = f2
        d = d + @pretty.text(" ")
      }
      _ =>
        result = Some(
          d +
          @pretty.nest(
            4,
            @pretty.hardline() +
            self.expr_doc(p.child("else", 0), level + 1, else_, AnyExpr),
          ),
        )
    }
  }
  result.unwrap()
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
/// explicit stack.
fn Ctx::chain_doc(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  e : @ast.Node[@ast.Expression],
) -> @pretty.Doc raise PrintError {
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
  let mut first = @pretty.empty()
  let mut rest = @pretty.empty()
  let mut symbol = ""
  for i, step in steps {
    match step {
      Symbol(s) => symbol = s
      Operand(p, node, wrapped) => {
        let doc = if wrapped {
          parens(self.expr_doc(p, level + 1, node, AnyExpr))
        } else {
          self.expr_doc(
            p,
            level + 1,
            node,
            if i == last {
              AnyExpr
            } else {
              Operand
            },
          )
        }
        if i == 0 {
          first = doc
        } else {
          rest = rest + @pretty.line() + @pretty.text(symbol + " ") + doc
        }
      }
      Expand(_, _) => ()
    }
  }
  @pretty.group(first + @pretty.nest(4, rest))
}
