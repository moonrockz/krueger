///|
fn parse_text(text : String) -> @parser.ParseResult {
  @parser.parse_module(
    @scanner.SourceText::{ module_name: None, text, },
    @scanner.DefaultScanner::new(),
  )
}

///|
/// Whether span `s` lies inside `text`, its ends lie between characters, and
/// its rows and columns agree with its offsets.
fn span_in_bounds(text : String, s : @scanner.Span) -> Bool {
  0 <= s.start.offset &&
  s.start.offset <= s.end.offset &&
  s.end.offset <= text.length() &&
  @lawkit.between_characters(text, s.start.offset) &&
  @lawkit.between_characters(text, s.end.offset) &&
  @lawkit.position_of(text, s.start.offset) ==
  Some({ row: s.start.line, column: s.start.column, }) &&
  @lawkit.position_of(text, s.end.offset) ==
  Some({ row: s.end.line, column: s.end.column, })
}

///|
fn errors(r : @parser.ParseResult) -> Array[@scanner.Diagnostic] {
  r.diagnostics.filter(d => d.severity is Error)
}

///|
test "law: the parser never crashes, and its diagnostics lie inside the source" {
  // Edges: text that is not Elm (fragments, unclosed literals and comments,
  // tab, a lone `\r`, BOM, lone surrogates) and valid modules cut short or
  // with a fragment put in or a piece taken out.
  @quickcheck.check(
    (t : @lawkit.ElmText) => {
      let text = t.text()
      parse_text(text).diagnostics.iter().all(d => span_in_bounds(text, d.span))
    },
    count=200,
    max_size=24,
    seed=277,
  )
}

///|
/// Whether the nesting was rejected: some error, all of them TOO MUCH
/// NESTING. Any other error, or an accepted module without its declaration
/// `f`, fails the law.
fn rejected(text : String) -> Bool raise {
  let r = parse_text(text)
  let errs = errors(r)
  if errs.iter().any(d => d.title != "TOO MUCH NESTING") {
    fail(
      "an error other than TOO MUCH NESTING: " +
      errs.map(d => d.title).join(", "),
    )
  }
  if errs.is_empty() && !has_f(r) {
    fail("accepted without the declaration f")
  }
  !errs.is_empty()
}

///|
/// Whether the AST has a declaration named `f`.
fn has_f(r : @parser.ParseResult) -> Bool {
  guard r.ast is Some(file) else { return false }
  file.declarations
  .iter()
  .any(d => {
    match d.value {
      FunctionDeclaration(f) => f.declaration.value.name.value == "f"
      _ => false
    }
  })
}

///|
test "law: nesting is accepted or rejected as too deep, and rejection is monotonic" {
  // Edges: every construct at depths 1 and 2 and around both limits (150
  // nesting levels, 400 AST levels, and half the nesting limit for
  // constructs that count two levels each), plus uniform depths to 450.
  @quickcheck.check(
    (n : @lawkit.Nesting) => {
      let deeper : @lawkit.Nesting = { ..n, depth: n.depth + 1, }
      // Parse both: a short circuit would skip `deeper` when `n` is accepted.
      let a = rejected(n.text())
      let b = rejected(deeper.text())
      !a || b
    },
    count=100,
    max_size=24,
    seed=281,
  )
}

///|
test "each construct changes verdict at its pinned threshold" {
  // The first rejected depth of each construct. The parser's nesting limit
  // is 150 levels; a constructor or type application counts two levels per
  // source level (75); chains are limited by the AST depth (400 levels, the
  // declaration and implementation included).
  let thresholds : Array[(@lawkit.Construct, Int)] = [
    (Parens, 150),
    (List, 150),
    (Record, 150),
    (Lambda, 150),
    (Let, 150),
    (Case, 150),
    (Type, 150),
    (Pattern, 150),
    (Operators, 399),
    (Cons, 399),
    (Arrow, 399),
    (ElseIf, 150),
    (Access, 399),
    (CtorPattern, 75),
    (TypeApp, 75),
  ]
  @expect.expect(thresholds.map(t => t.0)).to_equal(@lawkit.constructs())
  @expect.expect_all(s => {
    for entry in thresholds {
      let (construct, limit) = entry
      for depth in (limit - 2)..<=(limit + 2) {
        s
        .expect(
          (
            @lawkit.Nesting::{ construct, depth, },
            rejected(@lawkit.nested(construct, depth)),
          ),
        )
        .to_equal((@lawkit.Nesting::{ construct, depth, }, depth >= limit))
      }
    }
  })
}

///|
test "law: deep nesting cut short is reported, never overflowed" {
  // Edges: every construct near both limits, cut at any UTF-16 offset
  // (unclosed openers at every depth, a cut inside a CRLF).
  @quickcheck.check(
    (input : (@lawkit.Nesting, UInt)) => {
      let (n, cut) = input
      let full = n.text()
      let text = full
        .view(
          end_offset=(cut % (full.length() + 1).reinterpret_as_uint()).reinterpret_as_int(),
        )
        .to_owned()
      parse_text(text).diagnostics.iter().all(d => span_in_bounds(text, d.span))
    },
    count=100,
    max_size=24,
    seed=317,
  )
}

///|
test "every literal and comment form holding an edge character parses with diagnostics in bounds" {
  // Exhaustive: every literal and comment form (closed and not) x every edge
  // character x every ending.
  @expect.expect_all(s => {
    for form in @lawkit.literal_forms() {
      for edge in @lawkit.edge_chars() {
        for tail in ["", "\n", "\r\n", " 1\n"] {
          let text = "module M exposing (..)\n\n\nx =\n    " +
            form.0 +
            edge +
            form.1 +
            tail
          let bad = parse_text(text).diagnostics.filter(d => {
            !span_in_bounds(text, d.span)
          })
          s.expect((text.escape(), bad.length())).to_equal((text.escape(), 0))
        }
      }
    }
  })
}

///|
/// Whether every attribute range lies inside the source and every child of
/// an attribute (its name, names and arguments) lies inside the attribute.
fn attributes_hold(text : String, r : @parser.ParseResult) -> Bool {
  let in_source = (range : @ast.Range) => {
    @lawkit.at_or_before(range.start, range.end) &&
    @lawkit.offset_of(text, range.start) is Some(_) &&
    @lawkit.offset_of(text, range.end) is Some(_)
  }
  r.attributes
  .iter()
  .all(group => {
    group.attributes
    .iter()
    .all(a => {
      match a {
        Docs(names~, range~) =>
          in_source(range) &&
          names.iter().all(n => @lawkit.within(n.range, range))
        Attribute(name~, arguments~, range~) =>
          in_source(range) &&
          @lawkit.within(name.range, range) &&
          arguments.iter().all(x => @lawkit.within(x.range, range))
      }
    })
  })
}

///|
test "law: doc attribute children lie inside their attribute" {
  // Edges: see `@lawkit.DocAttributes` (names and values outside the BMP,
  // continued values, LF, CRLF and mixed line ends).
  @quickcheck.check(
    (d : @lawkit.DocAttributes) => {
      let text = d.text()
      let r = parse_text(text)
      errors(r).is_empty() &&
      !r.attributes.is_empty() &&
      attributes_hold(text, r)
    },
    count=100,
    max_size=24,
    seed=331,
  )
}

///|
test "law: an overflow warning in an attribute points at its literal" {
  // Edges: see `@lawkit.DocAttributes`; the literal on the `@` line, on a
  // continuation line, in a list and in an attributes block.
  @quickcheck.check(
    (d : @lawkit.DocAttributes) => {
      let text = d.text()
      let r = parse_text(text)
      r.diagnostics
      .iter()
      .filter(w => w.code == "KR-PARSE-009")
      .all(w => {
        span_in_bounds(text, w.span) &&
        text.view(
          start_offset=w.span.start.offset,
          end_offset=w.span.end.offset,
        ) ==
        @lawkit.overflow_literal()
      })
    },
    count=100,
    max_size=24,
    seed=337,
  )
}

///|
test "a char literal holding a lone high surrogate is reported, not a crash" {
  let text = "module M exposing (..)\n\n\nx =\n    '" +
    @lawkit.units([0xD800, 'a'.to_int()]) +
    "'\n"
  let r = parse_text(text)
  @expect.expect(r.diagnostics.iter().all(d => span_in_bounds(text, d.span))).to_be_true()
}

///|
test "@docs names with characters outside the BMP lie inside their attribute" {
  let text = "module M exposing (..)\n\n\nx =\n    1\n\n\n{-| d\n@docs 𐐨, b\n-}\nf =\n    1\n"
  guard parse_text(text).attributes
    is [{ attributes: [Docs(names~, range~)], .. }] else {
    fail("expected one @docs attribute")
  }
  @expect.expect_all(s => {
    s
    .expect(names.map(n => (n.range.start.column, n.range.end.column)))
    .to_equal([(7, 8), (10, 11)])
    s.expect(range.end.column).to_equal(11)
  })
}

///|
test "a warning on a continued attribute line points at the literal, also after CRLF" {
  for nl in ["\n", "\r\n"] {
    let text = [
      "module M exposing (..)", "", "", "x =", "    1", "", "", "{-| d", "@tag",
      " 9999999999999999999999999999999", "-}", "f =", "    1", "",
    ].join(nl)
    let warnings = parse_text(text).diagnostics.filter(d => {
      d.severity is Warning
    })
    guard warnings is [w] else {
      fail("expected one warning, got \{warnings.length()}")
    }
    let start = text.find("9999").unwrap()
    @expect.expect_all(s => {
      s
      .expect((w.span.start.offset, w.span.end.offset))
      .to_equal((start, start + 31))
      s.expect(span_in_bounds(text, w.span)).to_be_true()
    })
  }
}
