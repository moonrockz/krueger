///|
let format_lock_path : String = "../tests/format/elm_format.lock"

///|
let format_pending_path : String = "../tests/format/pending.json"

///|
let format_out_dir : String = "../.dev/out/format"

///|
let elm_format_tests_dir : String = "../.corpus/elm-format"

///|
let format_reports_dir : String = "../_build/reports/format"

///|
/// The `.elm` files below `dir` as paths relative to `dir`, sorted. A
/// missing directory has no files.
fn list_elm_files(dir : String) -> Array[String] raise {
  let found = []
  if !@fs.path_exists(dir) {
    return found
  }
  let stack = [""]
  while stack.pop() is Some(rel) {
    let full = if rel == "" { dir } else { "\{dir}/\{rel}" }
    for entry in @fs.read_dir(full) {
      let child = if rel == "" { entry } else { "\{rel}/\{entry}" }
      if @fs.is_dir("\{dir}/\{child}") {
        stack.push(child)
      } else if child.has_suffix(".elm") {
        found.push(child)
      }
    }
  }
  found.sort()
  found
}

///|
/// Every formatter source: the corpus files, then the elm-format test
/// files, as `(key, text, sha256 of the source)`.
fn format_sources() -> Array[(String, String, String)] raise {
  let out = []
  for source in manifest_sources() {
    let (key, sha256) = source
    out.push((key, verified_source(key, sha256), sha256))
  }
  for path in list_elm_files(elm_format_tests_dir) {
    let file = "\{elm_format_tests_dir}/\{path}"
    out.push(
      (
        "elm-format/\{path}",
        @fs.read_file_to_string(file),
        sha256_bytes_hex(@fs.read_file_to_bytes(file)),
      ),
    )
  }
  out
}

///|
/// The formatted text, or why there is none: `rejected: <title>` when
/// krueger rejects the source, `raised: <error>` when it parses but cannot
/// print.
fn format_one(key : String, text : String) -> Result[String, String] {
  try @krueger.format(text, dialect=corpus_dialect(key)) catch {
    ParseFailed(diagnostics) =>
      Err(
        "rejected: " +
        (match diagnostics.get(0) {
          Some(d) => d.title
          None => "no diagnostic"
        }),
      )
    e => Err("raised: " + @debug.to_string(e))
  } noraise {
    t => Ok(t)
  }
}

///|
/// Write krueger's output for every source to `format_out_dir/actual` and
/// the verdicts to `keys.json`, for `mise run format:record`.
fn write_formatted() -> Unit raise {
  let keys = []
  let mut written = 0
  for source in format_sources() {
    let (key, text, sha256) = source
    let verdict = match format_one(key, text) {
      Ok(output) => {
        let path = "\{format_out_dir}/actual/\{key}"
        ensure_dir(parent_dir(path))
        @fs.write_string_to_file(path, output)
        written += 1
        "parsed"
      }
      Err(reason) =>
        if reason.has_prefix("rejected") {
          reason
        } else {
          "parsed"
        }
    }
    keys.push(
      Json::object({
        "key": key.to_json(),
        "source": sha256.to_json(),
        "krueger": verdict.to_json(),
      }),
    )
  }
  ensure_dir(format_out_dir)
  @fs.write_string_to_file(
    "\{format_out_dir}/keys.json",
    Json::array(keys).stringify(indent=2) + "\n",
  )
  println(
    "format: wrote \{written} formatted files to \{format_out_dir}/actual",
  )
}

///|
priv struct FormatLockEntry {
  source : String
  expected : String?
  skipped : String?
}

///|
fn read_format_lock() -> Map[String, FormatLockEntry] raise {
  if !@fs.path_exists(format_lock_path) {
    fail("missing \{format_lock_path}; run mise run format:record")
  }
  guard @json.parse(@fs.read_file_to_string(format_lock_path)) is Object(root) else {
    fail("\{format_lock_path}: not a JSON object")
  }
  let lock = Map([])
  for key, entry in root {
    guard entry is Object(e) && e.get("source") is Some(String(source)) else {
      fail("\{format_lock_path}: malformed entry \{key}")
    }
    lock[key] = {
      source,
      expected: match e.get("expected") {
        Some(String(h)) => Some(h)
        _ => None
      },
      skipped: match e.get("skipped") {
        Some(String(r)) => Some(r)
        _ => None
      },
    }
  }
  lock
}

///|
fn read_format_pending() -> Array[String] raise {
  guard @json.parse(@fs.read_file_to_string(format_pending_path))
    is Array(items) else {
    fail("\{format_pending_path}: not a JSON array")
  }
  let keys = []
  for item in items {
    guard item is String(key) else {
      fail("\{format_pending_path}: not a string")
    }
    keys.push(key)
  }
  keys
}

///|
fn clip(line : String) -> String {
  if line.length() > 100 {
    line.view(end_offset=100).to_owned() + "..."
  } else {
    line
  }
}

///|
/// The first line where two texts differ, as `line N: expected ...; actual ...`.
fn first_text_difference(expected : String, actual : String) -> String {
  let e = expected.split("\n").map(l => l.to_owned()).collect()
  let a = actual.split("\n").map(l => l.to_owned()).collect()
  let n = if e.length() > a.length() { e.length() } else { a.length() }
  for i in 0..<n {
    let el = if i < e.length() { Some(e[i]) } else { None }
    let al = if i < a.length() { Some(a[i]) } else { None }
    if el != al {
      return "line \{i + 1}: expected \{clip(el.unwrap_or("<end>"))}; actual \{clip(al.unwrap_or("<end>"))}"
    }
  }
  "no difference"
}

///|
/// Counts of one source set.
priv struct SetCount {
  mut matched : Int
  mut total : Int
  skipped : Map[String, Int]
}

///|
fn SetCount::new() -> SetCount {
  { matched: 0, total: 0, skipped: Map([]), }
}

///|
fn SetCount::to_json(self : SetCount) -> Json {
  let skipped : Map[String, Json] = Map([])
  for reason, n in self.skipped {
    skipped[reason] = n.to_json()
  }
  {
    "matched": self.matched.to_json(),
    "total": self.total.to_json(),
    "skipped": Json::object(skipped),
  }
}

///|
fn SetCount::markdown(self : SetCount, name : String) -> String {
  let skipped = self.skipped.iter().map(p => "\{p.1} (\{p.0})").collect()
  "| \{name} | \{self.matched} | \{self.total} | \{skipped.join("; ")} |\n"
}

///|
fn check_format_corpus() -> Unit raise {
  let lock = read_format_lock()
  let pending = read_format_pending()
  let problems = []
  let mismatched = []
  let details : Map[String, String] = Map([])
  let unchanged = SetCount::new()
  let changed = SetCount::new()
  let tests = SetCount::new()
  let known = Map([])
  for source in format_sources_unverified() {
    known[source] = true
  }
  for key in known.keys() {
    if !lock.contains(key) {
      problems.push(
        "\{key}: not in \{format_lock_path}; run mise run format:record",
      )
    }
  }
  let keys = lock.keys().collect()
  keys.sort()
  for key in keys {
    let entry = lock[key]
    let file = "\{corpus_dir}/\{key}"
    if !@fs.path_exists(file) {
      problems.push(
        "\{key}: missing \{file}; run mise run corpus:fetch and format:fetch",
      )
      continue
    }
    if sha256_bytes_hex(@fs.read_file_to_bytes(file)) != entry.source {
      problems.push(
        "\{key}: the source changed after the lock; run mise run format:record",
      )
      continue
    }
    let set = if key.has_prefix("elm-format/") {
      tests
    } else if entry.expected is Some(h) && h == entry.source {
      unchanged
    } else {
      changed
    }
    if entry.skipped is Some(reason) {
      set.skipped[reason] = set.skipped.get(reason).unwrap_or(0) + 1
      continue
    }
    guard entry.expected is Some(expected) else { continue }
    set.total += 1
    let (actual_hash, actual_text) = match
      format_one(key, @fs.read_file_to_string(file)) {
      Ok(output) => (sha256_hex(output), output)
      Err(reason) => ("", reason)
    }
    if actual_hash == expected {
      set.matched += 1
    } else {
      mismatched.push(key)
      let path = "\{format_out_dir}/expected/\{key}"
      if @fs.path_exists(path) {
        details[key] = first_text_difference(
          @fs.read_file_to_string(path),
          actual_text,
        )
      }
    }
  }
  for key in mismatched {
    if !pending.contains(key) {
      problems.push(
        "\{key}: krueger's output differs from elm-format's, and the file is not in \{format_pending_path}",
      )
    }
  }
  for key in pending {
    if !mismatched.contains(key) {
      problems.push(
        "\{key}: listed in \{format_pending_path}, but the output matches elm-format now; remove it",
      )
    }
  }
  ensure_dir(format_reports_dir)
  let summary = "### Formatter parity with elm-format 0.8.7\n\n| Source set | Matched | Total | Skipped |\n|---|---|---|---|\n" +
    unchanged.markdown("Corpus files elm-format accepts unchanged") +
    changed.markdown("Corpus files elm-format changes") +
    tests.markdown("elm-format test files")
  @fs.write_string_to_file("\{format_reports_dir}/summary.md", summary)
  @fs.write_string_to_file(
    "\{format_reports_dir}/format.json",
    Json::object({
      "corpus_unchanged": unchanged.to_json(),
      "corpus_changed": changed.to_json(),
      "elm_format_tests": tests.to_json(),
      "pending": pending.length().to_json(),
    }).stringify(indent=2) +
    "\n",
  )
  println(summary)
  // Regressions (mismatches not in the pending list) come first, so the
  // budget does not fill with known differences.
  let shown = mismatched.filter(k => !pending.contains(k))
  shown.append(mismatched.filter(k => pending.contains(k)))
  let mut count = 0
  for key in shown {
    if count >= max_reported_mismatches {
      break
    }
    if details.get(key) is Some(d) {
      println("format: \{key}: \{d}")
      count += 1
    }
  }
  if !problems.is_empty() {
    fail("format corpus:\n" + problems.iter().take(20).collect().join("\n"))
  }
}

///|
/// The keys of all formatter sources, without reading the files.
fn format_sources_unverified() -> Array[String] raise {
  let keys = manifest_sources().map(s => s.0)
  for path in list_elm_files(elm_format_tests_dir) {
    keys.push("elm-format/\{path}")
  }
  keys
}

///|
test "format corpus" {
  match parity_mode() {
    Some(WriteFormatted) => write_formatted()
    Some(CheckFormat) => check_format_corpus()
    _ => ()
  }
}
