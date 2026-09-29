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
fn score() -> Counts raise {
  let entries = parse_lock(@fs.read_file_to_string(lock_path))
  let problems = source_problems(entries, manifest_sources())
  if !problems.is_empty() {
    fail(
      "\{lock_path} does not match \{manifest_path} (run mise run corpus:goldens): " +
      problems.join("; "),
    )
  }
  let mut tokenized = 0
  let mut parsed = 0
  let mut matched = 0
  let reports = []
  for entry in entries {
    let text = verified_source(entry.key, entry.source_sha256)
    let source = @krueger.SourceText::{ module_name: None, text, }
    if @krueger.tokenize(source) is Ok(_) {
      tokenized += 1
    }
    let result = @krueger.parse_module(source)
    let actual = result.ast.map(@ast.encode_file)
    if actual is Some(_) && result.diagnostics.is_empty() {
      parsed += 1
    }
    let is_match = match (entry.golden, actual) {
      (Hash(h), Some(json)) => sha256_hex(canonical(json)) == h
      (ParseError, _) => !result.diagnostics.is_empty()
      _ => false
    }
    if is_match {
      matched += 1
    } else if reports.length() < max_reported_mismatches {
      reports.push(mismatch_report(entry.key, actual))
    }
  }
  let counts = { files: entries.length(), tokenized, parsed, matched, }
  println(scoreboard(counts))
  for r in reports {
    println(r)
  }
  counts
}

///|
test "parity corpus" {
  match parity_mode() {
    None =>
      println(
        "parity: skipped (set KRUEGER_PARITY_MODE or run mise run test:parity)",
      )
    Some(WriteLock) => write_lock()
    Some(Ratchet) => {
      let counts = score()
      if @fs.path_exists(baseline_path) {
        let baseline = counts_from_json(
          @json.parse(@fs.read_file_to_string(baseline_path)),
        )
        if ratchet(counts, baseline) is Err(message) {
          fail("parity ratchet refused to lower the baseline: " + message)
        }
      }
      @fs.write_string_to_file(
        baseline_path,
        counts_to_json(counts).stringify(indent=2) + "\n",
      )
      println("parity: wrote \{baseline_path}")
    }
    Some(Check) => {
      let counts = score()
      let baseline = counts_from_json(
        @json.parse(@fs.read_file_to_string(baseline_path)),
      )
      let found = regressions(counts, baseline)
      if !found.is_empty() {
        fail("parity regressed: " + found.join("; "))
      }
    }
  }
}
