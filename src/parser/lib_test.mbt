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
