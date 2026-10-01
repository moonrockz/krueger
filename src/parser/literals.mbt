///|
/// Decode the escapes elm-syntax accepts: `\n` `\r` `\t` `\"` `\'` `\\` and
/// `\u{HEX}`. `body` is the literal without its quotes.
fn decode_escapes(
  body : String,
  code_point_limit? : Bool = false,
) -> String raise SyntaxError {
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
      raise literal_error("UNKNOWN ESCAPE", "unfinished escape")
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
          raise literal_error(
            "BAD UNICODE ESCAPE", "expected `{` in unicode escape",
          )
        }
        let mut j = i + 3
        let mut code = 0
        while j < chars.length() && chars[j] != '}' {
          guard hex_value(chars[j]) is Some(digit) else {
            raise literal_error(
              "BAD UNICODE ESCAPE", "expected a hex digit in unicode escape",
            )
          }
          // Stop growing past the largest code point, so long runs cannot overflow.
          if code <= 0x10FFFF {
            code = code * 16 + digit
          }
          j += 1
        }
        if j >= chars.length() || j == i + 3 {
          raise literal_error(
            "BAD UNICODE ESCAPE", "expected hex digits and `}` in unicode escape",
          )
        }
        if code_point_limit && code > 0x10FFFF {
          raise literal_error("BAD UNICODE ESCAPE", "code point above 10FFFF")
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
      _ => raise literal_error("UNKNOWN ESCAPE", "unknown escape `\\\{e}`")
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
fn hex_value(c : Char) -> Int? {
  match c {
    '0'..='9' => Some(c.to_int() - '0'.to_int())
    'a'..='f' => Some(c.to_int() - 'a'.to_int() + 10)
    'A'..='F' => Some(c.to_int() - 'A'.to_int() + 10)
    _ => None
  }
}

///|
/// A literal error before its token is known; `with_span` places it.
fn literal_error(title : String, message : String) -> SyntaxError {
  SyntaxError(message, dummy_span, { title, report: [], })
}

///|
/// A literal error at `span`, with the report for its title.
fn literal_problem(
  title : String,
  message : String,
  span : @scanner.Span,
) -> SyntaxError {
  let highlight = point(span.start)
  let problem = match title {
    "UNKNOWN ESCAPE" =>
      span_problem(
        title,
        "Backslashes always start escaped characters, but I do not recognize this one:",
        highlight,
        [
          Text([
            Plain("Valid escape characters include "),
            @scanner.Chunk::code("\\n"),
            Plain(", "),
            @scanner.Chunk::code("\\t"),
            Plain(", "),
            @scanner.Chunk::code("\\\""),
            Plain(", "),
            @scanner.Chunk::code("\\'"),
            Plain(", "),
            @scanner.Chunk::code("\\\\"),
            Plain(" and "),
            @scanner.Chunk::code("\\u{1F600}"),
            Plain("."),
          ]),
        ],
      )
    "BAD UNICODE ESCAPE" if message.has_prefix("code point") =>
      span_problem(title, "This is not a valid code point:", highlight, [
        plain("The valid code points are between 0 and 10FFFF inclusive."),
      ])
    "BAD UNICODE ESCAPE" =>
      span_problem(title, "I ran into an invalid Unicode escape:", highlight, [
        Text([
          Plain("A Unicode escape looks like "),
          @scanner.Chunk::code("\\u{1F600}"),
          Plain(", with 4 to 6 hex digits between the curly braces."),
        ]),
      ])
    "NEEDS DOUBLE QUOTES" =>
      span_problem(
        title,
        "The following string uses single quotes:",
        highlight,
        [
          Text([
            Plain("Please switch to double quotes instead: "),
            @scanner.Chunk::code("'this'"),
            Plain(" becomes "),
            @scanner.Chunk::code("\"this\""),
            Plain(". Elm uses single quotes only for one character, like "),
            @scanner.Chunk::code("'a'"),
            Plain("."),
          ]),
        ],
      )
    _ =>
      span_problem(title, "I ran into a problem with this number:", highlight, [])
  }
  SyntaxError(message, span, problem)
}

///|
/// Value of a single- or triple-quoted string token.
fn string_value(
  token : @scanner.Token,
  dialect : @dialect.Dialect,
) -> String raise SyntaxError {
  let text = token.lexeme
  let quote = if text.has_prefix("\"\"\"") { 3 } else { 1 }
  let body = text.unsafe_substring(start=quote, end=text.length() - quote)
  decode_escapes(body, code_point_limit=dialect.has(BadUnicodeEscape)) catch {
    SyntaxError(message, _, problem) =>
      raise literal_problem(problem.title, message, token.span)
  }
}

///|
/// Value of a char token.
fn char_value(
  token : @scanner.Token,
  dialect : @dialect.Dialect,
) -> Char raise SyntaxError {
  let text = token.lexeme
  let value = decode_escapes(
    text.unsafe_substring(start=1, end=text.length() - 1),
    code_point_limit=dialect.has(BadUnicodeEscape),
  ) catch {
    SyntaxError(message, _, problem) =>
      raise literal_problem(problem.title, message, token.span)
  }
  // `iter` takes a lone surrogate as one character (`char_length` aborts).
  if dialect.has(CharLength) && value.iter().take(2).count() > 1 {
    raise literal_problem(
      "NEEDS DOUBLE QUOTES",
      "a char literal holds one character [rule: char-length]",
      token.span,
    )
  }
  match value.get_char(0) {
    Some(c) => c
    None =>
      raise literal_problem(
        "NEEDS DOUBLE QUOTES",
        "empty char literal",
        token.span,
      )
  }
}

///|
/// A warning for a number too big to store exactly: krueger keeps the
/// nearest value it can (`Int64` max, or infinity), as elm make accepts it.
fn out_of_range(c : Cursor, token : @scanner.Token, kept : String) -> Unit {
  c.warnings.push({
    code: "KR-PARSE-009",
    severity: Warning,
    message: "Number literal out of range",
    span: token.span,
    title: "NUMBER OUT OF RANGE",
    report: [
      plain("This number is too big for me to store exactly:"),
      Excerpt(
        context=point(token.span.start),
        highlight=point(token.span.start),
      ),
      plain(
        "I will use \{kept} instead. Elm compiles it, but the value may not be what you expect.",
      ),
    ],
  })
}

///|
/// An integer token: `Ok(n)` for decimal, `Err(n)` for hexadecimal. A value
/// above the `Int64` range becomes `Int64` max, with a warning.
fn int_value(c : Cursor, token : @scanner.Token) -> Result[Int64, Int64] {
  let text = token.lexeme
  let max = 9223372036854775807L
  if text.has_prefix("0x") {
    let digits = text.unsafe_substring(start=2, end=text.length())
    Err(
      @string.parse_int64(digits, base=16) catch {
        _ => {
          out_of_range(c, token, "the largest 64-bit integer")
          max
        }
      },
    )
  } else {
    Ok(
      @string.parse_int64(text) catch {
        _ => {
          out_of_range(c, token, "the largest 64-bit integer")
          max
        }
      },
    )
  }
}

///|
/// A float token. A value beyond the `Double` range becomes infinity, with a
/// warning.
fn float_value(c : Cursor, token : @scanner.Token) -> Double {
  @string.parse_double(token.lexeme) catch {
    _ => {
      out_of_range(c, token, "infinity")
      1.0 / 0.0
    }
  }
}
