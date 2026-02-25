///|
fn normalize_doc_comment_text(raw : String) -> String {
  let without_prefix = match raw.strip_prefix("{-|") {
    Some(view) => view.to_string()
    None => raw
  }
  let without_suffix = match without_prefix.strip_suffix("-}") {
    Some(view) => view.to_string()
    None => without_prefix
  }
  without_suffix.trim().to_string()
}

///|
fn extract_doc_comment(trivia : Array[@scanner.Trivia]) -> DocComment? {
  let mut candidate : DocComment? = None
  for item in trivia {
    match item {
      @scanner.Trivia::Comment(comment) =>
        match comment.kind {
          @scanner.CommentKind::Doc =>
            candidate = Some(DocComment::{
              text: normalize_doc_comment_text(comment.text),
              span: comment.span,
            })
          @scanner.CommentKind::Line | @scanner.CommentKind::Block =>
            match candidate {
              Some(_) => return None
              None => ()
            }
        }
      _ => ()
    }
  }
  candidate
}

///|
fn module_span(tokens : Array[@scanner.Token]) -> @scanner.Span? {
  if tokens.length() == 0 {
    None
  } else {
    Some(@scanner.Span::{
      start: tokens[0].span.start,
      end: tokens[tokens.length() - 1].span.end,
    })
  }
}

///|
fn looks_like_function_decl_start(
  tokens : Array[@scanner.Token],
  index : Int,
) -> Bool {
  if index >= tokens.length() ||
    tokens[index].kind != @scanner.TokenKind::Identifier {
    return false
  }
  let mut cursor = index + 1
  while cursor < tokens.length() &&
        tokens[cursor].kind == @scanner.TokenKind::Identifier {
    cursor = cursor + 1
  }
  cursor < tokens.length() && tokens[cursor].kind == @scanner.TokenKind::Equals
}

///|
pub fn[S : @scanner.Scanner] parse_module(
  source : @scanner.SourceText,
  scanner : S,
) -> ParseResult {
  match scanner.tokenize(source) {
    Ok(tokens) => parse_tokens(tokens)
    Err(errs) =>
      ParseResult::{ ast: None, cst: None, diagnostics: errs.diagnostics }
  }
}

///|
pub fn parse_tokens(tokens : @scanner.TokenStream) -> ParseResult {
  let stream = tokens.tokens
  let mut cursor = 0
  let mut module_name : String? = None
  let exposing = []
  let declarations = []
  let cst_decls = []

  if stream.length() > 0 && stream[0].kind == @scanner.TokenKind::module_kw() {
    cursor = 1
    if cursor < stream.length() &&
      stream[cursor].kind == @scanner.TokenKind::Identifier {
      module_name = Some(stream[cursor].lexeme)
      cursor = cursor + 1
    }
    if cursor < stream.length() &&
      stream[cursor].kind == @scanner.TokenKind::exposing_kw() {
      cursor = cursor + 1
      if cursor < stream.length() &&
        stream[cursor].kind == @scanner.TokenKind::LParen {
        cursor = cursor + 1
        while cursor < stream.length() &&
              stream[cursor].kind != @scanner.TokenKind::RParen {
          if stream[cursor].kind == @scanner.TokenKind::Identifier {
            exposing.push(stream[cursor].lexeme)
          }
          cursor = cursor + 1
        }
        if cursor < stream.length() &&
          stream[cursor].kind == @scanner.TokenKind::RParen {
          cursor = cursor + 1
        }
      }
    }
  }

  while cursor < stream.length() {
    if stream[cursor].kind != @scanner.TokenKind::Identifier {
      cursor = cursor + 1
      continue
    }

    let name_token = stream[cursor]
    let name = name_token.lexeme
    cursor = cursor + 1

    let args = []
    while cursor < stream.length() &&
          stream[cursor].kind == @scanner.TokenKind::Identifier {
      args.push(stream[cursor].lexeme)
      cursor = cursor + 1
    }

    if cursor < stream.length() &&
      stream[cursor].kind == @scanner.TokenKind::Equals {
      cursor = cursor + 1
    } else {
      continue
    }

    let body_tokens = []
    while cursor < stream.length() &&
          !looks_like_function_decl_start(stream, cursor) {
      body_tokens.push(stream[cursor])
      cursor = cursor + 1
    }

    let meta = DeclMeta::{
      doc_comment: extract_doc_comment(name_token.trivia_before),
      span: name_token.span,
    }
    declarations.push(
      Declaration::FunctionDecl(FunctionDeclaration::{
        name,
        args,
        body_tokens,
        meta,
      }),
    )
    cst_decls.push(CstDecl::{
      kind: "function",
      span: name_token.span,
      tokens: [],
    })
  }

  ParseResult::{
    ast: Some(ModuleAst::{
      module_name,
      exposing,
      imports: [],
      declarations,
      span: module_span(stream),
    }),
    cst: Some(ModuleCst::{
      tokens: stream,
      declarations: cst_decls,
      span: module_span(stream),
    }),
    diagnostics: [],
  }
}
