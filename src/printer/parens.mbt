///|
/// Where `normalize_expression` rewrites an expression: a place in the
/// printer's sense, or an operator application inside a chain. `spine` is
/// true when the application is on the right edge of the chain, so that
/// its right operand is the chain's last.
priv enum NormalizeAt {
  Place(ExprAt)
  InChain(Bool)
}

///|
priv enum NormalizeWork {
  Rewrite(@ast.Node[@ast.Expression], NormalizeAt)
  Rebuild(
    Int,
    (Array[@ast.Node[@ast.Expression]]) -> @ast.Node[@ast.Expression]
  )
}

///|
/// The place of an operand of the operator application `symbol`: an
/// application stays in the chain; the last operand of a chain is
/// `LastOperand`, or `Piped` after `<|`.
fn operand_at(
  operand : @ast.Node[@ast.Expression],
  symbol : String,
  last : Bool,
) -> NormalizeAt {
  match operand.value {
    OperatorApplication(_, _, _, _) => InChain(last)
    _ if !last => Place(Operand)
    _ if symbol == "<|" => Place(Piped)
    _ => Place(LastOperand)
  }
}

///|
/// `e` with elm-format's parentheses (see `normalize_file`). The printer
/// decides the same while it prints (`Ctx::run`). An explicit stack, as in
/// the printer, so deep expressions do not overflow the call stack.
fn normalize_expression(
  start : @ast.Node[@ast.Expression],
  at : ExprAt,
) -> @ast.Node[@ast.Expression] {
  let work : Array[NormalizeWork] = [Rewrite(start, Place(at))]
  let results : Array[@ast.Node[@ast.Expression]] = []
  fn plan(
    items : Array[(@ast.Node[@ast.Expression], NormalizeAt)],
    build : (Array[@ast.Node[@ast.Expression]]) -> @ast.Node[@ast.Expression],
  ) {
    work.push(Rebuild(items.length(), build))
    for i = items.length() - 1; i >= 0; i = i - 1 {
      work.push(Rewrite(items[i].0, items[i].1))
    }
  }

  let any = (x : @ast.Node[@ast.Expression]) => (x, Place(AnyExpr))
  let setters = (ss : ArrayView[@ast.Node[@ast.RecordSetter]]) => {
    ss.iter().map(s => any(s.value.expression)).collect()
  }
  let with_setters = (
    ss : ArrayView[@ast.Node[@ast.RecordSetter]],
    xs : ArrayView[@ast.Node[@ast.Expression]],
  ) => {
    let out : Array[@ast.Node[@ast.RecordSetter]] = []
    for i, s in ss {
      out.push({ range: s.range, value: { ..s.value, expression: xs[i], }, })
    }
    out[:]
  }
  while work.pop() is Some(item) {
    match item {
      Rewrite(e, InChain(spine)) => {
        guard e.value is OperatorApplication(symbol, dir, l, r) else {
          work.push(Rewrite(e, Place(Operand)))
          continue
        }
        plan(
          [(l, operand_at(l, symbol, false)), (r, operand_at(r, symbol, spine))],
          xs => {
            range: e.range,
            value: OperatorApplication(symbol, dir, xs[0], xs[1]),
          },
        )
      }
      Rewrite(e, Place(at)) => {
        if e.value is ParenthesizedExpression(x) && !parens_at(x.value, at) {
          // The parentheses go; the expression takes their place and range.
          plan([(x, Place(at))], xs => { range: e.range, value: xs[0].value, })
          continue
        }
        let node = (value : @ast.Expression) => {
          let n : @ast.Node[@ast.Expression] = { range: e.range, value, }
          if parens_at(value, at) {
            let wrapped : @ast.Node[@ast.Expression] = {
              range: e.range,
              value: ParenthesizedExpression(n),
            }
            wrapped
          } else {
            n
          }
        }
        match e.value {
          Application(items) => {
            let parts = [(items[0], Place(Head))]
            for i in 1..<items.length() {
              parts.push((items[i], Place(ExprArg)))
            }
            plan(parts, xs => node(Application(xs[:])))
          }
          OperatorApplication(_, _, _, _) =>
            plan([(e, InChain(true))], xs => node(xs[0].value))
          IfBlock(c, t, f) =>
            plan([any(c), any(t), any(f)], xs => {
              node(IfBlock(xs[0], xs[1], xs[2]))
            })
          Negation(x) =>
            plan([(x, Place(Negated))], xs => node(Negation(xs[0])))
          TupledExpression(items) =>
            plan(items.iter().map(any).collect(), xs => {
              node(TupledExpression(xs[:]))
            })
          ParenthesizedExpression(x) =>
            plan([any(x)], xs => node(ParenthesizedExpression(xs[0])))
          ListExpr(items) =>
            plan(items.iter().map(any).collect(), xs => node(ListExpr(xs[:])))
          RecordAccess(x, name) =>
            plan([(x, Place(Target))], xs => node(RecordAccess(xs[0], name)))
          RecordExpr(ss) =>
            plan(setters(ss), xs => node(RecordExpr(with_setters(ss, xs[:]))))
          RecordUpdateExpression(name, ss) =>
            plan(setters(ss), xs => {
              node(RecordUpdateExpression(name, with_setters(ss, xs[:])))
            })
          LambdaExpression(l) =>
            plan([any(l.expression)], xs => {
              node(
                LambdaExpression({
                  args: normalize_patterns(l.args, PatternArg),
                  expression: xs[0],
                }),
              )
            })
          CaseExpression(b) => {
            let parts = [any(b.expression)]
            for c in b.cases {
              parts.push(any(c.expression))
            }
            plan(parts, xs => {
              let cases : Array[@ast.Case] = []
              for i, c in b.cases {
                cases.push({
                  pattern: normalize_pattern(c.pattern, AnyPattern),
                  expression: xs[i + 1],
                })
              }
              node(CaseExpression({ expression: xs[0], cases: cases[:], }))
            })
          }
          LetExpression(b) => {
            let parts = []
            for d in b.declarations {
              match d.value {
                LetFunction(f) =>
                  parts.push(any(f.declaration.value.expression))
                LetDestructuring(_, x) => parts.push(any(x))
              }
            }
            parts.push(any(b.expression))
            plan(parts, xs => {
              let declarations : Array[@ast.Node[@ast.LetDeclaration]] = []
              for i, d in b.declarations {
                let value : @ast.LetDeclaration = match d.value {
                  LetFunction(f) => LetFunction(with_body(f, xs[i]))
                  LetDestructuring(p, _) =>
                    LetDestructuring(normalize_pattern(p, PatternArg), xs[i])
                }
                declarations.push({ range: d.range, value, })
              }
              node(
                LetExpression({
                  declarations: declarations[:],
                  expression: xs[xs.length() - 1],
                }),
              )
            })
          }
          value => plan([], _ => node(value))
        }
      }
      Rebuild(count, build) => {
        let start = results.length() - count
        let xs = []
        for i in start..<results.length() {
          xs.push(results[i])
        }
        results.truncate(start)
        results.push(build(xs))
      }
    }
  }
  results[0]
}

///|
/// `f` with its body `body` and its argument patterns normalized.
fn with_body(
  f : @ast.Function,
  body : @ast.Node[@ast.Expression],
) -> @ast.Function {
  let imp = f.declaration
  {
    ..f,
    declaration: {
      range: imp.range,
      value: {
        ..imp.value,
        arguments: normalize_patterns(imp.value.arguments, PatternArg),
        expression: body,
      },
    },
  }
}

///|
fn normalize_patterns(
  ps : ArrayView[@ast.Node[@ast.Pattern]],
  at : PatternAt,
) -> ArrayView[@ast.Node[@ast.Pattern]] {
  ps.iter().map(p => normalize_pattern(p, at)).collect()[:]
}

///|
/// `p` with the parentheses that the printer writes (see
/// `pattern_parens`). It recurses per nesting level, as the pattern
/// printer does; a `::` chain is a loop.
fn normalize_pattern(
  p : @ast.Node[@ast.Pattern],
  at : PatternAt,
) -> @ast.Node[@ast.Pattern] {
  let value : @ast.Pattern = match p.value {
    TuplePattern(xs) => TuplePattern(normalize_patterns(xs, AnyPattern))
    ListPattern(xs) => ListPattern(normalize_patterns(xs, AnyPattern))
    NamedPattern(r, args) =>
      NamedPattern(r, normalize_patterns(args, PatternArg))
    UnConsPattern(_, _) => {
      let nodes = []
      let mut node = p
      while node.value is UnConsPattern(left, right) {
        nodes.push((node.range, normalize_pattern(left, ConsLeft)))
        node = right
      }
      let mut tail = normalize_pattern(node, ConsTail)
      for i = nodes.length() - 1; i > 0; i = i - 1 {
        let (range, left) = nodes[i]
        tail = { range, value: UnConsPattern(left, tail), }
      }
      UnConsPattern(nodes[0].1, tail)
    }
    AsPattern(x, name) => AsPattern(normalize_pattern(x, AsInner), name)
    ParenthesizedPattern(x) =>
      ParenthesizedPattern(normalize_pattern(x, AnyPattern))
    other => other
  }
  let n : @ast.Node[@ast.Pattern] = { range: p.range, value, }
  if pattern_parens(value, at) {
    { range: p.range, value: ParenthesizedPattern(n), }
  } else {
    n
  }
}

///|
/// The declarations of `file` with elm-format's parentheses.
fn normalize_parens(file : @ast.File) -> @ast.File {
  let declarations : Array[@ast.Node[@ast.Declaration]] = []
  for d in file.declarations {
    let value : @ast.Declaration = match d.value {
      FunctionDeclaration(f) =>
        FunctionDeclaration(
          with_body(
            f,
            normalize_expression(f.declaration.value.expression, AnyExpr),
          ),
        )
      Destructuring(p, x) =>
        Destructuring(
          normalize_pattern(p, PatternArg),
          normalize_expression(x, AnyExpr),
        )
      other => other
    }
    declarations.push({ range: d.range, value, })
  }
  { ..file, declarations: declarations[:], }
}
