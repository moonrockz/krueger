///|
/// Parity check over the pinned corpus, controlled by `KRUEGER_PARITY_MODE`:
///
/// - unset: skip (so `moon test` works without the fetched corpus).
/// - `check`: score krueger against `tests/corpus/goldens.lock`; fail when a
///   count drops below `tests/corpus/baseline.json`.
/// - `ratchet`: score, then write the counts to `tests/corpus/baseline.json`.
/// - `write-lock`: hash the raw oracle output in `.dev/out/goldens/raw` and
///   write `tests/corpus/goldens.lock`.
priv enum Mode {
  Check
  Ratchet
  WriteLock
}

///|
let manifest_path : String = "tests/corpus/manifest.json"

///|
let lock_path : String = "tests/corpus/goldens.lock"

///|
let baseline_path : String = "tests/corpus/baseline.json"

///|
let corpus_dir : String = ".corpus"

///|
let raw_goldens_dir : String = ".dev/out/goldens/raw"

///|
let max_reported_mismatches : Int = 20

///|
let reports_dir : String = "_build/reports/parity"

///|
fn parity_mode() -> Mode? raise {
  match @env.get_env_var("KRUEGER_PARITY_MODE") {
    None | Some("") => None
    Some("check") => Some(Check)
    Some("ratchet") => Some(Ratchet)
    Some("write-lock") => Some(WriteLock)
    Some(other) => fail("unknown KRUEGER_PARITY_MODE: \{other}")
  }
}

///|
/// Corpus keys and source SHA-256 from the manifest, in manifest order.
fn manifest_sources() -> Array[(String, String)] raise {
  guard @json.parse(@fs.read_file_to_string(manifest_path)) is Object(root) &&
    root.get("packages") is Some(Array(packages)) else {
    fail("\{manifest_path}: missing packages array")
  }
  let sources = []
  for p in packages {
    guard p is Object(pkg) &&
      pkg.get("name") is Some(String(name)) &&
      pkg.get("version") is Some(String(version)) &&
      pkg.get("files") is Some(Array(files)) else {
      fail("\{manifest_path}: malformed package entry")
    }
    for f in files {
      guard f is Object(file) &&
        file.get("path") is Some(String(path)) &&
        file.get("sha256") is Some(String(sha)) else {
        fail("\{manifest_path}: malformed file entry in \{name}")
      }
      sources.push(("\{name}@\{version}/\{path}", sha))
    }
  }
  sources
}

///|
/// Read a corpus file after checking it against its expected SHA-256.
fn verified_source(key : String, expected_sha256 : String) -> String raise {
  let path = "\{corpus_dir}/\{key}"
  if !@fs.path_exists(path) {
    fail("missing corpus file \{path}; run mise run corpus:fetch")
  }
  let bytes = @fs.read_file_to_bytes(path)
  if sha256_bytes_hex(bytes) != expected_sha256 {
    fail(
      "corpus file \{path} does not match its pinned hash; run rm -rf .corpus && mise run corpus:fetch",
    )
  }
  @fs.read_file_to_string(path)
}

///|
fn write_lock() -> Unit raise {
  let entries = []
  for source in manifest_sources() {
    let (key, source_sha256) = source
    // The oracle parsed this file, so it must be the pinned source.
    ignore(verified_source(key, source_sha256))
    let raw = "\{raw_goldens_dir}/\{key}"
    let golden = if @fs.path_exists("\{raw}.json") {
      Hash(
        sha256_hex(
          canonical(@json.parse(@fs.read_file_to_string("\{raw}.json"))),
        ),
      )
    } else if @fs.path_exists("\{raw}.error") {
      ParseError
    } else {
      fail("missing oracle output for \{key}; run mise run corpus:goldens")
    }
    entries.push({ key, source_sha256, golden, })
  }
  @fs.write_string_to_file(lock_path, format_lock(entries))
  println("parity: wrote \{lock_path} (\{entries.length()} files)")
}

///|
/// Path of the first difference from the raw elm-syntax JSON, when the raw
/// golden exists locally (`mise run corpus:goldens`).
fn difference_path(key : String, actual : Json) -> String? {
  let raw = "\{raw_goldens_dir}/\{key}.json"
  if !@fs.path_exists(raw) {
    return None
  }
  let expected = try @json.parse(@fs.read_file_to_string(raw)) catch {
    _ => return None
  } noraise {
    j => j
  }
  first_difference(expected, actual).map(d => d.path)
}

///|
/// Mismatch details for one file, printed after the scoreboard.
fn mismatch_report(key : String, actual : Json?) -> String {
  let raw = "\{raw_goldens_dir}/\{key}.json"
  let detail = match actual {
    None => "  krueger produced no AST"
    Some(json) =>
      if @fs.path_exists(raw) {
        let expected = try @json.parse(@fs.read_file_to_string(raw)) catch {
          _ => Json::null()
        } noraise {
          j => j
        }
        match first_difference(expected, json) {
          Some(d) =>
            "  first difference at \{d.path}\n    elm-syntax: \{sexpr(d.expected)}\n    krueger:    \{sexpr(d.actual)}"
          None => "  JSON equal after decoding; hash differs"
        }
      } else {
        "  run mise run corpus:goldens locally for the structural diff"
      }
  }
  "mismatch: \{key}\n\{detail}"
}

///|
/// Score every corpus file in the lock and return one result per file.
fn score() -> Array[FileReport] raise {
  let entries = parse_lock(@fs.read_file_to_string(lock_path))
  let problems = source_problems(entries, manifest_sources())
  if !problems.is_empty() {
    fail(
      "\{lock_path} does not match \{manifest_path} (run mise run corpus:goldens): " +
      problems.join("; "),
    )
  }
  let files = []
  let mismatches = []
  // Scored against elm-syntax, so parsed in its dialect; every file must also
  // parse without errors in the default dialect (elm make accepts the corpus).
  let scoring = @krueger.Dialect::elm_syntax_7_3_9()
  let default_errors = []
  for entry in entries {
    let text = verified_source(entry.key, entry.source_sha256)
    let source = @krueger.SourceText::{ module_name: None, text, }
    let tokenized = @krueger.tokenize(source, dialect=scoring) is Ok(_)
    let result = @krueger.parse_module(source, dialect=scoring)
    // elm make lets only elm/* packages declare infix operators and effect
    // modules.
    let default_dialect = {
      ..@krueger.Dialect::elm_0_19_1(),
      core_package: entry.key.has_prefix("elm/"),
    }
    if dialect_errors(
        entry.key,
        @krueger.parse_module(source, dialect=default_dialect),
      )
      is Some(e) {
      default_errors.push(e)
    }
    let actual = result.ast.map(@ast.encode_file)
    let parsed = actual is Some(_) && result.diagnostics.is_empty()
    // A hash match counts even when krueger also reported diagnostics.
    let matched = match (entry.golden, actual) {
      (Hash(h), Some(json)) => sha256_hex(canonical(json)) == h
      (ParseError, _) => !result.diagnostics.is_empty()
      _ => false
    }
    let diagnostic = result.diagnostics
      .get(0)
      .map(d => {
        code: d.code,
        message: d.message,
        line: d.span.start.line,
        column: d.span.start.column,
      })
    let difference = if matched {
      None
    } else {
      actual.bind(json => difference_path(entry.key, json))
    }
    files.push({
      key: entry.key,
      tokenized,
      parsed,
      matched,
      diagnostic,
      difference,
    })
    if !matched && mismatches.length() < max_reported_mismatches {
      mismatches.push(mismatch_report(entry.key, actual))
    }
  }
  let counts = parity_report(files, None).counts
  println(scoreboard(counts))
  for m in mismatches {
    println(m)
  }
  println(
    "\{@krueger.Dialect::elm_0_19_1().name}: \{default_errors.length()} corpus files with errors",
  )
  if !default_errors.is_empty() {
    fail(
      "corpus files with errors in the default dialect:\n" +
      default_errors.iter().take(10).collect().join("\n"),
    )
  }
  files
}

///|
/// `key:line:column code message` for the first error in `result`, if any.
fn dialect_errors(key : String, result : @krueger.ParseResult) -> String? {
  for d in result.diagnostics {
    if d.severity is Error {
      return Some(
        "\{key}:\{d.span.start.line}:\{d.span.start.column} \{d.code} \{d.message}",
      )
    }
  }
  None
}

///|
fn read_baseline() -> Counts? raise {
  if @fs.path_exists(baseline_path) {
    Some(counts_from_json(@json.parse(@fs.read_file_to_string(baseline_path))))
  } else {
    None
  }
}

///|
/// Create `path` and its parents (like `mkdir -p`).
fn ensure_dir(path : String) -> Unit raise {
  let mut prefix = ""
  for part in path.split("/") {
    prefix = if prefix == "" { part.to_owned() } else { "\{prefix}/\{part}" }
    if !@fs.path_exists(prefix) {
      @fs.create_dir(prefix)
    }
  }
}

///|
/// Write `parity.json`, `parity.xml` (JUnit), `parity.html` and `summary.md`.
fn write_reports(report : ParityReport) -> Unit raise {
  ensure_dir(reports_dir)
  @fs.write_string_to_file(
    "\{reports_dir}/parity.json",
    report_json(report).stringify(indent=2) + "\n",
  )
  @fs.write_string_to_file("\{reports_dir}/parity.xml", report_junit(report))
  @fs.write_string_to_file("\{reports_dir}/parity.html", report_html(report))
  @fs.write_string_to_file("\{reports_dir}/summary.md", report_markdown(report))
  println("parity: wrote reports to \{reports_dir}")
}

///|
test "parity corpus" {
  match parity_mode() {
    None =>
      println(
        "parity: skipped (set KRUEGER_PARITY_MODE or run mise run test:parity)",
      )
    Some(WriteLock) => write_lock()
    Some(mode) => {
      let baseline = read_baseline()
      let report = parity_report(
        score(),
        baseline,
        commit=@env.get_env_var("GITHUB_SHA"),
      )
      write_reports(report)
      match mode {
        Check => {
          if baseline is None {
            fail("missing \{baseline_path}; run mise run parity:ratchet")
          }
          if !report.regressions.is_empty() {
            fail("parity regressed: " + report.regressions.join("; "))
          }
        }
        _ => {
          if baseline is Some(b) && ratchet(report.counts, b) is Err(message) {
            fail("parity ratchet refused to lower the baseline: " + message)
          }
          @fs.write_string_to_file(
            baseline_path,
            counts_to_json(report.counts).stringify(indent=2) + "\n",
          )
          println("parity: wrote \{baseline_path}")
        }
      }
    }
  }
}

///|
test "dialect_errors names the first error" {
  let ok : @krueger.ParseResult = { ast: None, cst: None, diagnostics: [], }
  @expect.expect(dialect_errors("a/B.elm", ok)).to_equal(None)
  let span : @krueger.Span = {
    start: { offset: 0, line: 3, column: 1, },
    end: { offset: 1, line: 3, column: 2, },
  }
  let warning : @krueger.Diagnostic = {
    code: "KR-PARSE-009",
    severity: Warning,
    message: "big",
    span,
    title: "",
    report: [],
  }
  @expect.expect(dialect_errors("a/B.elm", { ..ok, diagnostics: [warning], })).to_equal(
    None,
  )
  let bad : @krueger.Diagnostic = {
    code: "KR-PARSE-004",
    severity: Error,
    message: "boom",
    span,
    title: "",
    report: [],
  }
  @expect.expect(
    dialect_errors("a/B.elm", { ..ok, diagnostics: [warning, bad], }),
  ).to_equal(Some("a/B.elm:3:1 KR-PARSE-004 boom"))
}
