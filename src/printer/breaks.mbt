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

///|
/// How a construct chooses between its one-line and multi-line forms.
priv enum Split {
  /// Fit in the line width (`Width` layout).
  Fit
  /// One line, unless a part has a forced break (`ElmFormat`, no break in
  /// the source where elm-format looks).
  Join
  /// Multi-line (`ElmFormat`, the source has a break where elm-format
  /// looks).
  Split
}

///|
/// `Fit` for `Width`; for `ElmFormat`, `Split` when there is source and
/// `broken()` is true, else `Join`.
fn Ctx::split_if(self : Ctx, broken : () -> Bool) -> Split {
  match self.layout {
    Width(_) => Fit
    ElmFormat => if self.source is Some(_) && broken() { Split } else { Join }
  }
}

///|
/// `Split` when a gap between two tokens inside `range` has a line break:
/// elm-format keeps a construct multi-line when its source is multi-line.
fn Ctx::split_within(self : Ctx, range : @ast.Range) -> Split {
  self.split_if(() => self.source.unwrap().break_within(range))
}

///|
/// `Split` when the gap before `range` or a gap inside it has a line break:
/// elm-format's `trackNewline` around the whitespace before a part and the
/// part itself.
fn Ctx::split_from(self : Ctx, range : @ast.Range) -> Split {
  self.split_if(() => {
    let facts = self.source.unwrap()
    facts.break_before(range.start) || facts.break_within(range)
  })
}

///|
/// `Fit` for `Width`, `Join` for `ElmFormat`: for a construct that
/// elm-format makes multi-line only when a part of it is multi-line.
fn Ctx::join(self : Ctx) -> Split {
  self.split_if(() => false)
}

///|
/// The line break for `s`: a hard line break for `Split`, else a line
/// break that is a space when the group fits.
fn split_line(s : Split) -> @pretty.Doc {
  if s is Split {
    @pretty.hardline()
  } else {
    @pretty.line()
  }
}

///|
/// The line break for `s`: a hard line break for `Split`, else a line
/// break that is nothing when the group fits.
fn split_softline(s : Split) -> @pretty.Doc {
  if s is Split {
    @pretty.hardline()
  } else {
    @pretty.softline()
  }
}
