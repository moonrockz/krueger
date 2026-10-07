///|
/// At most this many prefixes are cut from one corpus file.
let max_prefixes : Int = 50

///|
/// Whether span `s` lies inside `text`, its ends lie between characters, and
/// its rows and columns agree with its offsets.
fn corpus_span_in_bounds(text : String, s : @krueger.Span) -> Bool {
  0 <= s.start.offset &&
  s.start.offset <= s.end.offset &&
  s.end.offset <= text.length() &&
  @lawkit.between_characters(text, s.start.offset) &&
  @lawkit.between_characters(text, s.end.offset) &&
  @lawkit.positions_of(text, [s.start.offset, s.end.offset]) ==
  [
    Some({ row: s.start.line, column: s.start.column, }),
    Some({ row: s.end.line, column: s.end.column, }),
  ]
}

///|
/// The line numbers the excerpts of `d` must show (see the `report` laws).
fn corpus_expected_gutters(d : @krueger.Diagnostic) -> Array[Int] {
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
/// Laws 8, 9 and 13 on one text: the scanner and the parser report
/// diagnostics inside the source, every diagnostic renders with excerpts that
/// number and show the expected source lines, and the JSON report has one
/// problem per error with its region on the text.
fn prefix_problems(label : String, text : String) -> Array[String] {
  let source = @krueger.SourceText::{ module_name: None, text, }
  let problems = []
  if @krueger.tokenize(source) is Err(errs) &&
    !errs.diagnostics.iter().all(d => corpus_span_in_bounds(text, d.span)) {
    problems.push("\{label}: a scanner diagnostic outside the source")
  }
  let diags = @krueger.parse_module(source).diagnostics
  if !diags.iter().all(d => corpus_span_in_bounds(text, d.span)) {
    problems.push("\{label}: a parser diagnostic outside the source")
  }
  for d in diags {
    let expected = corpus_expected_gutters(d)
    let plain = @krueger.render_plain(d, source, "src/M.elm")
    let terminal = @lawkit.strip_ansi(
      @krueger.render_terminal(d, source, "src/M.elm"),
    )
    if !@lawkit.shows_source(text, plain, expected) ||
      !@lawkit.shows_source(text, terminal, expected) {
      problems.push("\{label}: an excerpt does not show its source lines")
      break
    }
  }
  let errors = diags.filter(d => d.severity is Error)
  let json_ok = match
    @lawkit.elm_json_problems(
      @krueger.render_elm_json(diags, source, "src/M.elm"),
    ) {
    Some(found) =>
      found.length() == errors.length() &&
      found
      .iter()
      .zip(errors.iter())
      .all(pair => {
        let ((region, message), d) = pair
        region is Some(r) &&
        @lawkit.range_in_source(text, r) &&
        @lawkit.shows_source(text, message, corpus_expected_gutters(d))
      })
    None => false
  }
  if !json_ok {
    problems.push("\{label}: the JSON report does not match the errors")
  }
  problems
}

///|
/// The token boundaries of `text`: 0, each token's start and end, one unit
/// into each token longer than one unit (a cut inside a token), and the end
/// of the text; sorted, without duplicates. `None` when the text does not
/// scan.
fn token_boundaries(text : String) -> Array[Int]? {
  let source = @krueger.SourceText::{ module_name: None, text, }
  guard @krueger.tokenize(source) is Ok(ts) else { return None }
  let found = [0, text.length()]
  for t in ts.tokens {
    found.push(t.span.start.offset)
    found.push(t.span.end.offset)
    if t.span.end.offset - t.span.start.offset > 1 {
      found.push(t.span.start.offset + 1)
    }
  }
  found.sort()
  found.dedup()
  Some(found)
}

///|
/// The offsets where `text`'s prefixes are cut: every token boundary, or at
/// most `max_prefixes` of them, evenly spaced (the first and the last
/// included).
fn prefix_cuts(boundaries : Array[Int]) -> Array[Int] {
  if boundaries.length() <= max_prefixes {
    return boundaries
  }
  Array::makei(max_prefixes, i => {
    boundaries[i * (boundaries.length() - 1) / (max_prefixes - 1)]
  })
}

///|
/// Law 12 on a corpus file: decoding its encoded AST (through JSON text)
/// gives it back, encoding that again gives the same JSON text, and exact
/// Ints give the same JSON text too.
fn round_trip_problems(key : String, text : String) -> Array[String] {
  let result = @krueger.parse_module(
    @krueger.SourceText::{ module_name: None, text, },
    dialect=@krueger.Dialect::elm_syntax_7_3_9(),
  )
  guard result.ast is Some(file) else { return ["\{key}: no AST"] }
  let json = @ast.encode_file(file).stringify()
  let exact = @ast.encode_file_with(file, exact_ints=true).stringify()
  // The corpus has no Int literal above 2^53, so exact Ints change no byte.
  let same = exact == json &&
    (try @ast.decode_file(@json.parse(json)) catch {
      _ => false
    } noraise {
      back => back == file && @ast.encode_file(back).stringify() == json
    })
  if same {
    []
  } else {
    ["\{key}: decoding the encoded AST does not give it back"]
  }
}

///|
/// Boundary laws over the corpus: the AST round trip (law 12) on every file,
/// and laws 8, 9 and 13 on prefixes cut at token boundaries. Runs in the
/// parity modes that score.
test "boundary laws over the corpus" {
  match parity_mode() {
    None
    | Some(WriteLock)
    | Some(WritePrinted)
    | Some(WriteFormatted)
    | Some(CheckFormat) => ()
    Some(_) => {
      let problems = []
      let mut files = 0
      let mut prefixes = 0
      for source in manifest_sources() {
        let (key, sha256) = source
        let text = verified_source(key, sha256)
        problems.append(round_trip_problems(key, text))
        guard token_boundaries(text) is Some(boundaries) else {
          problems.push("\{key}: does not scan")
          continue
        }
        for cut in prefix_cuts(boundaries) {
          problems.append(
            prefix_problems(
              "\{key} (prefix \{cut})",
              text.view(end_offset=cut).to_owned(),
            ),
          )
          prefixes = prefixes + 1
        }
        files = files + 1
      }
      println("prefixes: \{files} files, \{prefixes} prefixes")
      if !problems.is_empty() {
        fail(
          "boundary laws: \{problems.length()} problems:\n" +
          problems.iter().take(10).collect().join("\n"),
        )
      }
    }
  }
}

///|
test "token boundaries include token ends, a cut inside each token and the end" {
  let text = "module M exposing (..)\nx = 1\n-- tail"
  @expect.expect_all(s => {
    s
    .expect(token_boundaries(text))
    .to_equal(
      Some([
        0, 1, 6, 7, 8, 9, 10, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 36,
      ]),
    )
    s.expect(token_boundaries("x = '")).to_equal(None)
    s.expect(prefix_cuts([0, 5, 9])).to_equal([0, 5, 9])
    let many = Array::makei(101, i => i)
    let cuts = prefix_cuts(many)
    s.expect((cuts.length(), cuts[0], cuts[49])).to_equal((50, 0, 100))
  })
}
