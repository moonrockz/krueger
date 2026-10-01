///|
/// A non-negative Int literal, decimal or hex (`0x` and upper-case digits).
/// Edge values: small values, 2^53 - 2 to 2^53 + 2 (where a Double stops
/// holding every Int), powers of two 2^54 to 2^62 (a Double holds them, but
/// writes other digits: 2^60 is `1152921504606847000`), 2^63 - 3 to 2^63 - 1
/// (the largest Int64), and values in between. Never a value whose digits
/// are its Double's shortest form without being that Double (such as
/// `1152921504606847000`): JSON text cannot tell it from the Double, and
/// the decoder reads the Double.
pub(all) struct IntLiteral(String) derive(Debug)

///|
pub impl @quickcheck.Arbitrary for IntLiteral with fn arbitrary(_, rs) {
  let two53 = 9007199254740992L
  let max = 9223372036854775807L
  let value = match pick(rs, 5) {
    0 => pick(rs, 300).to_int64()
    1 => two53 + (pick(rs, 5) - 2).to_int64()
    2 => 1L << (54 + pick(rs, 9))
    3 => max - pick(rs, 3).to_int64()
    _ => rs.next_uint64().reinterpret_as_int64() & max
  }
  let d = value.to_double()
  let value = if value.to_string() == d.to_string() && d.to_int64() != value {
    value + 1
  } else {
    value
  }
  IntLiteral(
    if pick(rs, 2) == 0 {
      value.to_string()
    } else {
      "0x" + value.to_string(radix=16).to_upper()
    },
  )
}

///|
pub impl @quickcheck.Shrink for IntLiteral

///|
/// The literal's text.
pub fn IntLiteral::text(self : IntLiteral) -> String {
  let IntLiteral(text) = self
  text
}
