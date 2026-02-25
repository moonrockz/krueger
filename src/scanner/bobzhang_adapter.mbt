pub(all) enum RawTokenKind {
  Identifier
  IntLiteral
  Symbol
} derive(Eq, Show)

pub(all) struct RawToken {
  kind : RawTokenKind
  lexeme : String
  span : Span
} derive(Eq, Show)

fn position(lexer : @lexer.Lexer) -> Position {
  let loc = lexer.get_loc()
  Position::{ offset: lexer.get_position(), line: loc.line, column: loc.column }
}

fn is_identifier_start(ch : Char) -> Bool {
  ch.is_ascii_alphabetic() || ch == '_'
}

fn is_identifier_continue(ch : Char) -> Bool {
  ch.is_ascii_alphabetic() || ch.is_ascii_digit() || ch == '_' || ch == '\''
}

fn consume_identifier(lexer : @lexer.Lexer) -> String {
  let mut lexeme = ""
  while lexer.peek() is Some(ch) && is_identifier_continue(ch) {
    lexeme = lexeme + Char::to_string(ch)
    lexer.advance()
  }
  lexeme
}

fn consume_int_literal(lexer : @lexer.Lexer) -> String {
  let mut lexeme = ""
  while lexer.peek() is Some(ch) && ch.is_ascii_digit() {
    lexeme = lexeme + Char::to_string(ch)
    lexer.advance()
  }
  lexeme
}

fn push_token(
  tokens : Array[RawToken],
  kind : RawTokenKind,
  lexeme : String,
  start : Position,
  end_ : Position,
) -> Unit {
  tokens.push(
    RawToken::{ kind, lexeme, span: Span::{ start, end: end_ } },
  )
}

fn consume_newline(lexer : @lexer.Lexer) -> Unit {
  match lexer.view() {
    ['\r', '\n', ..] => {
      lexer.advance()
      lexer.advance()
      lexer.new_line()
    }
    ['\n', ..] => {
      lexer.advance()
      lexer.new_line()
    }
    _ => ()
  }
}

pub fn lex_raw(source : SourceText) -> Result[Array[RawToken], ScanErrorList] {
  let lexer = @lexer.Lexer::new(source.text)
  let tokens = []
  while lexer.peek() is Some(_) {
    lexer.skip_whitespace()
    match lexer.peek() {
      None => ()
      Some('\n') | Some('\r') => consume_newline(lexer)
      Some(ch) if is_identifier_start(ch) => {
        let start = position(lexer)
        let lexeme = consume_identifier(lexer)
        push_token(tokens, RawTokenKind::Identifier, lexeme, start, position(lexer))
      }
      Some(ch) if ch.is_ascii_digit() => {
        let start = position(lexer)
        let lexeme = consume_int_literal(lexer)
        push_token(tokens, RawTokenKind::IntLiteral, lexeme, start, position(lexer))
      }
      Some(_) => {
        let start = position(lexer)
        let lexeme = match lexer.view() {
          ['.', '.', ..] => {
            lexer.advance()
            lexer.advance()
            ".."
          }
          ['-', '>', ..] => {
            lexer.advance()
            lexer.advance()
            "->"
          }
          [ch, ..] => {
            lexer.advance()
            Char::to_string(ch)
          }
          _ => {
            lexer.advance()
            ""
          }
        }
        if lexeme != "" {
          push_token(tokens, RawTokenKind::Symbol, lexeme, start, position(lexer))
        }
      }
    }
  }
  Ok(tokens)
}
