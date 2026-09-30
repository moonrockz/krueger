///|
/// Deepest AST a declaration may have. Encoding an AST and printing its JSON
/// recurse once per level, so deeper trees overflow the stack on wasm.
const MAX_AST_DEPTH : Int = 400

///|
/// A node of any AST type, for the depth walk.
priv enum Item {
  E(@ast.Expression)
  P(@ast.Pattern)
  T(@ast.TypeAnnotation)
  F(@ast.Function)
}

///|
fn function_items(f : @ast.Function) -> Array[Item] {
  let items = []
  if f.signature is Some(s) {
    items.push(T(s.value.type_annotation.value))
  }
  for a in f.declaration.value.arguments {
    items.push(P(a.value))
  }
  items.push(E(f.declaration.value.expression.value))
  items
}

///|
/// The direct children of `item`.
fn children(item : Item) -> Array[Item] {
  match item {
    F(f) => function_items(f)
    E(e) =>
      match e {
        Application(xs) | TupledExpression(xs) | ListExpr(xs) =>
          xs.map(x => E(x.value))
        OperatorApplication(_, _, l, r) => [E(l.value), E(r.value)]
        IfBlock(a, b, c) => [E(a.value), E(b.value), E(c.value)]
        Negation(x) | ParenthesizedExpression(x) | RecordAccess(x, _) =>
          [E(x.value)]
        LetExpression(block) => {
          let items = []
          for d in block.declarations {
            match d.value {
              LetFunction(f) => items.push(F(f))
              LetDestructuring(p, x) => {
                items.push(P(p.value))
                items.push(E(x.value))
              }
            }
          }
          items.push(E(block.expression.value))
          items
        }
        CaseExpression(block) => {
          let items = [E(block.expression.value)]
          for c in block.cases {
            items.push(P(c.pattern.value))
            items.push(E(c.expression.value))
          }
          items
        }
        LambdaExpression(l) =>
          [..l.args.map(a => P(a.value)), E(l.expression.value)]
        RecordExpr(setters) | RecordUpdateExpression(_, setters) =>
          setters.map(s => E(s.value.expression.value))
        _ => []
      }
    P(p) =>
      match p {
        TuplePattern(xs) | ListPattern(xs) | NamedPattern(_, xs) =>
          xs.map(x => P(x.value))
        UnConsPattern(a, b) => [P(a.value), P(b.value)]
        AsPattern(x, _) => [P(x.value)]
        _ => []
      }
    T(t) =>
      match t {
        Typed(_, xs) | Tupled(xs) => xs.map(x => T(x.value))
        Record(fields) => fields.map(f => T(f.value.type_annotation.value))
        GenericRecord(_, fields) =>
          fields.value.map(f => T(f.value.type_annotation.value))
        FunctionTypeAnnotation(a, b) => [T(a.value), T(b.value)]
        _ => []
      }
  }
}

///|
/// The depth of `decl`'s AST, measured without recursion (an explicit stack),
/// so it works on trees of any depth.
fn declaration_depth(decl : @ast.Declaration) -> Int {
  let roots : Array[Item] = match decl {
    FunctionDeclaration(f) => [F(f)]
    AliasDeclaration(a) => [T(a.type_annotation.value)]
    CustomTypeDeclaration(t) => {
      let items = []
      for c in t.constructors {
        for a in c.value.arguments {
          items.push(T(a.value))
        }
      }
      items
    }
    PortDeclaration(s) => [T(s.type_annotation.value)]
    Destructuring(p, e) => [P(p.value), E(e.value)]
    InfixDeclaration(_) => []
  }
  let stack = roots.map(r => (r, 1))
  let mut deepest = 0
  while stack.pop() is Some((item, depth)) {
    if depth > deepest {
      deepest = depth
    }
    for child in children(item) {
      stack.push((child, depth + 1))
    }
  }
  deepest
}
