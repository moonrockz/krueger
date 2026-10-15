///|
let d0 : @ast.Range = {
  start: { row: 0, column: 0, },
  end: { row: 0, column: 0, },
}

///|
fn[T] dn(value : T) -> @ast.Node[T] {
  { range: d0, value, }
}

///|
/// Decodes the JSON value and compares the result through its JSON text
/// (`derive(Eq)` recurses; the texts do not). The value is decoded as it
/// is, not parsed from text: `@json.parse` recurses per level and stops at
/// its own `max_nesting_depth` (1024 by default).
fn[T] round_trips(
  json : Json,
  decode : (Json) -> T raise @ast.DecodeError,
  encode : (T) -> Json,
) -> Bool raise {
  let back = decode(json)
  encode(back).stringify() == json.stringify()
}

///|
test "2000 nested parentheses decode on every target" {
  let mut e : @ast.Node[@ast.Expression] = dn(FunctionOrValue([][:], "x"))
  for _ in 0..<2000 {
    e = dn(ParenthesizedExpression(e))
  }
  @expect.expect(
    round_trips(
      @ast.encode_expression(e.value),
      @ast.decode_expression,
      @ast.encode_expression,
    ),
  ).to_be_true()
}

///|
test "a 2000-element cons pattern and a 2000-level type decode on every target" {
  let mut p : @ast.Node[@ast.Pattern] = dn(ListPattern([][:]))
  let mut t : @ast.Node[@ast.TypeAnnotation] = dn(GenericType("a"))
  for _ in 0..<2000 {
    p = dn(UnConsPattern(dn(IntPattern(9007199254740993L)), p))
    t = dn(
      FunctionTypeAnnotation(dn(Typed(dn(([][:], "List")), [t][:])), dn(Unit)),
    )
  }
  @expect.expect_all(s => {
    s
    .expect(
      round_trips(
        @ast.encode_pattern_with(p.value, exact_ints=true),
        @ast.decode_pattern,
        v => @ast.encode_pattern_with(v, exact_ints=true),
      ),
    )
    .to_be_true()
    s
    .expect(
      round_trips(
        @ast.encode_type_annotation(t.value),
        @ast.decode_type_annotation,
        @ast.encode_type_annotation,
      ),
    )
    .to_be_true()
  })
}

///|
test "a file with 2000-level lets, cases, lambdas, records and a parsed chain decodes on every target" {
  let y : @ast.Node[@ast.Expression] = dn(FunctionOrValue([][:], "y"))
  let mut e : @ast.Node[@ast.Expression] = dn(FunctionOrValue([][:], "x"))
  for i in 0..<2000 {
    e = match i % 6 {
      0 =>
        dn(
          LetExpression({
            declarations: [
              (
                dn(
                  LetFunction({
                    documentation: None,
                    signature: Some(
                      dn({
                        name: dn("g"),
                        type_annotation: dn(GenericType("a")),
                      }),
                    ),
                    declaration: dn({
                      name: dn("g"),
                      arguments: [dn(@ast.Pattern::VarPattern("z"))][:],
                      expression: e,
                    }),
                  }),
                ) : @ast.Node[@ast.LetDeclaration]),
            ][:],
            expression: y,
          }),
        )
      1 =>
        dn(
          CaseExpression({
            expression: y,
            cases: [
              (
                { pattern: dn(@ast.Pattern::VarPattern("z")), expression: e, } :
                @ast.Case),
            ][:],
          }),
        )
      2 =>
        dn(
          LambdaExpression({
            args: [dn(@ast.Pattern::VarPattern("z"))][:],
            expression: e,
          }),
        )
      3 =>
        dn(
          RecordUpdateExpression(
            dn("r"),
            [
              (
                dn({ field: dn("a"), expression: e, }) :
                @ast.Node[@ast.RecordSetter]),
            ][:],
          ),
        )
      4 => dn(RecordAccess(e, dn("f")))
      _ => dn(Application([y, e][:]))
    }
  }
  let file : @ast.File = {
    module_definition: dn(
      NormalModule({ module_name: dn(["A"][:]), exposing_list: dn(All(d0)), }),
    ),
    imports: [][:],
    declarations: [
      dn(
        @ast.Declaration::FunctionDeclaration({
          documentation: None,
          signature: None,
          declaration: dn({ name: dn("x"), arguments: [][:], expression: e, }),
        }),
      ),
    ][:],
    comments: [][:],
  }
  let source = @scanner.SourceText::new(
    "module M exposing (..)\n\n\nf =\n    1" + " + 1".repeat(2000) + "\n",
  )
  guard @parser.parse_module(source, @scanner.DefaultScanner::new()).ast
    is Some(parsed) else {
    fail("no AST")
  }
  @expect.expect_all(s => {
    s
    .expect(
      round_trips(@ast.encode_file(file), @ast.decode_file, @ast.encode_file),
    )
    .to_be_true()
    s
    .expect(
      round_trips(@ast.encode_file(parsed), @ast.decode_file, @ast.encode_file),
    )
    .to_be_true()
  })
}

///|
test "an error at the bottom of a 2000-level tree reports its full path on every target" {
  let mut e : @ast.Node[@ast.Expression] = dn(FunctionOrValue([][:], "x"))
  for _ in 0..<2000 {
    e = dn(ParenthesizedExpression(e))
  }
  let json = @ast.encode_expression(e.value)
  // Replace the leaf: walk down 2000 `parenthesized.value` objects.
  let mut cur = json
  for _ in 0..<1999 {
    guard cur is { "parenthesized": { "value": next, .. }, .. } else {
      fail("shape")
    }
    cur = next
  }
  guard cur is { "parenthesized": Object(leaf_node), .. } else { fail("shape") }
  leaf_node["value"] = { "type": "bogus", "bogus": 1 }
  let message = try {
    ignore(@ast.decode_expression(json))
    "no error"
  } catch {
    e => e.to_string()
  }
  @expect.expect_all(s => {
    s
    .expect(message.has_prefix("$.parenthesized.value.parenthesized.value."))
    .to_be_true()
    s
    .expect(
      message.has_suffix(
        ".parenthesized.value.type: No decoder for type: bogus",
      ),
    )
    .to_be_true()
    s
    .expect(message.length())
    .to_equal(
      "$".length() +
      2000 * ".parenthesized.value".length() +
      ".type: No decoder for type: bogus".length(),
    )
  })
}
