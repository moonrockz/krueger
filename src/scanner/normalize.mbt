///|
fn build_token(
  raw : RawToken,
  kind : TokenKind,
  pending : Array[Trivia],
) -> Token {
  Token::{
    kind,
    lexeme: raw.lexeme,
    span: raw.span,
    trivia_before: pending,
    trivia_after: [],
  }
}

///|
/// Attach trivia to the significant tokens of `raw_tokens` (the output of
/// `lex_raw`). Trivia goes to the next token's `trivia_before`; trivia after
/// the last token goes to its `trivia_after`. When there is no token, the
/// trivia goes to `TokenStream::trivia`. Nothing is dropped.
pub fn normalize_tokens(raw_tokens : Array[RawToken]) -> TokenStream {
  let tokens = []
  let mut pending_trivia = []
  for raw in raw_tokens {
    match raw.kind {
      Significant(kind) => {
        tokens.push(build_token(raw, kind, pending_trivia))
        pending_trivia = []
      }
      _ => if raw_to_trivia(raw) is Some(trivia) { pending_trivia.push(trivia) }
    }
  }
  // Trivia after the last token (for example comments at the end of the file)
  // becomes that token's trailing trivia, so nothing is lost.
  if tokens.length() > 0 && pending_trivia.length() > 0 {
    let last = tokens.length() - 1
    tokens[last] = { ..tokens[last], trivia_after: pending_trivia, }
    return TokenStream::{ tokens, trivia: [], }
  }
  TokenStream::{ tokens, trivia: pending_trivia, }
}
