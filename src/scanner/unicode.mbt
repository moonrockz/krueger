///|
/// Whether `cp` is in one of the inclusive start/end pairs of `ranges`.
fn in_ranges(ranges : FixedArray[Int], cp : Int) -> Bool {
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
/// Whether `c` can start a lower-case name (a Unicode lower-case letter).
/// Lower-case names are values, functions and type variables.
///
/// ```mbt check
/// test {
///   inspect(@scanner.is_lower_start('a'), content="true")
///   inspect(@scanner.is_lower_start('é'), content="true")
///   inspect(@scanner.is_lower_start('A'), content="false")
///   inspect(@scanner.is_lower_start('_'), content="false")
/// }
/// ```
pub fn is_lower_start(c : Char) -> Bool {
  let cp = c.to_int()
  if cp < 0x80 {
    c >= 'a' && c <= 'z'
  } else {
    in_ranges(lower_start_ranges, cp)
  }
}

///|
/// Whether `c` can start an upper-case name (a Unicode upper-case or
/// title-case letter). Upper-case names are modules, types and constructors.
/// In the `elm-syntax-7.3.9` dialect the scanner does not start a name with
/// a title-case letter (rule `titlecase-name-start`).
///
/// ```mbt check
/// test {
///   inspect(@scanner.is_upper_start('M'), content="true")
///   inspect(@scanner.is_upper_start('Ä'), content="true")
///   inspect(@scanner.is_upper_start('ǅ'), content="true")
///   inspect(@scanner.is_upper_start('m'), content="false")
/// }
/// ```
pub fn is_upper_start(c : Char) -> Bool {
  let cp = c.to_int()
  if cp < 0x80 {
    c >= 'A' && c <= 'Z'
  } else {
    in_ranges(upper_start_ranges, cp)
  }
}

///|
/// Whether `c` can continue a name: a Unicode letter or number, or `_`.
///
/// ```mbt check
/// test {
///   inspect(@scanner.is_name_part('x'), content="true")
///   inspect(@scanner.is_name_part('_'), content="true")
///   inspect(@scanner.is_name_part('7'), content="true")
///   inspect(@scanner.is_name_part('ß'), content="true")
///   inspect(@scanner.is_name_part('-'), content="false")
///   inspect(@scanner.is_name_part('\''), content="false")
/// }
/// ```
pub fn is_name_part(c : Char) -> Bool {
  let cp = c.to_int()
  if cp < 0x80 {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '_'
  } else {
    in_ranges(inner_ranges, cp)
  }
}

///|
/// Whether `c` is a title-case letter (Lt), such as `ǅ`.
fn is_titlecase(c : Char) -> Bool {
  c.to_int() >= 0x80 && in_ranges(titlecase_ranges, c.to_int())
}

///|
/// Whether `c` is a number outside ASCII (Nd, Nl, No), such as `₁` or `٣`.
fn is_non_ascii_number(c : Char) -> Bool {
  c.to_int() >= 0x80 && in_ranges(number_ranges, c.to_int())
}
