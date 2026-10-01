///|
fn parse(text : String) -> @parser.ParseResult raise {
  let source = @scanner.SourceText::{ module_name: Some("Main"), text, }
  match @scanner.DefaultScanner::new().tokenize(source) {
    Ok(tokens) => @parser.parse_tokens(tokens)
    Err(_) => fail("expected tokenization success")
  }
}

///|
fn codes(result : @parser.ParseResult) -> Array[String] {
  result.diagnostics.map(d => d.code)
}

///|
fn ast(result : @parser.ParseResult) -> @ast.File raise {
  guard result.ast is Some(file) else { fail("expected an AST") }
  file
}

///|
fn range(r1 : Int, c1 : Int, r2 : Int, c2 : Int) -> @ast.Range {
  { start: { row: r1, column: c1, }, end: { row: r2, column: c2, }, }
}

///|
fn custom_type(file : @ast.File, name : String) -> @ast.Type? {
  for decl in file.declarations {
    if decl.value is CustomTypeDeclaration(t) && t.name.value == name {
      return Some(t)
    }
  }
  None
}

///|
fn assert_node_span_matches_tokens(
  node_span : @scanner.Span,
  tokens : Array[@scanner.Token],
) -> Unit raise {
  // A precondition stays hard: the checks below index the tokens.
  @expect.expect(tokens.length() > 0).to_be_true()
  @expect.expect_all(s => {
    s.expect(node_span.start).to_equal(tokens[0].span.start)
    s.expect(node_span.end).to_equal(tokens[tokens.length() - 1].span.end)
  })
}

///|
test "module header becomes a normal module with its exposing list" {
  @expect.expect_all(s => {
    let file = ast(parse("module Main exposing (Msg(..), view, Id)"))
    s.expect(file.module_definition.range).to_equal(range(1, 1, 1, 41))
    guard file.module_definition.value is NormalModule(data) else {
      fail("expected a normal module")
    }
    s.expect(data.module_name.value).to_equal(["Main"])
    s.expect(data.exposing_list.range).to_equal(range(1, 13, 1, 41))
    guard data.exposing_list.value is Explicit(items) else {
      fail("expected an explicit exposing list")
    }
    s
    .expect(items.map(i => i.value))
    .to_equal([
      TypeExpose({ name: "Msg", open: Some(range(1, 26, 1, 30)), }),
      FunctionExpose("view"),
      TypeOrAliasExpose("Id"),
    ])
  })
}

///|
test "exposing everything records the range of the dots" {
  let file = ast(parse("module Main exposing (..)"))
  guard file.module_definition.value is NormalModule(data) else {
    fail("expected a normal module")
  }
  @expect.expect(data.exposing_list.value).to_equal(All(range(1, 23, 1, 25)))
}

///|
test "cst keeps the header and imports with token span fidelity" {
  @expect.expect_all(s => {
    let result = parse(
      "module Main exposing (add)\nimport Html exposing (text)\nadd x = x + 1",
    )
    guard result.cst is Some(cst) else { fail("expected a CST") }
    guard cst.header is Some(header) else { fail("expected a CST header") }
    s.expect(header.module_name).to_equal(Some("Main"))
    s.expect(header.exposing).to_equal(["add"])
    s.expect(header.tokens[0].kind).to_equal(@scanner.TokenKind::module_kw())
    assert_node_span_matches_tokens(header.span, header.tokens)
    @expect.expect(cst.imports.length()).to_equal(1)
    s.expect(cst.imports[0].module_name).to_equal("Html")
    s.expect(cst.imports[0].exposing).to_equal(Some(["text"]))
    assert_node_span_matches_tokens(cst.imports[0].span, cst.imports[0].tokens)
  })
}

///|
test "imports keep their alias and exposing list" {
  @expect.expect_all(s => {
    let file = ast(
      parse(
        "module Main exposing (main)\nimport Browser as B exposing (sandbox, Program(..))",
      ),
    )
    @expect.expect(file.imports.length()).to_equal(1)
    let import_ = file.imports[0]
    s.expect(import_.range).to_equal(range(2, 1, 2, 52))
    s.expect(import_.value.module_name.value).to_equal(["Browser"])
    s.expect(import_.value.module_alias.map(a => a.value)).to_equal(Some(["B"]))
    guard import_.value.exposing_list is Some({ value: Explicit(items), .. }) else {
      fail("expected an explicit exposing list")
    }
    s
    .expect(items.map(i => i.value))
    .to_equal([
      FunctionExpose("sandbox"),
      TypeExpose({ name: "Program", open: Some(range(2, 47, 2, 51)), }),
    ])
  })
}

///|
test "function declarations are parsed and kept in the cst" {
  @expect.expect_all(s => {
    let result = parse("module Main exposing (add)\nadd x = x + 1")
    s.expect(codes(result)).to_equal([])
    guard ast(result).declarations is [{ value: FunctionDeclaration(f), .. }] else {
      fail("expected one function declaration")
    }
    s.expect(f.declaration.value.name.value).to_equal("add")
    guard result.cst is Some(cst) else { fail("expected a CST") }
    guard cst.declarations is [Function(cst_f)] else {
      fail("expected one function in the CST")
    }
    s.expect(cst_f.name).to_equal("add")
    s.expect(cst_f.args).to_equal(["x"])
    assert_node_span_matches_tokens(cst_f.span, cst_f.tokens)
  })
}

///|
test "ast and cst keep every declaration" {
  @expect.expect_all(s => {
    let result = parse(
      "module Main exposing (add)\ntype alias User a = a\ntype Color = Red\nadd x = x + 1",
    )
    s.expect(codes(result)).to_equal([])
    s.expect(ast(result).declarations.length()).to_equal(3)
    guard result.cst is Some(cst) else { fail("expected a CST") }
    guard cst.declarations
      is [TypeAlias(type_alias), UnionType(union), Function(f)] else {
      fail("expected alias, union and function in the CST")
    }
    s.expect(type_alias.name).to_equal("User")
    s.expect(type_alias.type_params).to_equal(["a"])
    assert_node_span_matches_tokens(type_alias.span, type_alias.tokens)
    s.expect(union.name).to_equal("Color")
    assert_node_span_matches_tokens(union.span, union.tokens)
    s.expect(f.name).to_equal("add")
    let file = ast(result)
    s.expect(custom_type(file, "Color") is Some(_)).to_be_true()
  })
}

///|
test "custom type with one simple constructor becomes a custom type declaration" {
  @expect.expect_all(s => {
    let file = ast(
      parse("module Main exposing (Wrapper)\ntype Wrapper a = Wrapper a Int"),
    )
    guard custom_type(file, "Wrapper") is Some(t) else {
      fail("expected custom type Wrapper")
    }
    s.expect(t.generics.map(g => g.value)).to_equal(["a"])
    guard t.constructors is [c] else { fail("expected one constructor") }
    s.expect(c.range).to_equal(range(2, 18, 2, 31))
    s.expect(c.value.name.value).to_equal("Wrapper")
    s
    .expect(c.value.arguments.map(a => a.value))
    .to_equal([
      GenericType("a"),
      Typed({ range: range(2, 28, 2, 31), value: ([], "Int"), }, []),
    ])
  })
}

///|
test "custom type arguments can be any type" {
  @expect.expect_all(s => {
    let result = parse("module Main exposing (Box)\ntype Box = Box (Maybe Int)")
    s.expect(codes(result)).to_equal([])
    guard custom_type(ast(result), "Box") is Some(t) else {
      fail("expected custom type Box")
    }
    guard t.constructors is [{ value: { arguments: [arg], .. }, .. }] else {
      fail("expected one constructor with one argument")
    }
    // A parenthesized type is the inner type with a range over the parens.
    s.expect(arg.range).to_equal(range(2, 16, 2, 27))
    guard arg.value is Typed({ value: ([], "Maybe"), .. }, [_]) else {
      fail("expected Maybe Int")
    }
  })
}

///|
test "doc comment attaches to the following type and starts its range" {
  @expect.expect_all(s => {
    let file = ast(
      parse(
        "module Main exposing (Msg)\n\nimport Html\n\n{-| A message. -}\ntype Msg\n    = Inc",
      ),
    )
    @expect.expect(file.declarations.length()).to_equal(1)
    s.expect(file.declarations[0].range).to_equal(range(5, 1, 7, 10))
    guard custom_type(file, "Msg") is Some(t) else {
      fail("expected custom type Msg")
    }
    s
    .expect(t.documentation)
    .to_equal(Some({ range: range(5, 1, 5, 18), value: "{-| A message. -}", }))
    s.expect(file.comments.length()).to_equal(0)
  })
}

///|
test "first doc comment after the header documents the module" {
  @expect.expect_all(s => {
    let file = ast(
      parse(
        "module Main exposing (Msg)\n\n{-| About Main. -}\ntype Msg\n    = Inc",
      ),
    )
    guard custom_type(file, "Msg") is Some(t) else {
      fail("expected custom type Msg")
    }
    s.expect(t.documentation is None).to_be_true()
    s.expect(file.declarations[0].range).to_equal(range(4, 1, 5, 10))
    s
    .expect(file.comments)
    .to_equal([{ range: range(3, 1, 3, 19), value: "{-| About Main. -}", }])
  })
}

///|
test "missing module header gives no ast" {
  @expect.expect_all(s => {
    let result = parse("x = 1")
    s.expect(codes(result)).to_contain_element("KR-PARSE-006")
    s.expect(result.ast is None).to_be_true()
  })
}

///|
test "malformed module header gives no ast" {
  @expect.expect_all(s => {
    let result = parse("module Main (add)\nadd x = x + 1")
    s.expect(codes(result)).to_contain_element("KR-PARSE-001")
    s.expect(result.ast is None).to_be_true()
  })
}

///|
test "malformed exposing list in the header is reported" {
  let result = parse("module Main exposing add\nadd x = x")
  @expect.expect(codes(result)).to_contain_element("KR-PARSE-001")
}

///|
test "parser recovers from a malformed import" {
  @expect.expect_all(s => {
    let result = parse("module Main exposing (add)\nimport )\ntype Color = Red")
    s.expect(codes(result)).to_equal(["KR-PARSE-002"])
    s.expect(custom_type(ast(result), "Color") is Some(_)).to_be_true()
  })
}

///|
test "malformed import exposing list is reported" {
  @expect.expect_all(s => {
    let result = parse(
      "module Main exposing (add)\nimport Html exposing text\ntype Color = Red",
    )
    s.expect(codes(result)).to_contain_element("KR-PARSE-002")
    s.expect(custom_type(ast(result), "Color") is Some(_)).to_be_true()
  })
}

///|
test "malformed type declaration is reported" {
  let result = parse(
    "module Main exposing (add)\ntype alias = String\nadd x = x + 1",
  )
  @expect.expect(codes(result)).to_contain_element("KR-PARSE-003")
}

///|
test "malformed function declaration is reported" {
  @expect.expect_all(s => {
    let result = parse("module Main exposing (add)\nadd x x + 1\nok y = y")
    s.expect(codes(result)).to_equal(["KR-PARSE-004"])
    s.expect(ast(result).declarations.length()).to_equal(1)
  })
}

///|
test "parse module returns scanner diagnostics when tokenization fails" {
  @expect.expect_all(s => {
    let source = @scanner.SourceText::{
      module_name: Some("Main"),
      text: "{-| missing close",
    }
    let result = @parser.parse_module(source, @scanner.DefaultScanner::new())
    s.expect(result.ast is None).to_be_true()
    s.expect(result.cst is None).to_be_true()
    s.expect(codes(result)).to_contain_element("KR-SCAN-002")
  })
}

///|
test "empty stream has no ast and an empty cst span" {
  @expect.expect_all(s => {
    let result = @parser.parse_tokens(@scanner.TokenStream::{
      tokens: [],
      trivia: [],
    })
    s.expect(codes(result)).to_equal(["KR-PARSE-006"])
    s.expect(result.ast is None).to_be_true()
    guard result.cst is Some(cst) else { fail("expected a CST") }
    s.expect(cst.span is None).to_be_true()
  })
}

///|
fn body_of(file : @ast.File, name : String) -> @ast.Node[@ast.Expression] raise {
  for decl in file.declarations {
    if decl.value is FunctionDeclaration(f) &&
      f.declaration.value.name.value == name {
      return f.declaration.value.expression
    }
  }
  fail("no function \{name}")
}

///|
test "unicode escapes out of range become the replacement character" {
  @expect.expect_all(s => {
    // elm-syntax accepts code points above 10FFFF; elm make does not.
    let text = "module Main exposing (..)\n\n\na = '\\u{110000}'\n\n\nb = \"\\u{FFFFFFFFFFFF}\"\n\n\nc = '\\u{D800}'\n"
    s.expect(codes(parse(text))).to_equal(["KR-PARSE-004", "KR-PARSE-004"])
    let result = parse_with(text, @dialect.Dialect::elm_syntax_7_3_9())
    s.expect(codes(result)).to_equal([])
    let file = ast(result)
    s.expect(body_of(file, "a").value).to_equal(CharLiteral('\u{FFFD}'))
    s.expect(body_of(file, "b").value).to_equal(Literal("\u{FFFD}"))
    s.expect(body_of(file, "c").value).to_equal(CharLiteral('\u{FFFD}'))
  })
}

///|
fn nested(
  open : String,
  middle : String,
  close : String,
  depth : Int,
) -> String {
  let sb = StringBuilder()
  for _ in 0..<depth {
    sb.write_string(open)
  }
  sb.write_string(middle)
  for _ in 0..<depth {
    sb.write_string(close)
  }
  sb.to_string()
}

///|
test "deep nesting is a diagnostic, not a stack overflow" {
  @expect.expect_all(s => {
    let header = "module Main exposing (..)\n\n\n"
    let deep = 5000
    let expr = parse(header + "f = " + nested("(", "1", ")", deep) + "\n")
    s.expect(codes(expr)).to_equal(["KR-PARSE-004"])
    let unclosed = parse(header + "f = " + nested("(", "1", "", deep) + "\n")
    s.expect(codes(unclosed)).to_equal(["KR-PARSE-004"])
    let list = parse(header + "f = " + nested("[", "1", "]", deep) + "\n")
    s.expect(codes(list)).to_equal(["KR-PARSE-004"])
    let typ = parse(
      header + "f : " + nested("(", "Int", ")", deep) + "\nf = 1\n",
    )
    s.expect(codes(typ)).to_equal(["KR-PARSE-004"])
    let pat = parse(header + "f " + nested("(", "x", ")", deep) + " = 1\n")
    s.expect(codes(pat)).to_equal(["KR-PARSE-004"])
    let type_alias = parse(
      header + "type alias A = " + nested("(", "Int", ")", deep) + "\n",
    )
    s.expect(codes(type_alias)).to_equal(["KR-PARSE-003"])
  })
}

///|
test "moderate nesting still parses" {
  @expect.expect_all(s => {
    let header = "module Main exposing (..)\n\n\n"
    let depth = 100
    s
    .expect(codes(parse(header + "f = " + nested("(", "1", ")", depth) + "\n")))
    .to_equal([])
    s
    .expect(codes(parse(header + "f = " + nested("[", "1", "]", depth) + "\n")))
    .to_equal([])
    s
    .expect(
      codes(
        parse(header + "f : " + nested("(", "Int", ")", depth) + "\nf = 1\n"),
      ),
    )
    .to_equal([])
    s
    .expect(
      codes(parse(header + "f " + nested("(", "x", ")", depth) + " = 1\n")),
    )
    .to_equal([])
  })
}

///|
test "an operator at the branch column after the last branch applies to the case" {
  @expect.expect_all(s => {
    let result = parse(
      "module Main exposing (..)\n\n\nf x =\n    case x of\n        A -> 1\n        + 2\n",
    )
    s.expect(codes(result)).to_equal([])
    let body = body_of(ast(result), "f")
    s.expect(body.range).to_equal(range(5, 5, 7, 12))
    guard body.value is OperatorApplication("+", Left, left, _) else {
      fail("expected `+` applied to the case")
    }
    s.expect(left.range).to_equal(range(5, 5, 6, 15))
  })
}

///|
fn parse_with(text : String, dialect : @dialect.Dialect) -> @parser.ParseResult {
  let source = @scanner.SourceText::{ module_name: Some("Main"), text, }
  @parser.parse_module(source, @scanner.DefaultScanner::new(dialect~), dialect~)
}

///|
test "a dialect operator table decides precedence" {
  let d = @dialect.Dialect::elm_0_19_1()
  // `+` binds looser than `*` normally; swap them.
  let swapped = {
    ..d,
    operators: d.operators.map(o => {
      match o.symbol {
        "+" => { ..o, precedence: 7, }
        "*" => { ..o, precedence: 6, }
        _ => o
      }
    }),
  }
  let text = "module Main exposing (..)\n\n\nf = a + b * c\n"
  let normal = body_of(ast(parse_with(text, d)), "f")
  guard normal.value is OperatorApplication("+", _, _, _) else {
    fail("expected + on top")
  }
  let custom = body_of(ast(parse_with(text, swapped)), "f")
  guard custom.value is OperatorApplication("*", _, _, _) else {
    fail("expected * on top")
  }
}

///|
test "a lexed symbol without an operator entry is an unknown operator" {
  @expect.expect_all(s => {
    let d = @dialect.Dialect::elm_0_19_1()
    let custom = { ..d, operator_symbols: ["<=>"], }
    let result = parse_with(
      "module Main exposing (..)\n\n\nf = a <=> b\n", custom,
    )
    s.expect(codes(result)).to_equal(["KR-PARSE-004"])
    s
    .expect(result.diagnostics[0].message)
    .to_contain("unknown infix operator `<=>`")
  })
}

///|
test "a dialect operator entry makes a new operator usable" {
  let d = @dialect.Dialect::elm_0_19_1()
  let custom = {
    ..d,
    operator_symbols: ["<=>"],
    operators: [
      ..d.operators,
      { symbol: "<=>", precedence: 4, direction: Non, },
    ],
  }
  let result = parse_with(
    "module Main exposing (..)\n\n\nf = a <=> b\n", custom,
  )
  @expect.expect(codes(result)).to_equal([])
  guard body_of(ast(result), "f").value is OperatorApplication("<=>", Non, _, _) else {
    fail("expected <=>")
  }
}

///|
test "a doc comment on a failing declaration is not also reported as stray" {
  let result = parse(
    "module Main exposing (..)\n\n\n{-| The answer. -}\nf =\n    (\n\n\ng =\n    1\n",
  )
  @expect.expect(codes(result)).to_equal(["KR-PARSE-004"])
}

///|
fn chain(op : String, terms : Int, tail : String) -> String {
  let sb = StringBuilder()
  sb.write_string("module Main exposing (..)\n\n\nf =\n    1")
  for _ in 0..<terms {
    sb.write_string(op + "1")
  }
  sb.to_string() + tail + "\n"
}

///|
test "very long operator chains are a diagnostic, not a stack overflow" {
  for text in [chain(" + ", 5000, ""), chain(" :: ", 5000, " :: []")] {
    let result = parse(text)
    @expect.expect(result.diagnostics.map(d => d.title)).to_equal([
      "TOO MUCH NESTING",
    ])
  }
}

///|
test "long operator chains still parse and encode" {
  @expect.expect_all(s => {
    for text in [chain(" + ", 300, ""), chain(" :: ", 100, " :: []")] {
      let result = parse(text)
      s.expect(codes(result)).to_equal([])
      let json = @ast.encode_file(ast(result)).stringify()
      s.expect(json.length() > 0).to_equal(true)
    }
  })
}

///|
fn repeated(unit : String, n : Int) -> String {
  let sb = StringBuilder()
  for _ in 0..<n {
    sb.write_string(unit)
  }
  sb.to_string()
}

///|
test "deep trees of any shape are a diagnostic, not a stack overflow" {
  let header = "module Main exposing (..)\n\n\n"
  let chain = "1" + repeated(" + 1", 399)
  let inputs = [
    // Left chains nested as first operands.
    header + "f =\n    ((" + chain + ") + " + chain + ") + " + chain + "\n",
    // Record access.
    header + "f r =\n    r" + repeated(".a", 1000) + "\n",
    // Type arrows.
    header + "f : Int" + repeated(" -> Int", 1000) + "\nf =\n    1\n",
    // Cons patterns.
    header +
    "f x =\n    case x of\n        a" +
    repeated(" :: a", 1000) +
    " ->\n            1\n\n        _ ->\n            2\n",
    // Right-associative operators.
    header + "f =\n    \"a\"" + repeated(" ++ \"a\"", 1000) + "\n",
  ]
  for text in inputs {
    let result = parse(text)
    @expect.expect(result.diagnostics.map(d => d.title)).to_contain_element(
      "TOO MUCH NESTING",
    )
    if result.ast is Some(file) {
      ignore(@ast.encode_file(file).stringify())
    }
  }
}

///|
test "realistic long chains still parse" {
  let header = "module Main exposing (..)\n\n\n"
  for
    text in [
      header + "f =\n    \"a\"" + repeated(" ++ \"a\"", 300) + "\n",
      header + "f x =\n    x" + repeated(" |> g", 300) + "\n",
    ] {
    let result = parse(text)
    @expect.expect(codes(result)).to_equal([])
    ignore(@ast.encode_file(ast(result)).stringify())
  }
}

///|
test "encode_attributes_with exact Ints writes an argument's digits" {
  let text = "module M exposing (..)\n\n\nx =\n    1\n\n\n{-| d\n\n@size 9007199254740993\n\n-}\nf =\n    1\n"
  let groups = @parser.parse_module(
      { module_name: None, text, },
      @scanner.DefaultScanner::new(),
    ).attributes
  @expect.expect_all(s => {
    s
    .expect(
      @parser.encode_attributes_with(groups, exact_ints=true)
      .stringify()
      .contains("9007199254740993"),
    )
    .to_be_true()
    s
    .expect(
      @parser.encode_attributes(groups).stringify().contains("9007199254740992"),
    )
    .to_be_true()
  })
}
