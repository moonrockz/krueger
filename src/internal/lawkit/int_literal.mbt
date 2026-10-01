///|
/// A non-negative Int literal, decimal or hex (`0x` and upper-case digits).
/// Edge values: small values, 2^53 - 2 to 2^53 + 2 (where a Double stops
/// holding every Int), 2^63 - 3 to 2^63 - 1 (the largest Int64), and values
/// in between.
pub(all) struct IntLiteral(String) derive(Debug)

///|
pub impl @quickcheck.Arbitrary for IntLiteral with fn arbitrary(_, rs) {
  let two53 = 9007199254740992L
  let max = 9223372036854775807L
  let value = match pick(rs, 4) {
    0 => pick(rs, 300).to_int64()
    1 => two53 + (pick(rs, 5) - 2).to_int64()
    2 => max - pick(rs, 3).to_int64()
    _ => rs.next_uint64().reinterpret_as_int64() & max
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
