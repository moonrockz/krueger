///|
/// `cp` as at least 4 upper-case hex digits.
fn hex_code(cp : Int) -> String {
  let digits = cp.to_string(radix=16).to_upper()
  if digits.length() < 4 {
    "0".repeat(4 - digits.length()) + digits
  } else {
    digits
  }
}

///|
/// How a string or char literal is quoted (elm-format `StringStyle`).
priv enum Quote {
  CharQuote
  StringQuote
  TripleQuote
}

///|
/// Whether a literal writes the character with code point `cp` as it is
/// (see `literal_plain_ranges`).
fn is_plain(cp : Int) -> Bool {
  let ranges = literal_plain_ranges
  let mut lo = 0
  let mut hi = ranges.length() / 2 - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    if cp < ranges[mid * 2] {
      hi = mid - 1
    } else if cp > ranges[mid * 2 + 1] {
      lo = mid + 1
    } else {
      return true
    }
  }
  false
}

///|
/// `c` inside a literal quoted with `quote`, escaped as elm-format does
/// (Box.hs `formatString`, `fix`): a line feed stays in a triple-quoted
/// string; `\n`, `\t`, `\\` and the quote are escaped; a character that
/// is not printable or is a space other than U+0020 is `\u{XXXX}`.
fn escaped(c : Char, quote : Quote) -> String {
  match c {
    '\n' if quote is TripleQuote => "\n"
    '\n' => "\\n"
    '\t' => "\\t"
    '\\' => "\\\\"
    '"' if quote is StringQuote => "\\\""
    '\'' if quote is CharQuote => "\\'"
    _ if is_plain(c.to_int()) => c.to_string()
    _ => "\\u{" + hex_code(c.to_int()) + "}"
  }
}

///|
fn string_literal(s : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  for c in s {
    out.write_string(escaped(c, StringQuote))
  }
  out.write_char('"')
  out.to_string()
}

///|
/// `s` as a triple-quoted string. After the escapes, elm-format
/// (`escapeMultiQuote`) escapes each `"` of a run of three or more, and of
/// a run at the end: `"""a\""""`.
fn triple_literal(s : String) -> String {
  let body = StringBuilder()
  for c in s {
    body.write_string(escaped(c, TripleQuote))
  }
  let out = StringBuilder()
  out.write_string("\"\"\"")
  let mut quotes = 0
  let flush = (escape : Bool) => {
    out.write_string((if escape { "\\\"" } else { "\"" }).repeat(quotes))
    quotes = 0
  }
  for c in body.to_string() {
    if c == '"' {
      quotes += 1
    } else {
      flush(quotes >= 3)
      out.write_char(c)
    }
  }
  flush(true)
  out.write_string("\"\"\"")
  out.to_string()
}

///|
fn char_literal(c : Char) -> String {
  "'" + escaped(c, CharQuote) + "'"
}

///|
/// Whether `x` is below zero or is negative zero.
fn is_negative(x : Double) -> Bool {
  x < 0.0 || (x == 0.0 && 1.0 / x < 0.0)
}

///|
/// The shortest text that reads back as `x` (finite and not negative), with
/// a `.` in the mantissa: `1.0`, `0.1`, `1.0e21`, `5.0e-324`.
fn float_text(x : Double) -> String {
  let parts = x.to_string().split("e").map(p => p.to_owned()).collect()
  let mantissa = if parts[0].contains(".") { parts[0] } else { parts[0] + ".0" }
  if parts.length() == 1 {
    return mantissa
  }
  let exponent = StringBuilder()
  for c in parts[1] {
    if c != '+' {
      exponent.write_char(c)
    }
  }
  mantissa + "e" + exponent.to_string()
}

///|
/// `0x` and the upper-case hex `digits` (no leading zeros), padded with
/// zeros to 2, 4, 8 or 16 digits (elm-format `formatLiteral`).
fn hex_padded(digits : String) -> String {
  let len = digits.length()
  let width = if len <= 2 {
    2
  } else if len <= 4 {
    4
  } else if len <= 8 {
    8
  } else {
    16
  }
  "0x" + "0".repeat(if width > len { width - len } else { 0 }) + digits
}

///|
/// `0x` and the upper-case digits of `n` (not negative), padded with zeros to
/// 2, 4, 8 or 16 digits.
fn hex_text(n : Int64) -> String {
  hex_padded(n.to_string(radix=16).to_upper())
}

///|
/// The shortest decimal digits of `x` (finite, not negative) and their
/// exponent `e`: `x` is `0.digits` times `10^e` (Haskell `floatToDigits`).
/// Zero gives `("0", 0)`.
fn float_digits(x : Double) -> (String, Int) {
  let parts = x.to_string().split("e").map(p => p.to_owned()).collect()
  let mut exponent = 0
  if parts.length() > 1 {
    let mut sign = 1
    for c in parts[1] {
      match c {
        '-' => sign = -1
        '+' => ()
        _ => exponent = exponent * 10 + (c.to_int() - '0'.to_int())
      }
    }
    exponent = sign * exponent
  }
  let digits : Array[Char] = []
  let mut point : Int? = None
  for c in parts[0] {
    if c == '.' {
      point = Some(digits.length())
    } else {
      digits.push(c)
    }
  }
  exponent += point.unwrap_or(digits.length())
  let mut first = 0
  while first < digits.length() && digits[first] == '0' {
    first += 1
    exponent -= 1
  }
  let mut end = digits.length()
  while end > first && digits[end - 1] == '0' {
    end -= 1
  }
  guard first < end else { return ("0", 0) }
  (String::from_array(digits[first:end]), exponent)
}

///|
/// `x` (finite, not negative) with one digit before the point and an
/// exponent: Haskell `showEFloat Nothing` (`1.0e3`, `1.5e-7`, `0.0e0`), as
/// elm-format writes a float with an exponent.
fn exponent_float_text(x : Double) -> String {
  let (digits, e) = float_digits(x)
  if digits == "0" {
    return "0.0e0"
  }
  let rest = digits.view(start_offset=1).to_owned()
  digits.view(end_offset=1).to_owned() +
  "." +
  (if rest.is_empty() { "0" } else { rest }) +
  "e" +
  (e - 1).to_string()
}

///|
/// `x` (finite, not negative) with all its digits and no exponent: Haskell
/// `showFFloat Nothing` (`1000.0`, `0.000001`), as elm-format writes a
/// float without an exponent.
fn decimal_float_text(x : Double) -> String {
  let (digits, e) = float_digits(x)
  if e <= 0 {
    return "0." + "0".repeat(-e) + digits
  }
  let whole = if digits.length() >= e {
    digits.view(end_offset=e).to_owned()
  } else {
    digits + "0".repeat(e - digits.length())
  }
  let fraction = if digits.length() > e {
    digits.view(start_offset=e).to_owned()
  } else {
    "0"
  }
  whole + "." + fraction
}

///|
/// Whether `s` is one or more ASCII digits.
fn all_digits(s : StringView, hex? : Bool = false) -> Bool {
  !s.is_empty() &&
  s
  .iter()
  .all(c => {
    (c >= '0' && c <= '9') ||
    (hex && ((c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')))
  })
}

///|
/// `digits` without its leading zeros (`"0"` stays).
fn without_leading_zeros(digits : StringView) -> String {
  let mut first = 0
  while first + 1 < digits.length() && digits.get_char(first) == Some('0') {
    first += 1
  }
  digits.view(start_offset=first).to_owned()
}

///|
/// The lexeme of the literal token that starts at `r.start` in the
/// `ElmFormat` layout with source, else `None`. elm-format reads the form
/// of a literal from its source: a float with or without an exponent, a
/// triple-quoted string.
fn Ctx::literal_lexeme(self : Ctx, r : @ast.Range) -> String? {
  match (self.layout, self.source) {
    (ElmFormat, Some(facts)) => facts.lexeme_at(r.start)
    _ => None
  }
}

///|
/// A decimal integer (not negative). elm-format writes its value; from a
/// lexeme, its digits without leading zeros, so a value that the parser
/// clamps (above the largest `Int64`) keeps its digits.
fn Ctx::integer_text(self : Ctx, r : @ast.Range, n : Int64) -> String {
  match self.literal_lexeme(r) {
    Some(l) if all_digits(l) => without_leading_zeros(l)
    _ => n.to_string()
  }
}

///|
/// A hex integer (not negative): upper-case digits, padded (see
/// `hex_padded`). From a lexeme, its digits, as for `Ctx::integer_text`.
fn Ctx::hex_literal_text(self : Ctx, r : @ast.Range, n : Int64) -> String {
  match self.literal_lexeme(r) {
    Some(l) if (l.has_prefix("0x") || l.has_prefix("0X")) &&
      all_digits(l.view(start_offset=2), hex=true) =>
      hex_padded(without_leading_zeros(l.view(start_offset=2)).to_upper())
    _ => hex_text(n)
  }
}

///|
/// A float (not negative) from its lexeme, in elm-format's form for it
/// (`exponent_float_text` when the lexeme has an exponent, else
/// `decimal_float_text`); `None` without a lexeme. A value too big for a
/// `Double` keeps its lexeme.
fn Ctx::float_lexeme_text(self : Ctx, r : @ast.Range, x : Double) -> String? {
  guard self.literal_lexeme(r) is Some(l) &&
    l.iter().all(c => c is ('0'..='9' | '.' | 'e' | 'E' | '+' | '-')) else {
    return None
  }
  if x.is_nan() || x.is_inf() {
    Some(l)
  } else if l.contains_char('e') || l.contains_char('E') {
    Some(exponent_float_text(x))
  } else {
    Some(decimal_float_text(x))
  }
}

///|
/// A string literal: triple-quoted when its lexeme is (`ElmFormat` layout
/// with source), else quoted with `"`.
fn Ctx::string_doc(self : Ctx, r : @ast.Range, s : String) -> @pretty.Doc {
  match self.literal_lexeme(r) {
    Some(l) if l.has_prefix("\"\"\"") => {
      let text = triple_literal(s)
      // Its line breaks are part of the value: no indentation after them.
      if text.contains_char('\n') {
        @pretty.verbatim(text)
      } else {
        @pretty.text(text)
      }
    }
    _ => @pretty.text(string_literal(s))
  }
}

///|
/// Whether `n` is the smallest `Int64` (the only value whose negation is
/// itself, apart from zero).
fn is_min_int(n : Int64) -> Bool {
  n < 0L && -n < 0L
}
