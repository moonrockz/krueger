///|
/// The AST of `text`, or `None` when it has a diagnostic with severity
/// `Error`.
fn parse_ok(text : String) -> @ast.File? {
  let r = @parser.parse_module(
    @scanner.SourceText::new(text),
    @scanner.DefaultScanner::new(),
  )
  if r.diagnostics.iter().any(d => d.severity is Error) {
    None
  } else {
    r.ast
  }
}

///|
/// The text of `format` in `layout`, or `None` when it raises.
fn format_in(text : String, layout : @printer.Layout) -> String? {
  try @printer.format(text, layout~) catch {
    _ => None
  } noraise {
    t => Some(t)
  }
}

///|
test "law: format is idempotent in both layouts" {
  // The shapes on which elm-format 0.8.7 is not idempotent are all in doc
  // comments (`@docs T(..)`, emphasis after a letter, two bullet lists,
  // `[a] [a]`, a fenced code block that starts with a blank line; see
  // `normalize_file`). `Spaced` has no doc comments, so it excludes them.
  @quickcheck.check(
    (m : @lawkit.Spaced) => {
      let t = m.text()
      guard parse_ok(t) is Some(_) else { return false }
      [@printer.Layout::ElmFormat, Width(40), Width(120)]
      .iter()
      .all(layout => {
        guard format_in(t, layout) is Some(once) else { return false }
        format_in(once, layout) == Some(once)
      })
    },
    count=100,
    max_size=20,
    seed=2030,
  )
}

///|
test "law: format is idempotent on modules with comments in every gap" {
  // The doc comments of `Commented` have none of the shapes on which
  // elm-format is not idempotent (see the law above).
  @quickcheck.check(
    (m : @lawkit.Commented) => {
      let t = m.text()
      guard parse_ok(t) is Some(_) else { return false }
      [@printer.Layout::ElmFormat, Width(40), Width(120)]
      .iter()
      .all(layout => {
        guard format_in(t, layout) is Some(once) else { return false }
        format_in(once, layout) == Some(once)
      })
    },
    count=100,
    max_size=20,
    seed=2035,
  )
}

///|
test "law: the AST does not change through format, apart from ranges and normalization" {
  // `format` keeps parentheses that hold a comment and a flat chain of
  // operators of one precedence and different directions, which
  // `normalize_file` changes (see its documentation); `normalize_file`
  // gives the same AST for both. Comments are checked by "law: format
  // prints every regular comment once, in source order".
  @quickcheck.check(
    (m : @lawkit.Commented) => {
      let t = m.text()
      guard parse_ok(t) is Some(before) else { return false }
      guard format_in(t, ElmFormat) is Some(out) else { return false }
      guard parse_ok(out) is Some(after) else { return false }
      let code = (f : @ast.File) => {
        @lawkit.without_ranges({ ..f, comments: [][:], })
      }
      code(@printer.normalize_file(after)) ==
      code(@printer.normalize_file(before))
    },
    count=100,
    max_size=20,
    seed=2031,
  )
}

///|
test "law: format returns text or raises ParseFailed for any text" {
  @quickcheck.check(
    (m : @lawkit.ElmText) => {
      let t = m.text()
      try @printer.format(t) catch {
        ParseFailed(_) => parse_ok(t) is None
        Unprintable(_) => false
      } noraise {
        _ => true
      }
    },
    count=300,
    max_size=24,
    seed=2032,
  )
}

///|
test "law: in the Width layout no line is longer than the width, unless it is one token" {
  @quickcheck.check(
    (m : @lawkit.Spaced) => {
      guard format_in(m.text(), Width(40)) is Some(out) else { return false }
      out
      .split("\n")
      .all(line => line.char_length() <= 40 || !line.trim().contains(" "))
    },
    count=100,
    max_size=20,
    seed=2033,
  )
}

///|
test "the formatter laws reach their success branch" {
  // Spaced modules format, and formatting changes most of them; some
  // ElmText inputs parse, so the never-crash law also formats text.
  let rs = @splitmix.new(seed=2036)
  let mut formatted = 0
  let mut changed = 0
  for i in 0..<100 {
    let m : @lawkit.Spaced = @quickcheck.Arbitrary::arbitrary(i % 20, rs)
    if format_in(m.text(), ElmFormat) is Some(out) {
      formatted += 1
      if out != m.text() {
        changed += 1
      }
    }
  }
  let mut parsed = 0
  for i in 0..<300 {
    let m : @lawkit.ElmText = @quickcheck.Arbitrary::arbitrary(i % 24, rs)
    if parse_ok(m.text()) is Some(_) {
      parsed += 1
    }
  }
  @expect.expect_all(s => {
    s.expect(formatted).to_equal(100)
    s.expect(changed > 80).to_be_true()
    s.expect(parsed > 30).to_be_true()
  })
}
