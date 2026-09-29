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
fn ast(result : @parser.ParseResult) -> @syntax.File raise {
  guard result.ast is Some(file) else { fail("expected an AST") }
  file
}

///|
fn range(r1 : Int, c1 : Int, r2 : Int, c2 : Int) -> @syntax.Range {
  { start: { row: r1, column: c1, }, end: { row: r2, column: c2, }, }
}

///|
fn custom_type(file : @syntax.File, name : String) -> @syntax.Type? {
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
  @expect.expect(tokens.length() > 0).to_be_true()
  @expect.expect(node_span.start).to_equal(tokens[0].span.start)
  @expect.expect(node_span.end).to_equal(tokens[tokens.length() - 1].span.end)
}

///|
test "module header becomes a normal module with its exposing list" {
  let file = ast(parse("module Main exposing (Msg(..), view, Id)"))
  @expect.expect(file.module_definition.range).to_equal(range(1, 1, 1, 41))
  guard file.module_definition.value is NormalModule(data) else {
    fail("expected a normal module")
  }
  @expect.expect(data.module_name.value).to_equal(["Main"])
  @expect.expect(data.exposing_list.range).to_equal(range(1, 13, 1, 41))
  guard data.exposing_list.value is Explicit(items) else {
    fail("expected an explicit exposing list")
  }
  @expect.expect(items.map(i => i.value)).to_equal([
    TypeExpose({ name: "Msg", open: Some(range(1, 26, 1, 30)), }),
    FunctionExpose("view"),
    TypeOrAliasExpose("Id"),
  ])
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
  let result = parse(
    "module Main exposing (add)\nimport Html exposing (text)\nadd x = x + 1",
  )
  guard result.cst is Some(cst) else { fail("expected a CST") }
  guard cst.header is Some(header) else { fail("expected a CST header") }
  @expect.expect(header.module_name).to_equal(Some("Main"))
  @expect.expect(header.exposing).to_equal(["add"])
  @expect.expect(header.tokens[0].kind).to_equal(
    @scanner.TokenKind::module_kw(),
  )
  assert_node_span_matches_tokens(header.span, header.tokens)
  @expect.expect(cst.imports.length()).to_equal(1)
  @expect.expect(cst.imports[0].module_name).to_equal("Html")
  @expect.expect(cst.imports[0].exposing).to_equal(Some(["text"]))
  assert_node_span_matches_tokens(cst.imports[0].span, cst.imports[0].tokens)
}

///|
test "imports keep their alias and exposing list" {
  let file = ast(
    parse(
      "module Main exposing (main)\nimport Browser as B exposing (sandbox, Program(..))",
    ),
  )
  @expect.expect(file.imports.length()).to_equal(1)
  let import_ = file.imports[0]
  @expect.expect(import_.range).to_equal(range(2, 1, 2, 52))
  @expect.expect(import_.value.module_name.value).to_equal(["Browser"])
  @expect.expect(import_.value.module_alias.map(a => a.value)).to_equal(
    Some(["B"]),
  )
  guard import_.value.exposing_list is Some({ value: Explicit(items), .. }) else {
    fail("expected an explicit exposing list")
  }
  @expect.expect(items.map(i => i.value)).to_equal([
    FunctionExpose("sandbox"),
    TypeExpose({ name: "Program", open: Some(range(2, 47, 2, 51)), }),
  ])
}

///|
test "function declarations are reported as unsupported and kept in the cst" {
  let result = parse("module Main exposing (add)\nadd x = x + 1")
  @expect.expect(codes(result)).to_equal(["KR-PARSE-005"])
  @expect.expect(ast(result).declarations.length()).to_equal(0)
  guard result.cst is Some(cst) else { fail("expected a CST") }
  guard cst.declarations is [Function(f)] else {
    fail("expected one function in the CST")
  }
  @expect.expect(f.name).to_equal("add")
  @expect.expect(f.args).to_equal(["x"])
  assert_node_span_matches_tokens(f.span, f.tokens)
}

///|
test "cst keeps every declaration while the ast keeps supported ones" {
  let result = parse(
    "module Main exposing (add)\ntype alias User a = a\ntype Color = Red\nadd x = x + 1",
  )
  @expect.expect(codes(result)).to_equal(["KR-PARSE-005", "KR-PARSE-005"])
  guard result.cst is Some(cst) else { fail("expected a CST") }
  guard cst.declarations
    is [TypeAlias(type_alias), UnionType(union), Function(f)] else {
    fail("expected alias, union and function in the CST")
  }
  @expect.expect(type_alias.name).to_equal("User")
  @expect.expect(type_alias.type_params).to_equal(["a"])
  assert_node_span_matches_tokens(type_alias.span, type_alias.tokens)
  @expect.expect(union.name).to_equal("Color")
  assert_node_span_matches_tokens(union.span, union.tokens)
  @expect.expect(f.name).to_equal("add")
  let file = ast(result)
  @expect.expect(custom_type(file, "Color") is Some(_)).to_be_true()
}

///|
test "custom type with one simple constructor becomes a custom type declaration" {
  let file = ast(
    parse("module Main exposing (Wrapper)\ntype Wrapper a = Wrapper a Int"),
  )
  guard custom_type(file, "Wrapper") is Some(t) else {
    fail("expected custom type Wrapper")
  }
  @expect.expect(t.generics.map(g => g.value)).to_equal(["a"])
  guard t.constructors is [c] else { fail("expected one constructor") }
  @expect.expect(c.range).to_equal(range(2, 18, 2, 31))
  @expect.expect(c.value.name.value).to_equal("Wrapper")
  @expect.expect(c.value.arguments.map(a => a.value)).to_equal([
    GenericType("a"),
    Typed({ range: range(2, 28, 2, 31), value: ([], "Int"), }, []),
  ])
}

///|
test "custom type with arguments the parser cannot type is unsupported" {
  let result = parse("module Main exposing (Box)\ntype Box = Box (Maybe Int)")
  @expect.expect(codes(result)).to_equal(["KR-PARSE-005"])
  @expect.expect(ast(result).declarations.length()).to_equal(0)
}

///|
test "doc comment attaches to the following type and starts its range" {
  let file = ast(
    parse(
      "module Main exposing (Msg)\n\nimport Html\n\n{-| A message. -}\ntype Msg\n    = Inc",
    ),
  )
  @expect.expect(file.declarations.length()).to_equal(1)
  @expect.expect(file.declarations[0].range).to_equal(range(5, 1, 7, 10))
  guard custom_type(file, "Msg") is Some(t) else {
    fail("expected custom type Msg")
  }
  @expect.expect(t.documentation).to_equal(
    Some({ range: range(5, 1, 5, 18), value: "{-| A message. -}", }),
  )
  @expect.expect(file.comments.length()).to_equal(0)
}

///|
test "first doc comment after the header documents the module" {
  let file = ast(
    parse(
      "module Main exposing (Msg)\n\n{-| About Main. -}\ntype Msg\n    = Inc",
    ),
  )
  guard custom_type(file, "Msg") is Some(t) else {
    fail("expected custom type Msg")
  }
  @expect.expect(t.documentation is None).to_be_true()
  @expect.expect(file.declarations[0].range).to_equal(range(4, 1, 5, 10))
  @expect.expect(file.comments).to_equal([
    { range: range(3, 1, 3, 19), value: "{-| About Main. -}", },
  ])
}

///|
test "missing module header gives no ast" {
  let result = parse("x = 1")
  @expect.expect(codes(result)).to_contain_element("KR-PARSE-006")
  @expect.expect(result.ast is None).to_be_true()
}

///|
test "malformed module header gives no ast" {
  let result = parse("module Main (add)\nadd x = x + 1")
  @expect.expect(codes(result)).to_contain_element("KR-PARSE-001")
  @expect.expect(result.ast is None).to_be_true()
}

///|
test "malformed exposing list in the header is reported" {
  let result = parse("module Main exposing add\nadd x = x")
  @expect.expect(codes(result)).to_contain_element("KR-PARSE-001")
}

///|
test "parser recovers from a malformed import" {
  let result = parse("module Main exposing (add)\nimport )\ntype Color = Red")
  @expect.expect(codes(result)).to_equal(["KR-PARSE-002"])
  @expect.expect(custom_type(ast(result), "Color") is Some(_)).to_be_true()
}

///|
test "malformed import exposing list is reported" {
  let result = parse(
    "module Main exposing (add)\nimport Html exposing text\ntype Color = Red",
  )
  @expect.expect(codes(result)).to_contain_element("KR-PARSE-002")
  @expect.expect(custom_type(ast(result), "Color") is Some(_)).to_be_true()
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
  let result = parse("module Main exposing (add)\nadd x x + 1\nok y = y")
  @expect.expect(codes(result)).to_equal(["KR-PARSE-004", "KR-PARSE-005"])
}

///|
test "parse module returns scanner diagnostics when tokenization fails" {
  let source = @scanner.SourceText::{
    module_name: Some("Main"),
    text: "{-| missing close",
  }
  let result = @parser.parse_module(source, @scanner.DefaultScanner::new())
  @expect.expect(result.ast is None).to_be_true()
  @expect.expect(result.cst is None).to_be_true()
  @expect.expect(codes(result)).to_contain_element("KR-SCAN-002")
}

///|
test "empty stream has no ast and an empty cst span" {
  let result = @parser.parse_tokens(@scanner.TokenStream::{ tokens: [], })
  @expect.expect(codes(result)).to_equal(["KR-PARSE-006"])
  @expect.expect(result.ast is None).to_be_true()
  guard result.cst is Some(cst) else { fail("expected a CST") }
  @expect.expect(cst.span is None).to_be_true()
}
