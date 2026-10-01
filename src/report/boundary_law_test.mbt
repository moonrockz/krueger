///|
/// The line numbers the excerpts of `d` must show, in order: for each
/// excerpt, its context's first line to the last line of its context or
/// highlight.
fn expected_gutters(d : @scanner.Diagnostic) -> Array[Int] {
  let out = []
  for block in d.report {
    if block is Excerpt(context~, highlight~) {
      let last = if context.end.line > highlight.end.line {
        context.end.line
      } else {
        highlight.end.line
      }
      for n in context.start.line..<=last {
        out.push(n)
      }
    }
  }
  out
}

///|
/// Whether every diagnostic of `text` renders in all three forms, each
/// excerpt numbering the expected lines and showing those source lines, and
/// the JSON report has one problem per error with its region on the text.
fn renders_in_bounds(text : String) -> Bool {
  let source : @scanner.SourceText = { module_name: None, text, }
  let diags = @parser.parse_module(source, @scanner.DefaultScanner::new()).diagnostics
  let shown = diags
    .iter()
    .all(d => {
      let expected = expected_gutters(d)
      @lawkit.shows_source(
        text,
        @report.render_plain(d, source, "src/M.elm"),
        expected,
      ) &&
      @lawkit.shows_source(
        text,
        @lawkit.strip_ansi(@report.render_terminal(d, source, "src/M.elm")),
        expected,
      )
    })
  let errors = diags.filter(d => d.severity is Error)
  let json_ok = match
    @lawkit.elm_json_problems(
      @report.render_elm_json(diags, source, "src/M.elm"),
    ) {
    Some(problems) =>
      problems.length() == errors.length() &&
      problems
      .iter()
      .zip(errors.iter())
      .all(pair => {
        let ((region, message), d) = pair
        region is Some(r) &&
        @lawkit.range_in_source(text, r) &&
        @lawkit.shows_source(text, message, expected_gutters(d))
      })
    None => false
  }
  shown && json_ok
}

///|
test "law: the renderers never crash and stay inside the source" {
  // Edges: see `@lawkit.ElmText` (diagnostics at the start and end of the
  // text, on the last line with no final newline, after a CRLF, on a lone
  // surrogate, inside unclosed literals and comments).
  @quickcheck.check(
    (t : @lawkit.ElmText) => renders_in_bounds(t.text()),
    count=200,
    max_size=24,
    seed=359,
  )
}

///|
test "every literal and comment form holding an edge character renders inside the source" {
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
          s
          .expect((text.escape(), renders_in_bounds(text)))
          .to_equal((text.escape(), true))
        }
      }
    }
  })
}
