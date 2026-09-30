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
test "function declarations are parsed and kept in the cst" {
  let result = parse("module Main exposing (add)\nadd x = x + 1")
  @expect.expect(codes(result)).to_equal([])
  guard ast(result).declarations is [{ value: FunctionDeclaration(f), .. }] else {
    fail("expected one function declaration")
  }
  @expect.expect(f.declaration.value.name.value).to_equal("add")
  guard result.cst is Some(cst) else { fail("expected a CST") }
  guard cst.declarations is [Function(cst_f)] else {
    fail("expected one function in the CST")
  }
  @expect.expect(cst_f.name).to_equal("add")
  @expect.expect(cst_f.args).to_equal(["x"])
  assert_node_span_matches_tokens(cst_f.span, cst_f.tokens)
}

///|
test "ast and cst keep every declaration" {
  let result = parse(
    "module Main exposing (add)\ntype alias User a = a\ntype Color = Red\nadd x = x + 1",
  )
  @expect.expect(codes(result)).to_equal([])
  @expect.expect(ast(result).declarations.length()).to_equal(3)
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
test "custom type arguments can be any type" {
  let result = parse("module Main exposing (Box)\ntype Box = Box (Maybe Int)")
  @expect.expect(codes(result)).to_equal([])
  guard custom_type(ast(result), "Box") is Some(t) else {
    fail("expected custom type Box")
  }
  guard t.constructors is [{ value: { arguments: [arg], .. }, .. }] else {
    fail("expected one constructor with one argument")
  }
  // A parenthesized type is the inner type with a range over the parens.
  @expect.expect(arg.range).to_equal(range(2, 16, 2, 27))
  guard arg.value is Typed({ value: ([], "Maybe"), .. }, [_]) else {
    fail("expected Maybe Int")
  }
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
  @expect.expect(codes(result)).to_equal(["KR-PARSE-004"])
  @expect.expect(ast(result).declarations.length()).to_equal(1)
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
  let result = parse(
    "module Main exposing (..)\n\n\na = '\\u{110000}'\n\n\nb = \"\\u{FFFFFFFFFFFF}\"\n\n\nc = '\\u{D800}'\n",
  )
  @expect.expect(codes(result)).to_equal([])
  let file = ast(result)
  @expect.expect(body_of(file, "a").value).to_equal(CharLiteral('\u{FFFD}'))
  @expect.expect(body_of(file, "b").value).to_equal(Literal("\u{FFFD}"))
  @expect.expect(body_of(file, "c").value).to_equal(CharLiteral('\u{FFFD}'))
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
  let header = "module Main exposing (..)\n\n\n"
  let deep = 5000
  let expr = parse(header + "f = " + nested("(", "1", ")", deep) + "\n")
  @expect.expect(codes(expr)).to_equal(["KR-PARSE-004"])
  let unclosed = parse(header + "f = " + nested("(", "1", "", deep) + "\n")
  @expect.expect(codes(unclosed)).to_equal(["KR-PARSE-004"])
  let list = parse(header + "f = " + nested("[", "1", "]", deep) + "\n")
  @expect.expect(codes(list)).to_equal(["KR-PARSE-004"])
  let typ = parse(header + "f : " + nested("(", "Int", ")", deep) + "\nf = 1\n")
  @expect.expect(codes(typ)).to_equal(["KR-PARSE-004"])
  let pat = parse(header + "f " + nested("(", "x", ")", deep) + " = 1\n")
  @expect.expect(codes(pat)).to_equal(["KR-PARSE-004"])
  let type_alias = parse(
    header + "type alias A = " + nested("(", "Int", ")", deep) + "\n",
  )
  @expect.expect(codes(type_alias)).to_equal(["KR-PARSE-003"])
}

///|
test "moderate nesting still parses" {
  let header = "module Main exposing (..)\n\n\n"
  let depth = 100
  @expect.expect(
    codes(parse(header + "f = " + nested("(", "1", ")", depth) + "\n")),
  ).to_equal([])
  @expect.expect(
    codes(parse(header + "f = " + nested("[", "1", "]", depth) + "\n")),
  ).to_equal([])
  @expect.expect(
    codes(parse(header + "f : " + nested("(", "Int", ")", depth) + "\nf = 1\n")),
  ).to_equal([])
  @expect.expect(
    codes(parse(header + "f " + nested("(", "x", ")", depth) + " = 1\n")),
  ).to_equal([])
}

///|
test "an operator at the branch column after the last branch applies to the case" {
  let result = parse(
    "module Main exposing (..)\n\n\nf x =\n    case x of\n        A -> 1\n        + 2\n",
  )
  @expect.expect(codes(result)).to_equal([])
  let body = body_of(ast(result), "f")
  @expect.expect(body.range).to_equal(range(5, 5, 7, 12))
  guard body.value is OperatorApplication("+", Left, left, _) else {
    fail("expected `+` applied to the case")
  }
  @expect.expect(left.range).to_equal(range(5, 5, 6, 15))
}
