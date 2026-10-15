///|
let r0 : @ast.Range = {
  start: { row: 0, column: 0, },
  end: { row: 0, column: 0, },
}

///|
fn[T] n(value : T) -> @ast.Node[T] {
  { range: r0, value, }
}

///|
/// A file with one declaration `x <arg> = <body>` and one signature.
fn deep_file(
  arg : @ast.Node[@ast.Pattern],
  t : @ast.Node[@ast.TypeAnnotation],
  body : @ast.Node[@ast.Expression],
) -> @ast.File {
  {
    module_definition: n(
      NormalModule({ module_name: n(["A"][:]), exposing_list: n(All(r0)), }),
    ),
    imports: [][:],
    declarations: [
      n(
        @ast.Declaration::FunctionDeclaration({
          documentation: None,
          signature: Some(n({ name: n("x"), type_annotation: t, })),
          declaration: n({
            name: n("x"),
            arguments: [arg][:],
            expression: body,
          }),
        }),
      ),
    ][:],
    comments: [][:],
  }
}

///|
test "2000 nested parentheses encode on every target" {
  let mut e : @ast.Node[@ast.Expression] = n(FunctionOrValue([][:], "x"))
  for _ in 0..<2000 {
    e = n(ParenthesizedExpression(e))
  }
  let text = @ast.encode_expression(e.value).stringify()
  @expect.expect_all(s => {
    s
    .expect(
      text.has_prefix(
        "{\"type\":\"parenthesized\",\"parenthesized\":{\"range\":[0,0,0,0],\"value\":{\"type\":\"parenthesized\"",
      ),
    )
    .to_be_true()
    s
    .expect(
      text.has_suffix(
        "{\"type\":\"functionOrValue\",\"functionOrValue\":{\"moduleName\":[],\"name\":\"x\"}}" +
        "}}".repeat(2000),
      ),
    )
    .to_be_true()
  })
}

///|
test "a 2000-element cons pattern and a 2000-level type encode on every target" {
  let mut p : @ast.Node[@ast.Pattern] = n(ListPattern([][:]))
  let mut t : @ast.Node[@ast.TypeAnnotation] = n(GenericType("a"))
  for _ in 0..<2000 {
    p = n(UnConsPattern(n(IntPattern(9007199254740993L)), p))
    t = n(Typed(n(([][:], "List")), [t][:]))
  }
  let exact = @ast.encode_pattern_with(p.value, exact_ints=true).stringify()
  let nearest = @ast.encode_pattern(p.value).stringify()
  let typed = @ast.encode_type_annotation(t.value).stringify()
  @expect.expect_all(s => {
    s.expect(exact.contains("9007199254740993")).to_be_true()
    s.expect(exact.contains("9007199254740992")).to_be_false()
    s.expect(nearest.contains("9007199254740992")).to_be_true()
    s.expect(nearest.contains("9007199254740993")).to_be_false()
    s
    .expect(
      typed.has_prefix(
        "{\"type\":\"typed\",\"typed\":{\"moduleNameAndName\":{\"range\":[0,0,0,0],\"value\":{\"moduleName\":[],\"name\":\"List\"}},\"args\":[{\"range\":[0,0,0,0],\"value\":{\"type\":\"typed\"",
      ),
    )
    .to_be_true()
  })
}

///|
test "a file with 2000-level lets, cases, lambdas, records, patterns and types encodes on every target" {
  let y : @ast.Node[@ast.Expression] = n(FunctionOrValue([][:], "y"))
  let mut e : @ast.Node[@ast.Expression] = n(FunctionOrValue([][:], "x"))
  let mut p : @ast.Node[@ast.Pattern] = n(VarPattern("p"))
  let mut t : @ast.Node[@ast.TypeAnnotation] = n(GenericType("a"))
  for i in 0..<2000 {
    e = match i % 6 {
      0 =>
        n(
          LetExpression({
            declarations: [
              (
                n(
                  LetFunction({
                    documentation: None,
                    signature: None,
                    declaration: n({
                      name: n("g"),
                      arguments: [][:],
                      expression: e,
                    }),
                  }),
                ) : @ast.Node[@ast.LetDeclaration]),
            ][:],
            expression: y,
          }),
        )
      1 =>
        n(
          CaseExpression({
            expression: y,
            cases: [
              ({ pattern: n(VarPattern("z")), expression: e, } : @ast.Case),
            ][:],
          }),
        )
      2 =>
        n(
          LambdaExpression({
            args: [n(@ast.Pattern::VarPattern("z"))][:],
            expression: e,
          }),
        )
      3 =>
        n(
          RecordUpdateExpression(
            n("r"),
            [
              (
                n({ field: n("a"), expression: e, }) :
                @ast.Node[@ast.RecordSetter]),
            ][:],
          ),
        )
      4 => n(IfBlock(y, e, y))
      _ => n(Application([y, e][:]))
    }
    p = match i % 3 {
      0 => n(TuplePattern([p, n(VarPattern("q"))][:]))
      1 => n(AsPattern(n(ParenthesizedPattern(p)), n("w")))
      _ => n(NamedPattern({ module_name: [][:], name: "Just", }, [p][:]))
    }
    t = match i % 3 {
      0 => n(FunctionTypeAnnotation(t, n(GenericType("b"))))
      1 =>
        n(
          Record(
            [n(({ name: n("f"), type_annotation: t, } : @ast.RecordField))][:],
          ),
        )
      _ => n(Tupled([t, n(Unit)][:]))
    }
  }
  let file = deep_file(p, t, e)
  let json = @ast.encode_file(file)
  let text = json.stringify()
  @expect.expect_all(s => {
    s.expect(text.has_prefix("{\"moduleDefinition\":")).to_be_true()
    s.expect(text.contains("\"name\":\"Just\"")).to_be_true()
    s.expect(text.has_suffix("\"comments\":[]}")).to_be_true()
    // The same text through the recursive-free path twice: deterministic.
    s.expect(@ast.encode_file(file).stringify() == text).to_be_true()
  })
}
