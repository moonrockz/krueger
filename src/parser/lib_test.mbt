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
fn find_function_decl(ast : ModuleAst, name : String) -> FunctionDeclaration? {
  for decl in ast.declarations {
    match decl {
      Declaration::FunctionDecl(fn_decl) if fn_decl.name == name =>
        return Some(fn_decl)
      _ => ()
    }
  }
  None
}

///|
fn find_type_alias_decl(
  ast : ModuleAst,
  name : String,
) -> TypeAliasDeclaration? {
  for decl in ast.declarations {
    match decl {
      Declaration::TypeAliasDecl(alias_decl) if alias_decl.name == name =>
        return Some(alias_decl)
      _ => ()
    }
  }
  None
}

///|
fn find_union_decl(ast : ModuleAst, name : String) -> UnionTypeDeclaration? {
  for decl in ast.declarations {
    match decl {
      Declaration::UnionTypeDecl(union_decl) if union_decl.name == name =>
        return Some(union_decl)
      _ => ()
    }
  }
  None
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
      assert_eq(ast.module_name, Some("Main"))
      assert_eq(ast.exposing, ["add"])
    }
    None => fail("expected ast")
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
        Some(fn_decl) => assert_eq(fn_decl.args, ["x"])
        None => fail("expected function declaration add")
      }
    None => fail("expected ast")
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
      assert_eq(ast.imports[0].module_name, "Html")
      assert_eq(ast.imports[0].exposing, Some(["text"]))
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
