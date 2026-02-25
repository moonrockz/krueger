///|
fn unwrap_ok(
  result : Result[@scanner.TokenStream, @scanner.ScanErrorList],
) -> @scanner.TokenStream? {
  match result {
    Ok(stream) => Some(stream)
    Err(_) => None
  }
}

///|
fn value_name_text(name : @ast.ValueName) -> String {
  name.0.0
}

///|
fn type_name_text(name : @ast.TypeName) -> String {
  name.0.0
}

///|
fn exposed_name_text(name : @ast.ExposedName) -> String {
  match name {
    @ast.ExposedName::Value(value) => value_name_text(value)
  }
}

///|
fn find_function_decl(
  ast : @ast.ModuleAst,
  name : String,
) -> @ast.FunctionDeclaration? {
  for decl in ast.declarations {
    match decl {
      @ast.Declaration::FunctionDecl(fn_decl) =>
        if value_name_text(fn_decl.name) == name {
          return Some(fn_decl)
        }
      _ => ()
    }
  }
  None
}

///|
fn find_type_alias_decl(
  ast : @ast.ModuleAst,
  name : String,
) -> @ast.TypeAliasDeclaration? {
  for decl in ast.declarations {
    match decl {
      @ast.Declaration::TypeAliasDecl(alias_decl) =>
        if type_name_text(alias_decl.name) == name {
          return Some(alias_decl)
        }
      _ => ()
    }
  }
  None
}

///|
fn find_union_decl(
  ast : @ast.ModuleAst,
  name : String,
) -> @ast.UnionTypeDeclaration? {
  for decl in ast.declarations {
    match decl {
      @ast.Declaration::UnionTypeDecl(union_decl) =>
        if type_name_text(union_decl.name) == name {
          return Some(union_decl)
        }
      _ => ()
    }
  }
  None
}

///|
fn has_diag_code(result : ParseResult, code : String) -> Bool {
  result.diagnostics.any(fn(diag) { diag.code == code })
}

///|
fn assert_node_span_matches_tokens(
  node_span : @scanner.Span,
  tokens : Array[@scanner.Token],
) -> Unit raise {
  assert_true(tokens.length() > 0)
  assert_eq(node_span.start, tokens[0].span.start)
  assert_eq(node_span.end, tokens[tokens.length() - 1].span.end)
}

///|
test "parse tokens captures module header information" {
  let source = @scanner.SourceText::{
    module_name: Some("Main"),
    text: "module Main exposing (add)\nadd x = x + 1",
  }
  let scanner = @scanner.DefaultScanner::new()
  let tokens = match unwrap_ok(scanner.tokenize(source)) {
    Some(tokens) => tokens
    None => fail("expected tokenization success")
  }
  let result = parse_tokens(tokens)
  match result.ast {
    Some(ast) => {
      assert_eq(
        ast.module_name,
        Some(@ast.ModuleName::ModuleName(@ast.Identifier::Identifier("Main"))),
      )
      assert_eq(ast.exposing.map(exposed_name_text), ["add"])
    }
    None => fail("expected ast")
  }
}

///|
test "parse tokens captures cst header and imports" {
  let source = @scanner.SourceText::{
    module_name: Some("Main"),
    text: "module Main exposing (add)\nimport Html exposing (text)\nadd x = x + 1",
  }
  let scanner = @scanner.DefaultScanner::new()
  let tokens = match unwrap_ok(scanner.tokenize(source)) {
    Some(tokens) => tokens
    None => fail("expected tokenization success")
  }
  let result = parse_tokens(tokens)
  match result.cst {
    Some(cst) => {
      match cst.header {
        Some(header) => {
          assert_eq(header.module_name, Some("Main"))
          assert_eq(header.exposing, ["add"])
          assert_eq(header.tokens[0].kind, @scanner.TokenKind::module_kw())
          assert_node_span_matches_tokens(header.span, header.tokens)
        }
        None => fail("expected module header cst")
      }
      assert_eq(cst.imports.length(), 1)
      assert_eq(cst.imports[0].module_name, "Html")
      assert_eq(cst.imports[0].exposing, Some(["text"]))
      assert_eq(cst.imports[0].tokens[0].kind, @scanner.TokenKind::import_kw())
      assert_node_span_matches_tokens(cst.imports[0].span, cst.imports[0].tokens)
    }
    None => fail("expected cst")
  }
}

///|
test "parse tokens captures function declaration" {
  let source = @scanner.SourceText::{
    module_name: Some("Main"),
    text: "module Main exposing (add)\nadd x = x + 1",
  }
  let scanner = @scanner.DefaultScanner::new()
  let tokens = match unwrap_ok(scanner.tokenize(source)) {
    Some(tokens) => tokens
    None => fail("expected tokenization success")
  }
  let result = parse_tokens(tokens)
  match result.ast {
    Some(ast) =>
      match find_function_decl(ast, "add") {
        Some(fn_decl) => {
          assert_eq(fn_decl.args.map(value_name_text), ["x"])
          match fn_decl.body {
            @ast.Expr::Unparsed(unparsed) =>
              assert_true(unparsed.tokens.length() > 0)
            _ => fail("expected unparsed function body")
          }
        }
        None => fail("expected function declaration add")
      }
    None => fail("expected ast")
  }
}

///|
test "parse tokens emits typed cst declarations with token span fidelity" {
  let source = @scanner.SourceText::{
    module_name: Some("Main"),
    text: "module Main exposing (add)\ntype alias User a = a\ntype Color = Red\nadd x = x + 1",
  }
  let scanner = @scanner.DefaultScanner::new()
  let tokens = match unwrap_ok(scanner.tokenize(source)) {
    Some(tokens) => tokens
    None => fail("expected tokenization success")
  }
  let result = parse_tokens(tokens)
  match result.cst {
    Some(cst) => {
      assert_eq(cst.declarations.length(), 3)
      match cst.declarations[0] {
        @cst.DeclarationCst::TypeAlias(alias_decl) => {
          assert_eq(alias_decl.name, "User")
          assert_eq(alias_decl.type_params, ["a"])
          assert_node_span_matches_tokens(alias_decl.span, alias_decl.tokens)
        }
        _ => fail("expected type alias cst declaration")
      }
      match cst.declarations[1] {
        @cst.DeclarationCst::UnionType(union_decl) => {
          assert_eq(union_decl.name, "Color")
          assert_eq(union_decl.type_params, [])
          assert_node_span_matches_tokens(union_decl.span, union_decl.tokens)
        }
        _ => fail("expected union type cst declaration")
      }
      match cst.declarations[2] {
        @cst.DeclarationCst::Function(function_decl) => {
          assert_eq(function_decl.name, "add")
          assert_eq(function_decl.args, ["x"])
          assert_node_span_matches_tokens(function_decl.span, function_decl.tokens)
        }
        _ => fail("expected function cst declaration")
      }
    }
    None => fail("expected cst")
  }
}

///|
test "parse tokens attaches doc comment to function declaration" {
  let source = @scanner.SourceText::{
    module_name: Some("Main"),
    text: "module Main exposing (add)\n\n{-| Adds one to a value. -}\nadd x = x + 1",
  }
  let scanner = @scanner.DefaultScanner::new()
  let tokens = match unwrap_ok(scanner.tokenize(source)) {
    Some(tokens) => tokens
    None => fail("expected tokenization success")
  }
  let result = parse_tokens(tokens)
  match result.ast {
    Some(ast) =>
      match find_function_decl(ast, "add") {
        Some(fn_decl) =>
          match fn_decl.meta.doc_comment {
            Some(doc) => assert_eq(doc.text, "Adds one to a value.")
            None => fail("expected attached doc comment")
          }
        None => fail("expected function declaration add")
      }
    None => fail("expected ast")
  }
}

///|
test "parse tokens captures imports and type declarations" {
  let source = @scanner.SourceText::{
    module_name: Some("Main"),
    text: "module Main exposing (add)\nimport Html exposing (text)\ntype alias User = String\ntype Color = Red\nadd x = x + 1",
  }
  let scanner = @scanner.DefaultScanner::new()
  let tokens = match unwrap_ok(scanner.tokenize(source)) {
    Some(tokens) => tokens
    None => fail("expected tokenization success")
  }
  let result = parse_tokens(tokens)
  match result.ast {
    Some(ast) => {
      assert_eq(ast.imports.length(), 1)
      assert_eq(ast.imports[0].module_name.0.0, "Html")
      match ast.imports[0].exposing {
        Some(names) => assert_eq(names.map(exposed_name_text), ["text"])
        None => fail("expected import exposing list")
      }
      assert_true(find_type_alias_decl(ast, "User") != None)
      assert_true(find_union_decl(ast, "Color") != None)
    }
    None => fail("expected ast")
  }
}

///|
test "parse tokens supports mixed top-level declaration ordering" {
  let source = @scanner.SourceText::{
    module_name: Some("Main"),
    text: "module Main exposing (add)\nimport Html\ntype alias User = String\nadd x = x + 1\ntype Color = Red",
  }
  let scanner = @scanner.DefaultScanner::new()
  let tokens = match unwrap_ok(scanner.tokenize(source)) {
    Some(tokens) => tokens
    None => fail("expected tokenization success")
  }
  let result = parse_tokens(tokens)
  match result.ast {
    Some(ast) => {
      assert_true(find_function_decl(ast, "add") != None)
      assert_true(find_type_alias_decl(ast, "User") != None)
      assert_true(find_union_decl(ast, "Color") != None)
    }
    None => fail("expected ast")
  }
}

///|
test "parse tokens reports diagnostic for malformed module header" {
  let source = @scanner.SourceText::{
    module_name: Some("Main"),
    text: "module Main (add)\nadd x = x + 1",
  }
  let scanner = @scanner.DefaultScanner::new()
  let tokens = match unwrap_ok(scanner.tokenize(source)) {
    Some(tokens) => tokens
    None => fail("expected tokenization success")
  }
  let result = parse_tokens(tokens)
  assert_true(has_diag_code(result, "KR-PARSE-001"))
}

///|
test "parse tokens recovers from malformed import and parses later function" {
  let source = @scanner.SourceText::{
    module_name: Some("Main"),
    text: "module Main exposing (add)\nimport )\nadd x = x + 1",
  }
  let scanner = @scanner.DefaultScanner::new()
  let tokens = match unwrap_ok(scanner.tokenize(source)) {
    Some(tokens) => tokens
    None => fail("expected tokenization success")
  }
  let result = parse_tokens(tokens)
  assert_true(has_diag_code(result, "KR-PARSE-002"))
  match result.ast {
    Some(ast) => assert_true(find_function_decl(ast, "add") != None)
    None => fail("expected ast")
  }
}

///|
test "parse tokens reports diagnostic for malformed type declaration" {
  let source = @scanner.SourceText::{
    module_name: Some("Main"),
    text: "module Main exposing (add)\ntype alias = String\nadd x = x + 1",
  }
  let scanner = @scanner.DefaultScanner::new()
  let tokens = match unwrap_ok(scanner.tokenize(source)) {
    Some(tokens) => tokens
    None => fail("expected tokenization success")
  }
  let result = parse_tokens(tokens)
  assert_true(has_diag_code(result, "KR-PARSE-003"))
}

///|
test "parse tokens reports diagnostic for malformed function declaration" {
  let source = @scanner.SourceText::{
    module_name: Some("Main"),
    text: "module Main exposing (add)\nadd x x + 1\nok y = y",
  }
  let scanner = @scanner.DefaultScanner::new()
  let tokens = match unwrap_ok(scanner.tokenize(source)) {
    Some(tokens) => tokens
    None => fail("expected tokenization success")
  }
  let result = parse_tokens(tokens)
  assert_true(has_diag_code(result, "KR-PARSE-004"))
  match result.ast {
    Some(ast) => assert_true(find_function_decl(ast, "ok") != None)
    None => fail("expected ast")
  }
}

///|
test "parse module returns scanner diagnostics when tokenization fails" {
  let source = @scanner.SourceText::{
    module_name: Some("Main"),
    text: "{-| missing close",
  }
  let result = parse_module(source, @scanner.DefaultScanner::new())
  assert_eq(result.ast, None)
  assert_eq(result.cst, None)
  assert_true(has_diag_code(result, "KR-SCAN-002"))
}

///|
test "parse tokens reports diagnostic when module exposing list is malformed" {
  let source = @scanner.SourceText::{
    module_name: Some("Main"),
    text: "module Main exposing add\nadd x = x",
  }
  let scanner = @scanner.DefaultScanner::new()
  let tokens = match unwrap_ok(scanner.tokenize(source)) {
    Some(tokens) => tokens
    None => fail("expected tokenization success")
  }
  let result = parse_tokens(tokens)
  assert_true(has_diag_code(result, "KR-PARSE-001"))
}

///|
test "parse tokens reports diagnostic when import exposing list is malformed" {
  let source = @scanner.SourceText::{
    module_name: Some("Main"),
    text: "module Main exposing (add)\nimport Html exposing text\nadd x = x",
  }
  let scanner = @scanner.DefaultScanner::new()
  let tokens = match unwrap_ok(scanner.tokenize(source)) {
    Some(tokens) => tokens
    None => fail("expected tokenization success")
  }
  let result = parse_tokens(tokens)
  assert_true(has_diag_code(result, "KR-PARSE-002"))
  match result.ast {
    Some(ast) => assert_true(find_function_decl(ast, "add") != None)
    None => fail("expected ast")
  }
}

///|
test "parse tokens handles empty stream with empty ast and cst spans" {
  let result = parse_tokens(@scanner.TokenStream::{ tokens: [] })
  match result.ast {
    Some(ast) => assert_eq(ast.span, None)
    None => fail("expected ast")
  }
  match result.cst {
    Some(cst) => assert_eq(cst.span, None)
    None => fail("expected cst")
  }
  assert_eq(result.diagnostics.length(), 0)
}
