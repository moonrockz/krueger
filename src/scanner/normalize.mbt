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

fn normalize_token(raw : RawToken) -> Token {
  let kind = match raw.kind {
    RawTokenKind::Identifier => keyword_kind(raw.lexeme)
    RawTokenKind::IntLiteral => TokenKind::IntLiteral
    RawTokenKind::Symbol => symbol_kind(raw.lexeme)
  }
  Token::{
    kind,
    lexeme: raw.lexeme,
    span: raw.span,
    trivia_before: [],
    trivia_after: [],
  }
}

pub fn normalize_tokens(raw_tokens : Array[RawToken]) -> TokenStream {
  TokenStream::{ tokens: raw_tokens.map(normalize_token) }
}
