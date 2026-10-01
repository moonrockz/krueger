///|
/// Whether `a` comes before `b` or is `b`.
pub fn at_or_before(a : @ast.Location, b : @ast.Location) -> Bool {
  a.row < b.row || (a.row == b.row && a.column <= b.column)
}

///|
/// Whether `r` contains `p` (`start <= p < end`; an empty range contains
/// nothing).
pub fn contains(r : @ast.Range, p : @ast.Location) -> Bool {
  at_or_before(r.start, p) && !at_or_before(r.end, p)
}

///|
/// Whether `a` lies inside `b`.
pub fn within(a : @ast.Range, b : @ast.Range) -> Bool {
  at_or_before(b.start, a.start) && at_or_before(a.end, b.end)
}

///|
/// The lines of `text` as the scanner counts them: split at `\n`, with one
/// `\r` before a `\n` dropped (CRLF); any other `\r` is a character.
fn lines(text : String) -> Array[StringView] {
  let parts : Array[StringView] = text.split("\n").collect()
  let last = parts.length() - 1
  parts.mapi((i, line) => {
    if i < last && line.has_suffix("\r") {
      line.view(end_offset=line.length() - 1)
    } else {
      line
    }
  })
}

///|
/// Whether the unit at `i` is the low half of a surrogate pair (a low
/// surrogate right after a high one), which adds no column.
fn continues_pair(text : StringView, i : Int) -> Bool {
  let c = text.code_unit_at(i).to_int()
  c >= 0xDC00 &&
  c <= 0xDFFF &&
  i > 0 &&
  text.code_unit_at(i - 1).to_int() >= 0xD800 &&
  text.code_unit_at(i - 1).to_int() <= 0xDBFF
}

///|
/// The number of columns `s` takes, counted as the scanner counts them: one
/// for every UTF-16 unit except the low half of a surrogate pair (so a pair
/// is one column, and a lone surrogate, high or low, is one).
fn code_points(s : StringView) -> Int {
  let mut n = 0
  for i in 0..<s.length() {
    if !continues_pair(s, i) {
      n = n + 1
    }
  }
  n
}

///|
/// The position after the last character of `text`, counted from the text
/// itself: rows at each `\n`, columns in code points, a CRLF one line break
/// and a lone `\r` one column.
pub fn end_of_text(text : String) -> @ast.Location {
  let all = lines(text)
  { row: all.length(), column: code_points(all[all.length() - 1]) + 1, }
}

///|
/// For each range its start, its end, and one column before each; sorted,
/// without duplicates.
pub fn range_edges(ranges : Array[@ast.Range]) -> Array[@ast.Location] {
  let found : Array[@ast.Location] = []
  for r in ranges {
    found.push(r.start)
    found.push(r.end)
    if r.end.column > 1 {
      found.push({ row: r.end.row, column: r.end.column - 1, })
    }
    if r.start.column > 1 {
      found.push({ row: r.start.row, column: r.start.column - 1, })
    }
  }
  sorted_unique(found)
}

///|
fn sorted_unique(found : Array[@ast.Location]) -> Array[@ast.Location] {
  found.sort_by((a, b) => {
    if a == b {
      0
    } else if at_or_before(a, b) {
      -1
    } else {
      1
    }
  })
  let out : Array[@ast.Location] = []
  for p in found {
    if out.last() != Some(p) {
      out.push(p)
    }
  }
  out
}

///|
/// The positions where boundary bugs live, for laws over positions: for each
/// range its start, its end, one column before each; for each line its start,
/// its end (after its last code point) and one column past its end; the end
/// of the text; the row after the last; and (1,1). Sorted, without
/// duplicates.
pub fn edge_positions(
  text : String,
  ranges : Array[@ast.Range],
) -> Array[@ast.Location] {
  let found = range_edges(ranges)
  found.push({ row: 1, column: 1, })
  let all = lines(text)
  for i, line in all {
    let row = i + 1
    let end = code_points(line) + 1
    found.push({ row, column: 1, })
    found.push({ row, column: end, })
    found.push({ row, column: end + 1, })
  }
  found.push(end_of_text(text))
  found.push({ row: all.length() + 1, column: 1, })
  sorted_unique(found)
}

///|
/// The UTF-16 offset of position `p` in `text`, or `None` when `p` is not on
/// the text. Columns are counted as the scanner counts them (see
/// `code_points`); a CRLF is one line break. The end of a line and the end of
/// the text are on it.
pub fn offset_of(text : String, p : @ast.Location) -> Int? {
  let mut row = 1
  let mut column = 1
  let mut i = 0
  while i < text.length() {
    let c = text.code_unit_at(i).to_int()
    if row == p.row && column == p.column && !continues_pair(text, i) {
      return Some(i)
    }
    let crlf = c == '\r'.to_int() &&
      i + 1 < text.length() &&
      text.code_unit_at(i + 1).to_int() == '\n'.to_int()
    if c == '\n'.to_int() || crlf {
      if row == p.row {
        return None
      }
      row = row + 1
      column = 1
      i = i + (if crlf { 2 } else { 1 })
    } else {
      if !continues_pair(text, i) {
        column = column + 1
      }
      i = i + 1
    }
  }
  if row == p.row && column == p.column {
    Some(i)
  } else {
    None
  }
}

///|
/// A few ranges on a small grid (rows 1 to 3; columns from 1, adjacent ranges
/// continuing past column 6). Edge values,
/// produced on purpose: no range, one range, equal ranges (a copy of an
/// earlier non-empty range), adjacent ranges (starting at an earlier range's
/// end), empty ranges, ranges over two rows.
pub(all) struct Ranges(Array[@ast.Range]) derive(Debug)

///|
pub impl @quickcheck.Arbitrary for Ranges with fn arbitrary(size, rs) {
  let pick = (n : Int) => {
    rs.next_uint(limit=n.reinterpret_as_uint()).reinterpret_as_int()
  }
  let n = pick(size.min(12) + 1)
  let out : Array[@ast.Range] = []
  for _ in 0..<n {
    let earlier = out.filter(r => r.start != r.end)
    let choice = pick(6)
    if choice < 2 && !earlier.is_empty() {
      out.push(earlier[pick(earlier.length())])
    } else if choice == 2 && !out.is_empty() {
      let a = out[pick(out.length())]
      out.push({
        start: a.end,
        end: { row: a.end.row, column: a.end.column + pick(3), },
      })
    } else {
      let row = 1 + pick(2)
      let column = 1 + pick(4)
      let end : @ast.Location = if pick(4) == 0 {
        { row: row + 1, column: 1 + pick(3), }
      } else {
        { row, column: column + pick(3), }
      }
      out.push({ start: { row, column, }, end, })
    }
  }
  Ranges(out)
}

///|
/// Shrinks by dropping one range.
pub impl @quickcheck.Shrink for Ranges with fn shrink(self) {
  let Ranges(ranges) = self
  Array::makei(ranges.length(), i => {
    let fewer = ranges.copy()
    ignore(fewer.remove(i))
    Ranges(fewer)
  }).iter()
}

///|
/// The ranges.
pub fn Ranges::ranges(self : Ranges) -> Array[@ast.Range] {
  let Ranges(ranges) = self
  ranges
}

///|
/// The row and column of each of the sorted UTF-16 `offsets` in `text`, in
/// one pass, counted as the scanner counts them (see `code_points`); `None`
/// for an offset out of order or past the end. An offset inside a CRLF maps
/// to the position before the CRLF, and one inside a surrogate pair to the
/// position after the pair.
pub fn positions_of(
  text : String,
  offsets : Array[Int],
) -> Array[@ast.Location?] {
  let out : Array[@ast.Location?] = []
  let mut row = 1
  let mut column = 1
  let mut i = 0
  for o in offsets {
    if o < i || o > text.length() {
      out.push(None)
      continue
    }
    while i < o {
      let c = text.code_unit_at(i).to_int()
      if c == '\n'.to_int() {
        row = row + 1
        column = 1
      } else if c == '\r'.to_int() &&
        i + 1 < text.length() &&
        text.code_unit_at(i + 1).to_int() == '\n'.to_int() {
        ()
      } else if !continues_pair(text, i) {
        column = column + 1
      }
      i = i + 1
    }
    out.push(Some({ row, column, }))
  }
  out
}

///|
/// The row and column of UTF-16 offset `offset` in `text` (see
/// `positions_of`); `None` past the end. Inverse of `offset_of` on offsets
/// between characters.
pub fn position_of(text : String, offset : Int) -> @ast.Location? {
  positions_of(text, [offset])[0]
}

///|
/// Whether `offset` lies between two characters of `text`: inside the text,
/// and not inside a CRLF or a surrogate pair. Token, trivia and diagnostic
/// boundaries must lie between characters.
pub fn between_characters(text : String, offset : Int) -> Bool {
  let unit = (i : Int) => {
    if i >= 0 && i < text.length() {
      text.code_unit_at(i).to_int()
    } else {
      -1
    }
  }
  0 <= offset &&
  offset <= text.length() &&
  !(unit(offset - 1) == '\r'.to_int() && unit(offset) == '\n'.to_int()) &&
  !(unit(offset - 1) >= 0xD800 &&
  unit(offset - 1) <= 0xDBFF &&
  unit(offset) >= 0xDC00 &&
  unit(offset) <= 0xDFFF)
}
