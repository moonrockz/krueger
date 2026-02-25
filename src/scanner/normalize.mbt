///|
fn keyword_kind(lexeme : String) -> TokenKind {
  match lexeme {
    "module" => TokenKind::ModuleKw
    "exposing" => TokenKind::ExposingKw
    "import" => TokenKind::ImportKw
    "type" => TokenKind::TypeKw
    "alias" => TokenKind::AliasKw
    "if" => TokenKind::IfKw
    "then" => TokenKind::ThenKw
    "else" => TokenKind::ElseKw
    "let" => TokenKind::LetKw
    "in" => TokenKind::InKw
    "case" => TokenKind::CaseKw
    "of" => TokenKind::OfKw
    _ => TokenKind::Identifier
  }
}

///|
fn symbol_kind(lexeme : String) -> TokenKind {
  match lexeme {
    "(" => TokenKind::LParen
    ")" => TokenKind::RParen
    "," => TokenKind::Comma
    "=" => TokenKind::Equals
    "+" => TokenKind::Plus
    ".." => TokenKind::DotDot
    "->" => TokenKind::Arrow
    _ => TokenKind::Unknown
  }
}

///|
fn is_significant(kind : RawTokenKind) -> Bool {
  match kind {
    RawTokenKind::Identifier
    | RawTokenKind::IntLiteral
    | RawTokenKind::Symbol => true
    _ => false
  }
}

///|
fn build_token(raw : RawToken, pending : Array[Trivia]) -> Token {
  let kind = match raw.kind {
    RawTokenKind::Identifier => keyword_kind(raw.lexeme)
    RawTokenKind::IntLiteral => TokenKind::IntLiteral
    RawTokenKind::Symbol => symbol_kind(raw.lexeme)
    _ => TokenKind::Unknown
  }
  Token::{
    kind,
    lexeme: raw.lexeme,
    span: raw.span,
    trivia_before: pending,
    trivia_after: [],
  }
}

///|
pub fn normalize_tokens(raw_tokens : Array[RawToken]) -> TokenStream {
  let tokens = []
  let mut pending_trivia = []
  for raw in raw_tokens {
    if is_significant(raw.kind) {
      tokens.push(build_token(raw, pending_trivia))
      pending_trivia = []
    } else {
      match raw_to_trivia(raw) {
        Some(trivia) => pending_trivia.push(trivia)
        None => ()
      }
    }
  }
  TokenStream::{ tokens, }
}
