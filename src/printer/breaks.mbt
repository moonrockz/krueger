///|
fn compare_location(a : @ast.Location, b : @ast.Location) -> Int {
  if a.row != b.row {
    a.row.compare(b.row)
  } else {
    a.column.compare(b.column)
  }
}

///|
/// The index of the first token that starts at or after `loc`.
fn SourceFacts::first_at_or_after(
  self : SourceFacts,
  loc : @ast.Location,
) -> Int {
  let mut lo = 0
  let mut hi = self.starts.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if compare_location(self.starts[mid], loc) < 0 {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}

///|
fn SourceFacts::token_at(self : SourceFacts, loc : @ast.Location) -> Int? {
  let i = self.first_at_or_after(loc)
  if i < self.starts.length() && compare_location(self.starts[i], loc) == 0 {
    Some(i)
  } else {
    None
  }
}

///|
fn SourceFacts::lexeme_at(self : SourceFacts, loc : @ast.Location) -> String? {
  self.token_at(loc).map(i => self.lexemes[i])
}

///|
/// The gap before the first token at or after `loc` has a line break.
fn SourceFacts::break_before(self : SourceFacts, loc : @ast.Location) -> Bool {
  let i = self.first_at_or_after(loc)
  i < self.starts.length() && self.prefix[i + 1] - self.prefix[i] > 0
}

///|
/// A gap between two tokens inside `range` has a line break. The gap before
/// the first token of the range is not inside it.
fn SourceFacts::break_within(self : SourceFacts, range : @ast.Range) -> Bool {
  let first = self.first_at_or_after(range.start)
  let after = self.first_at_or_after(range.end)
  // Gaps first+1 ..< after are inside the range.
  after > first + 1 && self.prefix[after] - self.prefix[first + 1] > 0
}
