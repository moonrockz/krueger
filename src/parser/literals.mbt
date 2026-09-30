///|
/// Decode the escapes elm-syntax accepts: `\n` `\r` `\t` `\"` `\'` `\\` and
/// `\u{HEX}`. `body` is the literal without its quotes.
fn decode_escapes(body : String) -> String raise SyntaxError {
  let sb = StringBuilder()
  let chars = body.to_array()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c != '\\' {
      sb.write_char(c)
      i += 1
      continue
    }
    guard chars.get(i + 1) is Some(e) else {
      raise SyntaxError("unfinished escape", dummy_span)
    }
    match e {
      'n' => sb.write_char('\n')
      'r' => sb.write_char('\r')
      't' => sb.write_char('\t')
      '"' => sb.write_char('"')
      '\'' => sb.write_char('\'')
      '\\' => sb.write_char('\\')
      'u' => {
        guard chars.get(i + 2) is Some('{') else {
          raise SyntaxError("expected `{` in unicode escape", dummy_span)
        }
        let mut j = i + 3
        let mut code = 0
        while j < chars.length() && chars[j] != '}' {
          // Stop growing past the largest code point, so long runs cannot overflow.
          if code <= 0x10FFFF {
            code = code * 16 + hex_value(chars[j])
          }
          j += 1
        }
        // A value that is not a Unicode scalar value (above U+10FFFF, or a
        // surrogate) becomes U+FFFD.
        let scalar = code <= 0x10FFFF && !(code >= 0xD800 && code <= 0xDFFF)
        sb.write_char(
          if scalar {
            Int::unsafe_to_char(code)
          } else {
            '\u{FFFD}'
          },
        )
        i = j + 1
        continue
      }
      _ => raise SyntaxError("unknown escape `\\\{e}`", dummy_span)
    }
    i += 2
  }
  sb.to_string()
}

///|
let dummy_span : @scanner.Span = {
  start: { offset: 0, line: 1, column: 1, },
  end: { offset: 0, line: 1, column: 1, },
}

///|
fn hex_value(c : Char) -> Int {
  match c {
    '0'..='9' => c.to_int() - '0'.to_int()
    'a'..='f' => c.to_int() - 'a'.to_int() + 10
    'A'..='F' => c.to_int() - 'A'.to_int() + 10
    _ => 0
  }
}

///|
/// Value of a single- or triple-quoted string token.
fn string_value(token : @scanner.Token) -> String raise SyntaxError {
  let text = token.lexeme
  let quote = if text.has_prefix("\"\"\"") { 3 } else { 1 }
  let body = text.unsafe_substring(start=quote, end=text.length() - quote)
  decode_escapes(body) catch {
    SyntaxError(message, _) => raise SyntaxError(message, token.span)
  }
}

///|
/// Value of a char token.
fn char_value(token : @scanner.Token) -> Char raise SyntaxError {
  let text = token.lexeme
  let value = decode_escapes(
    text.unsafe_substring(start=1, end=text.length() - 1),
  ) catch {
    SyntaxError(message, _) => raise SyntaxError(message, token.span)
  }
  match value.get_char(0) {
    Some(c) => c
    None => raise SyntaxError("empty char literal", token.span)
  }
}

///|
/// An integer token: `Ok(n)` for decimal, `Err(n)` for hexadecimal.
fn int_value(token : @scanner.Token) -> Result[Int64, Int64] raise SyntaxError {
  let text = token.lexeme
  if text.has_prefix("0x") {
    let digits = text.unsafe_substring(start=2, end=text.length())
    Err(
      @string.parse_int64(digits, base=16) catch {
        _ => raise SyntaxError("hex literal out of range", token.span)
      },
    )
  } else {
    Ok(
      @string.parse_int64(text) catch {
        _ => raise SyntaxError("integer literal out of range", token.span)
      },
    )
  }
}

///|
fn float_value(token : @scanner.Token) -> Double raise SyntaxError {
  @string.parse_double(token.lexeme) catch {
    _ => raise SyntaxError("invalid float literal", token.span)
  }
}
