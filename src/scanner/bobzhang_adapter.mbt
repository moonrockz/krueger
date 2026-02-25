pub(all) enum RawTokenKind {
  Identifier
  IntLiteral
  Symbol
  Whitespace
  Newline
  LineComment
  BlockComment
  DocComment
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

fn consume_horizontal_whitespace(lexer : @lexer.Lexer) -> String {
  let mut lexeme = ""
  while lexer.peek() is Some(ch) && (ch == ' ' || ch == '\t') {
    lexeme = lexeme + Char::to_string(ch)
    lexer.advance()
  }
  lexeme
}

fn consume_newline(lexer : @lexer.Lexer) -> String {
  match lexer.view() {
    ['\r', '\n', ..] => {
      lexer.advance()
      lexer.advance()
      lexer.new_line()
      "\r\n"
    }
    ['\n', ..] => {
      lexer.advance()
      lexer.new_line()
      "\n"
    }
    _ => ""
  }
}

fn consume_line_comment(lexer : @lexer.Lexer) -> String {
  let mut lexeme = "--"
  lexer.advance()
  lexer.advance()
  while lexer.peek() is Some(ch) && ch != '\n' && ch != '\r' {
    lexeme = lexeme + Char::to_string(ch)
    lexer.advance()
  }
  lexeme
}

fn consume_block_comment(lexer : @lexer.Lexer, is_doc : Bool) -> (String, Bool) {
  let mut lexeme = if is_doc { "{-|" } else { "{-" }
  lexer.advance()
  lexer.advance()
  if is_doc {
    lexer.advance()
  }
  let mut closed = false
  let mut done = false
  while !done {
    match lexer.view() {
      ['-', '}', ..] => {
        lexeme = lexeme + "-}"
        lexer.advance()
        lexer.advance()
        closed = true
        done = true
      }
      ['\r', '\n', ..] => {
        lexeme = lexeme + "\r\n"
        lexer.advance()
        lexer.advance()
        lexer.new_line()
      }
      ['\n', ..] => {
        lexeme = lexeme + "\n"
        lexer.advance()
        lexer.new_line()
      }
      [ch, ..] => {
        lexeme = lexeme + Char::to_string(ch)
        lexer.advance()
      }
      _ => {
        done = true
      }
    }
  }
  (lexeme, closed)
}

fn symbol_lexeme_or_invalid(lexer : @lexer.Lexer) -> (String, Bool) {
  match lexer.view() {
    ['.', '.', ..] => {
      lexer.advance()
      lexer.advance()
      ("..", true)
    }
    ['-', '>', ..] => {
      lexer.advance()
      lexer.advance()
      ("->", true)
    }
    ['(' | ')' | ',' | '=' | '+', ..] => {
      match lexer.peek() {
        Some(ch) => {
          lexer.advance()
          (Char::to_string(ch), true)
        }
        None => ("", false)
      }
    }
    [ch, ..] => {
      lexer.advance()
      (Char::to_string(ch), false)
    }
    _ => ("", false)
  }
}

pub fn lex_raw(source : SourceText) -> Result[Array[RawToken], ScanErrorList] {
  let lexer = @lexer.Lexer::new(source.text)
  let tokens = []
  let diagnostics = []
  while lexer.peek() is Some(_) {
    let start = position(lexer)
    match lexer.view() {
      [' ' | '\t', ..] => {
        let lexeme = consume_horizontal_whitespace(lexer)
        push_token(tokens, RawTokenKind::Whitespace, lexeme, start, position(lexer))
      }
      ['\r', '\n', ..] | ['\n', ..] => {
        let lexeme = consume_newline(lexer)
        push_token(tokens, RawTokenKind::Newline, lexeme, start, position(lexer))
      }
      ['-', '-', ..] => {
        let lexeme = consume_line_comment(lexer)
        push_token(tokens, RawTokenKind::LineComment, lexeme, start, position(lexer))
      }
      ['{', '-', '|', ..] => {
        let (lexeme, closed) = consume_block_comment(lexer, true)
        push_token(tokens, RawTokenKind::DocComment, lexeme, start, position(lexer))
        if !closed {
          diagnostics.push(
            malformed_doc_comment(
              Span::{ start, end: position(lexer) },
            ),
          )
        }
      }
      ['{', '-', ..] => {
        let (lexeme, closed) = consume_block_comment(lexer, false)
        push_token(tokens, RawTokenKind::BlockComment, lexeme, start, position(lexer))
        if !closed {
          diagnostics.push(
            unterminated_block_comment(
              Span::{ start, end: position(lexer) },
            ),
          )
        }
      }
      [ch, ..] if is_identifier_start(ch) => {
        let lexeme = consume_identifier(lexer)
        push_token(tokens, RawTokenKind::Identifier, lexeme, start, position(lexer))
      }
      [ch, ..] if ch.is_ascii_digit() => {
        let lexeme = consume_int_literal(lexer)
        push_token(tokens, RawTokenKind::IntLiteral, lexeme, start, position(lexer))
      }
      [_, ..] => {
        let (lexeme, valid) = symbol_lexeme_or_invalid(lexer)
        if valid {
          push_token(tokens, RawTokenKind::Symbol, lexeme, start, position(lexer))
        } else {
          diagnostics.push(
            invalid_sequence(
              Span::{ start, end: position(lexer) },
            ),
          )
        }
      }
      _ => ()
    }
  }
  if diagnostics.length() > 0 {
    Err(ScanErrorList::{ diagnostics })
  } else {
    Ok(tokens)
  }
}
