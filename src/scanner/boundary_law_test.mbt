///|
fn scan(text : String) -> Result[@scanner.TokenStream, @scanner.ScanErrorList] {
  @scanner.DefaultScanner::new().tokenize(@scanner.SourceText::{
    module_name: None,
    text,
  })
}

///|
fn trivia_text(t : @scanner.Trivia) -> String {
  match t {
    Whitespace(s, _) | Newline(s, _) => s
    Comment(c) => c.text
  }
}

///|
fn trivia_span(t : @scanner.Trivia) -> @scanner.Span {
  match t {
    Whitespace(_, span) | Newline(_, span) => span
    Comment(c) => c.span
  }
}

///|
/// Every piece of the token stream, in order: (text, span).
fn pieces(ts : @scanner.TokenStream) -> Array[(String, @scanner.Span)] {
  let out = []
  for v in ts.trivia {
    out.push((trivia_text(v), trivia_span(v)))
  }
  for t in ts.tokens {
    for v in t.trivia_before {
      out.push((trivia_text(v), trivia_span(v)))
    }
    out.push((t.lexeme, t.span))
    for v in t.trivia_after {
      out.push((trivia_text(v), trivia_span(v)))
    }
  }
  out
}

///|
/// Whether `p` is the position at its own offset in `text`, and that offset
/// lies between two characters (not inside a CRLF or a surrogate pair).
fn agrees(text : String, p : @scanner.Position) -> Bool {
  @lawkit.between_characters(text, p.offset) &&
  @lawkit.position_of(text, p.offset) ==
  Some({ row: p.line, column: p.column, })
}

///|
fn in_bounds(text : String, s : @scanner.Span) -> Bool {
  0 <= s.start.offset &&
  s.start.offset <= s.end.offset &&
  s.end.offset <= text.length() &&
  agrees(text, s.start) &&
  agrees(text, s.end)
}

///|
test "law: tokens and trivia rebuild the source" {
  // Edges: empty text, only a comment, only whitespace, CRLF, a lone `\r`,
  // tab, BOM, surrogate pairs, lone surrogates, no final newline.
  @quickcheck.check(
    (t : @lawkit.ElmText) => {
      let text = t.text()
      match scan(text) {
        Ok(ts) =>
          (ts.tokens.is_empty() || ts.trivia.is_empty()) &&
          pieces(ts).map(p => p.0).join("") == text
        Err(_) => true
      }
    },
    count=200,
    max_size=24,
    seed=263,
  )
}

///|
/// Whether the pieces of `ts` tile `text`: each starts where the last ended,
/// holds exactly its slice of the text, and has positions that agree with
/// their offsets; the last ends at the end of the text.
fn tiles(text : String, ts : @scanner.TokenStream) -> Bool {
  let mut at = 0
  let mut ok = true
  for p in pieces(ts) {
    let (piece, span) = p
    ok = ok &&
      span.start.offset == at &&
      span.end.offset == at + piece.length() &&
      span.end.offset <= text.length() &&
      text.view(start_offset=at, end_offset=span.end.offset) == piece &&
      agrees(text, span.start) &&
      agrees(text, span.end)
    at = span.end.offset
  }
  ok && at == text.length()
}

///|
test "law: token and trivia spans tile the text and agree with their offsets" {
  @quickcheck.check(
    (t : @lawkit.ElmText) => {
      let text = t.text()
      match scan(text) {
        Ok(ts) => tiles(text, ts)
        Err(_) => true
      }
    },
    count=200,
    max_size=24,
    seed=269,
  )
}

///|
test "law: the scanner never crashes, and its diagnostics lie inside the source" {
  @quickcheck.check(
    (t : @lawkit.ElmText) => {
      let text = t.text()
      match scan(text) {
        Ok(_) => true
        Err(errs) =>
          !errs.diagnostics.is_empty() &&
          errs.diagnostics.iter().all(d => in_bounds(text, d.span))
      }
    },
    count=200,
    max_size=24,
    seed=271,
  )
}

///|
test "a lone high surrogate is one character in its diagnostic" {
  // The diagnostic must not swallow the line break that follows.
  let text = @lawkit.units([0xD800, '\n'.to_int(), 'b'.to_int()])
  guard scan(text) is Err(errs) else { fail("expected a diagnostic") }
  let span = errs.diagnostics[0].span
  @expect.expect_all(s => {
    s.expect(span.end.offset).to_equal(1)
    s.expect((span.end.line, span.end.column)).to_equal((1, 2))
  })
}

///|
test "a text of only whitespace and comments keeps its trivia" {
  guard scan("  -- c\n{- d -}") is Ok(ts) else { fail("expected tokens") }
  @expect.expect_all(s => {
    s.expect(ts.tokens.length()).to_equal(0)
    s.expect(ts.trivia.map(trivia_text).join("")).to_equal("  -- c\n{- d -}")
  })
}

///|
test "an unterminated char or string stops before an unescaped CRLF" {
  @expect.expect_all(s => {
    for text in ["'a\r\n", "\"a\r\n"] {
      guard scan(text) is Err(errs) else { fail("expected a diagnostic") }
      let end = errs.diagnostics[0].span.end
      s
      .expect((text, end.offset, end.line))
      .to_equal((text, text.length() - 2, 1))
    }
    // An escaped line break is part of the literal, which runs to the end.
    guard scan("'\\\r\n") is Err(errs) else { fail("expected a diagnostic") }
    s.expect(errs.diagnostics[0].span.end.offset).to_equal(4)
  })
}

///|
test "a lone low surrogate is one column" {
  let text = @lawkit.units(['a'.to_int(), 0xDC00, 'b'.to_int()])
  guard scan(text) is Err(errs) else { fail("expected a diagnostic") }
  let span = errs.diagnostics[0].span
  @expect.expect((span.start.column, span.end.column)).to_equal((2, 3))
}

///|
test "a backslash before a line break is an escape inside the literal, as in elm make" {
  // elm make reports UNKNOWN ESCAPE: the literal goes on after the line break.
  for text in ["\"a\\\nb\"", "\"a\\\r\nb\"", "'\\\n'", "'\\\r\n'"] {
    guard scan(text) is Ok(ts) else {
      fail("\{text.escape()}: expected a literal")
    }
    @expect.expect(ts.tokens.map(t => t.lexeme)).to_equal([text])
  }
}

///|
test "law: a character Elm does not allow is reported as exactly one character" {
  // Edges: lone high and low surrogates, a surrogate pair outside a name, tab,
  // `;`, `` ` ``, `#`, `@`, BOM.
  @quickcheck.check(
    (t : @lawkit.ElmText) => {
      let text = t.text()
      match scan(text) {
        Ok(_) => true
        Err(errs) =>
          errs.diagnostics
          .iter()
          .filter(d => d.code == "KR-SCAN-003")
          .all(d => {
            d.span.start.line == d.span.end.line &&
            d.span.end.column == d.span.start.column + 1 &&
            agrees(text, d.span.start) &&
            agrees(text, d.span.end)
          })
      }
    },
    count=200,
    max_size=24,
    seed=293,
  )
}

///|
test "every literal and comment form holding an edge character scans losslessly or reports in bounds" {
  // Exhaustive: every literal and comment form (closed and not) x every edge
  // character x every ending.
  @expect.expect_all(s => {
    for form in @lawkit.literal_forms() {
      for edge in @lawkit.edge_chars() {
        for tail in ["", "\n", "\r\n", " 1\n"] {
          let text = "x =\n    " + form.0 + edge + form.1 + tail
          let ok = match scan(text) {
            Ok(ts) =>
              (ts.tokens.is_empty() || ts.trivia.is_empty()) &&
              pieces(ts).map(p => p.0).join("") == text &&
              tiles(text, ts)
            Err(errs) =>
              !errs.diagnostics.is_empty() &&
              errs.diagnostics.iter().all(d => in_bounds(text, d.span))
          }
          s.expect((text.escape(), ok)).to_equal((text.escape(), true))
        }
      }
    }
  })
}
