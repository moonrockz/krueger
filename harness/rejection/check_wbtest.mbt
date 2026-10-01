///|
/// Rejection parity: krueger's accept/reject verdict per dialect against the
/// verdicts recorded from `elm make` 0.19.1 and elm-syntax 7.3.9
/// (`tests/rejection/verdicts.json`, written by `mise run rejection:record`).
///
/// Mismatches must be listed in `tests/rejection/pending.json`; the list only
/// shrinks. `KRUEGER_REJECTION_MODE=write-pending` rewrites it from the
/// current mismatches (use it only when adding fixtures).

///|
let fixtures_dir : String = "../tests/rejection"

///|
let verdicts_path : String = "../tests/rejection/verdicts.json"

///|
let pending_path : String = "../tests/rejection/pending.json"

///|
/// A fixture and dialect whose check does not match the oracle yet.
priv struct Pending {
  fixture : String
  dialect : String
  check : String
} derive(Eq, Debug)

///|
fn sha256_hex(text : String) -> String {
  @hex.encode(Bytes::from_array(@crypto.sha256(@utf8.encode(text))))
}

///|
/// Compare strings by code unit (`String::compare` compares length first).
fn compare_lexical(a : String, b : String) -> Int {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    let c = a.code_unit_at(i).compare(b.code_unit_at(i))
    if c != 0 {
      return c
    }
  }
  a.length().compare(b.length())
}

///|
fn compare_pending(a : Pending, b : Pending) -> Int {
  let by_fixture = compare_lexical(a.fixture, b.fixture)
  if by_fixture != 0 {
    return by_fixture
  }
  let by_dialect = compare_lexical(a.dialect, b.dialect)
  if by_dialect != 0 {
    return by_dialect
  }
  compare_lexical(a.check, b.check)
}

///|
/// Whether krueger accepts `text` in `dialect`: no diagnostic with severity
/// `Error` (warnings do not count).
fn krueger_accepts(text : String, dialect : @krueger.Dialect) -> Bool {
  let source = @krueger.SourceText::{ module_name: Some("Fixture"), text, }
  let result = @krueger.parse_module(source, dialect~)
  !result.diagnostics.iter().any(d => d.severity is Error)
}

///|
/// Built-in dialects checked against the oracle, with their verdict keys.
fn checked_dialects() -> Array[@krueger.Dialect] {
  [@krueger.Dialect::elm_0_19_1(), @krueger.Dialect::elm_syntax_7_3_9()]
}

///|
/// Fixtures whose verdict differs from the oracle's, sorted. `read` returns a
/// fixture's text by its path relative to `tests/rejection`.
fn mismatches(
  verdicts : Json,
  read : (String) -> String raise,
) -> Array[Pending] raise {
  guard verdicts is Object(entries) else {
    fail("\{verdicts_path}: expected an object")
  }
  let found = []
  for fixture, entry in entries {
    guard entry is Object(e) && e.get("sha256") is Some(String(sha256)) else {
      fail("\{verdicts_path}: malformed entry \{fixture}")
    }
    let text = read(fixture)
    if sha256_hex(text) != sha256 {
      fail("\{fixture} changed: run `mise run rejection:record`")
    }
    for dialect in checked_dialects() {
      guard e.get(dialect.name) is Some(Object(v)) &&
        v.get("accepted") is Some(accepted) else {
        fail("\{verdicts_path}: no \{dialect.name} verdict for \{fixture}")
      }
      if krueger_accepts(text, dialect) != (accepted is True) {
        found.push({ fixture, dialect: dialect.name, check: "verdict", })
      }
    }
    if e.get("elm-0.19.1") is Some(elm) &&
      title_mismatch(fixture, text, elm) is Some(p) {
      found.push(p)
    }
  }
  found.sort_by(compare_pending)
  found
}

///|
/// Differences between the fixture files on disk and the recorded verdicts,
/// as messages.
fn unrecorded(verdicts : Json, files : Array[String]) -> Array[String] {
  let recorded = match verdicts {
    Object(entries) => entries.keys().collect()
    _ => []
  }
  let problems = []
  for file in files {
    if !recorded.contains(file) {
      problems.push("\{file} not recorded: run `mise run rejection:record`")
    }
  }
  for key in recorded {
    if !files.contains(key) {
      problems.push("\{key} removed: run `mise run rejection:record`")
    }
  }
  problems
}

///|
/// `.elm` files under `dir`, as paths relative to it.
fn elm_files(dir : String) -> Array[String] raise {
  let found = []
  fn go(rel : String) raise {
    let full = if rel == "" { dir } else { "\{dir}/\{rel}" }
    for entry in @fs.read_dir(full) {
      let child = if rel == "" { entry } else { "\{rel}/\{entry}" }
      if @fs.is_dir("\{dir}/\{child}") {
        go(child)
      } else if child.has_suffix(".elm") {
        found.push(child)
      }
    }
  }

  go("")
  found.sort_by(compare_lexical)
  found
}

///|
fn format_pending(entries : Array[Pending]) -> String {
  let sorted = entries.copy()
  sorted.sort_by(compare_pending)
  let items : Array[Json] = sorted.map(p => {
    "fixture": p.fixture,
    "dialect": p.dialect,
    "check": p.check,
  })
  Json::array(items).stringify(indent=2) + "\n"
}

///|
fn parse_pending(text : String) -> Array[Pending] raise {
  guard @json.parse(text) is Array(items) else {
    fail("\{pending_path}: expected an array")
  }
  let entries = []
  for item in items {
    guard item is Object(o) &&
      o.get("fixture") is Some(String(fixture)) &&
      o.get("dialect") is Some(String(dialect)) &&
      o.get("check") is Some(String(check)) else {
      fail("\{pending_path}: malformed entry")
    }
    entries.push({ fixture, dialect, check, })
  }
  entries.sort_by(compare_pending)
  entries
}

///|
fn describe(p : Pending) -> String {
  "\{p.fixture} [\{p.dialect}] \{p.check}"
}

///|
test "rejection fixtures" {
  let verdicts = @json.parse(@fs.read_file_to_string(verdicts_path))
  let missing = unrecorded(verdicts, elm_files(fixtures_dir))
  if !missing.is_empty() {
    fail(missing.join("\n"))
  }
  let current = mismatches(verdicts, fixture => {
    @fs.read_file_to_string("\{fixtures_dir}/\{fixture}")
  })
  let fixture_count = match verdicts {
    Object(o) => o.length()
    _ => 0
  }
  let mode = @env.get_env_var("KRUEGER_REJECTION_MODE")
  let (rows, messages) = report_rows(verdicts, fixture => {
    @fs.read_file_to_string("\{fixtures_dir}/\{fixture}")
  })
  ensure_dir(reports_dir)
  @fs.write_string_to_file("\{reports_dir}/index.html", report_html(rows))
  let snapshot_problems = check_snapshots(messages, mode is Some("approve"))
  if mode is Some("write-pending") {
    @fs.write_string_to_file(pending_path, format_pending(current))
    println("rejection: wrote \{current.length()} entries to \{pending_path}")
    return
  }
  let pending = if @fs.path_exists(pending_path) {
    parse_pending(@fs.read_file_to_string(pending_path))
  } else {
    []
  }
  println("rejection: \{fixture_count} fixtures | \{current.length()} pending")
  let unexpected = current.filter(p => !pending.contains(p))
  let fixed = pending.filter(p => !current.contains(p))
  let problems = []
  for p in unexpected {
    problems.push("new mismatch: \{describe(p)}")
  }
  for p in fixed {
    problems.push("now matches, remove from \{pending_path}: \{describe(p)}")
  }
  problems.append(snapshot_problems)
  if !problems.is_empty() {
    fail(problems.join("\n"))
  }
}
