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
/// `c` inside a literal quoted with `quote`, escaped as elm-format does.
fn escaped(c : Char, quote : Char) -> String {
  let cp = c.to_int()
  match c {
    '\n' => "\\n"
    '\t' => "\\t"
    '\\' => "\\\\"
    _ if c == quote => "\\" + quote.to_string()
    _ if cp < 0x20 ||
      (cp >= 0x7F && cp <= 0x9F) ||
      cp == 0x2028 ||
      cp == 0x2029 ||
      (cp >= 0xD800 && cp <= 0xDFFF) => "\\u{" + hex_code(cp) + "}"
    _ => c.to_string()
  }
}

///|
fn string_literal(s : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  for c in s {
    out.write_string(escaped(c, '"'))
  }
  out.write_char('"')
  out.to_string()
}

///|
fn char_literal(c : Char) -> String {
  "'" + escaped(c, '\'') + "'"
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
/// `0x` and the upper-case digits of `n` (not negative), padded with zeros to
/// 2, 4, 8 or 16 digits.
fn hex_text(n : Int64) -> String {
  let digits = n.to_string(radix=16).to_upper()
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
  "0x" + "0".repeat(width - len) + digits
}

///|
/// Whether `n` is the smallest `Int64` (the only value whose negation is
/// itself, apart from zero).
fn is_min_int(n : Int64) -> Bool {
  n < 0L && -n < 0L
}
