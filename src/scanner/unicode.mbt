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
/// title-case letter).
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
