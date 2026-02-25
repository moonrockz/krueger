///|
fn find_doc_comment(trivia : Array[Trivia]) -> Bool {
  trivia.any(fn(item) {
    match item {
      Trivia::Comment(comment) => comment.kind == CommentKind::Doc
      _ => false
    }
  })
}

///|
fn find_regular_comment(trivia : Array[Trivia]) -> Bool {
  trivia.any(fn(item) {
    match item {
      Trivia::Comment(comment) =>
        comment.kind == CommentKind::Line || comment.kind == CommentKind::Block
      _ => false
    }
  })
}

///|
test "attaches doc comment to following token trivia_before" {
  let source = SourceText::{
    module_name: Some("Main"),
    text: "{-| Adds one -}\nadd x = x + 1",
  }
  let scanner = DefaultScanner::new()
  let stream = match scanner.tokenize(source) {
    Ok(stream) => stream
    Err(_) => fail("expected tokenization success")
  }
  assert_true(stream.tokens.length() > 0)
  assert_true(find_doc_comment(stream.tokens[0].trivia_before))
}

///|
test "preserves regular comments in trivia_before" {
  let source = SourceText::{
    module_name: Some("Main"),
    text: "-- line\n{- block -}\nadd x = x + 1",
  }
  let scanner = DefaultScanner::new()
  let stream = match scanner.tokenize(source) {
    Ok(stream) => stream
    Err(_) => fail("expected tokenization success")
  }
  assert_true(stream.tokens.length() > 0)
  assert_true(find_regular_comment(stream.tokens[0].trivia_before))
}
