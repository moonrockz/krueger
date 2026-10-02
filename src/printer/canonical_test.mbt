///|
/// Where a node is, for the model (the same positions as the printer, but
/// decided from this file's own rules).
enum MAt {
  MAny
  MOperand
  MArg
  MHead
  MNegated
  MTarget
} derive(Eq)

///|
fn[A, B] each(xs : ArrayView[A], f : (A) -> B) -> ArrayView[B] {
  let out = []
  for x in xs {
    out.push(f(x))
  }
  out[:]
}

///|
fn model_negative(x : Double) -> Bool {
  x < 0.0 || (x == 0.0 && 1.0 / x < 0.0)
}

///|
fn opens_right(e : @ast.Expression) -> Bool {
  e
  is (LambdaExpression(_)
  | IfBlock(_, _, _)
  | CaseExpression(_)
  | LetExpression(_))
}

///|
fn compound(e : @ast.Expression) -> Bool {
  opens_right(e) ||
  e is (Application(_) | OperatorApplication(_, _, _, _) | Negation(_))
}

///|
fn model_parens(e : @ast.Expression, at : MAt) -> Bool {
  match at {
    MAny => false
    MOperand => opens_right(e)
    MArg => compound(e) && !(e is Negation(_))
    MHead => compound(e)
    MNegated => compound(e) || e is RecordAccessFunction(_)
    MTarget =>
      match e {
        FunctionOrValue(_, name) => starts_upper(name)
        RecordExpr(_)
        | RecordUpdateExpression(_, _)
        | ParenthesizedExpression(_)
        | RecordAccess(_, _) => false
        _ => true
      }
  }
}

///|
fn starts_upper(name : String) -> Bool {
  for c in name {
    return c >= 'A' && c <= 'Z'
  }
  false
}

///|
fn wrap(e : @ast.Expression, at : MAt) -> @ast.Node[@ast.Expression] {
  if model_parens(e, at) {
    n(ParenthesizedExpression(n(e)))
  } else {
    n(e)
  }
}

///|
fn table(symbol : String) -> (Int, @ast.InfixDirection) {
  let def = @dialect.Dialect::elm_0_19_1().operator(symbol).unwrap()
  (def.precedence, def.direction)
}

///|
fn model_joins(parent : String, child : String, left : Bool) -> Bool {
  let (pp, pd) = table(parent)
  let (cprec, cd) = table(child)
  if pp != cprec {
    cprec > pp
  } else if left {
    pd is Left && cd is Left
  } else {
    pd is Right && cd is Right
  }
}

///|
/// An operator application inside a chain. `last`: its right end is the end
/// of the whole chain.
fn chain_node(
  e : @ast.Node[@ast.Expression],
  last : Bool,
) -> @ast.Node[@ast.Expression] {
  guard e.value is OperatorApplication(symbol, dir, l, r) else {
    return ce(e, MAny)
  }
  let left = match l.value {
    OperatorApplication(s, _, _, _) =>
      if model_joins(symbol, s, true) {
        chain_node(l, false)
      } else {
        n(ParenthesizedExpression(chain_node(l, true)))
      }
    _ => ce(l, MOperand)
  }
  let right = match r.value {
    OperatorApplication(s, _, _, _) =>
      if model_joins(symbol, s, false) {
        chain_node(r, last)
      } else {
        n(ParenthesizedExpression(chain_node(r, true)))
      }
    _ => ce(r, if last { MAny } else { MOperand })
  }
  n(OperatorApplication(symbol, dir, left, right))
}

///|
fn cfun(f : @ast.Function) -> @ast.Function {
  let imp = f.declaration.value
  {
    ..f,
    declaration: n({
      ..imp,
      arguments: each(imp.arguments, a => cp(a, PArg)),
      expression: ce(imp.expression, MAny),
    }),
  }
}

///|
fn cset(s : @ast.Node[@ast.RecordSetter]) -> @ast.Node[@ast.RecordSetter] {
  n({ ..s.value, expression: ce(s.value.expression, MAny), })
}

///|
/// The canonical form of an expression at `at`.
fn ce(e : @ast.Node[@ast.Expression], at : MAt) -> @ast.Node[@ast.Expression] {
  let inner : @ast.Expression = match e.value {
    Integer(x) if x < 0L => Negation(n(Integer(-x)))
    Hex(x) if x < 0L => Negation(n(Hex(-x)))
    Floatable(x) if model_negative(x) => Negation(n(Floatable(-x)))
    Application(xs) => {
      let items = [ce(xs[0], MHead)]
      for i in 1..<xs.length() {
        items.push(ce(xs[i], MArg))
      }
      Application(items[:])
    }
    OperatorApplication(_, _, _, _) => chain_node(e, true).value
    IfBlock(c, t, f) => IfBlock(ce(c, MAny), ce(t, MAny), ce(f, MAny))
    Negation(x) => Negation(ce(x, MNegated))
    TupledExpression(xs) => TupledExpression(each(xs, x => ce(x, MAny)))
    ParenthesizedExpression(x) => ParenthesizedExpression(ce(x, MAny))
    LetExpression(b) =>
      LetExpression({
        declarations: each(b.declarations, d => {
          n(
            match d.value {
              LetFunction(f) => LetFunction(cfun(f))
              LetDestructuring(p, x) => cdestructuring(p, x)
            },
          )
        }),
        expression: ce(b.expression, MAny),
      })
    CaseExpression(b) =>
      CaseExpression({
        expression: ce(b.expression, MAny),
        cases: each(b.cases, c => {
          pattern: cp(c.pattern, PAny),
          expression: ce(c.expression, MAny),
        }),
      })
    LambdaExpression(l) =>
      LambdaExpression({
        args: each(l.args, a => cp(a, PArg)),
        expression: ce(l.expression, MAny),
      })
    RecordExpr(ss) => RecordExpr(each(ss, cset))
    ListExpr(xs) => ListExpr(each(xs, x => ce(x, MAny)))
    RecordAccess(x, name) => RecordAccess(ce(x, MTarget), name)
    RecordUpdateExpression(name, ss) =>
      RecordUpdateExpression(name, each(ss, cset))
    other => other
  }
  wrap(inner, at)
}

///|
enum PAt {
  PAny
  PConsLeft
  PAsInner
  PArg
}

///|
/// The canonical form of a pattern at `at`.
fn cp(p : @ast.Node[@ast.Pattern], at : PAt) -> @ast.Node[@ast.Pattern] {
  let inner : @ast.Pattern = match p.value {
    TuplePattern(xs) => TuplePattern(each(xs, x => cp(x, PAny)))
    ListPattern(xs) => ListPattern(each(xs, x => cp(x, PAny)))
    NamedPattern(r, args) => NamedPattern(r, each(args, x => cp(x, PArg)))
    UnConsPattern(l, r) => UnConsPattern(cp(l, PConsLeft), cp(r, PAny))
    AsPattern(x, name) => AsPattern(cp(x, PAsInner), name)
    ParenthesizedPattern(x) => ParenthesizedPattern(cp(x, PAny))
    other => other
  }
  let parens = match at {
    PAny => false
    PConsLeft | PAsInner => inner is (UnConsPattern(_, _) | AsPattern(_, _))
    PArg =>
      inner is (UnConsPattern(_, _) | AsPattern(_, _)) ||
      (inner is NamedPattern(_, args) && !args.is_empty())
  }
  if parens {
    n(ParenthesizedPattern(n(inner)))
  } else {
    n(inner)
  }
}

///|
/// The file that parsing the printer's output gives back for a built file.
fn canonical_file(f : @ast.File) -> @ast.File {
  {
    ..f,
    declarations: each(f.declarations, d => {
      n(
        match d.value {
          FunctionDeclaration(fun) => FunctionDeclaration(cfun(fun))
          Destructuring(p, e) => Destructuring(cp(p, PArg), ce(e, MAny))
          other => other
        },
      )
    }),
  }
}

///|
/// A let destructuring. Its pattern is a term (`(Wrap w) = x`). A variable
/// pattern has no source form of its own: `y = x` reads as a function with
/// no arguments.
fn cdestructuring(
  p : @ast.Node[@ast.Pattern],
  x : @ast.Node[@ast.Expression],
) -> @ast.LetDeclaration {
  match p.value {
    VarPattern(name) =>
      LetFunction({
        documentation: None,
        signature: None,
        declaration: n({
          name: n(name),
          arguments: [][:],
          expression: ce(x, MAny),
        }),
      })
    _ => LetDestructuring(cp(p, PArg), ce(x, MAny))
  }
}
