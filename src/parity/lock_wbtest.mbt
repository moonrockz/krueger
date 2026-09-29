///|
/// Golden result for one corpus file.
priv enum Golden {
  Hash(String)
  ParseError
}

///|
/// One line of `tests/corpus/goldens.lock`.
priv struct LockEntry {
  key : String
  source_sha256 : String
  golden : Golden
}

///|
let parse_error_marker : String = "PARSE_ERROR"

///|
/// Parse the lock text: one `<key> <source-sha256> <golden-sha256|PARSE_ERROR>` per line.
fn parse_lock(text : String) -> Array[LockEntry] raise {
  let entries = []
  for raw in text.split("\n") {
    let line = raw.trim().to_owned()
    if line == "" || line.has_prefix("#") {
      continue
    }
    let fields = line
      .split(" ")
      .filter(f => f != "")
      .map(f => f.to_owned())
      .collect()
    guard fields is [key, source_sha256, golden] else {
      fail("goldens.lock: malformed line: \{line}")
    }
    let golden = if golden == parse_error_marker {
      ParseError
    } else {
      Hash(golden)
    }
    entries.push({ key, source_sha256, golden, })
  }
  entries
}

///|
/// Format lock entries sorted by key, one per line.
fn format_lock(entries : Array[LockEntry]) -> String {
  let sorted = entries.copy()
  sorted.sort_by((a, b) => compare_lexical(a.key, b.key))
  let sb = StringBuilder()
  sb.write_string(
    "# <corpus key> <source sha256> <canonical elm-syntax JSON sha256 | PARSE_ERROR>\n",
  )
  for e in sorted {
    let golden = match e.golden {
      Hash(h) => h
      ParseError => parse_error_marker
    }
    sb.write_string("\{e.key} \{e.source_sha256} \{golden}\n")
  }
  sb.to_string()
}

///|
/// Plain lexical order by UTF-16 code unit. `String::compare` orders shorter
/// strings first, which makes the lock hard to read.
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
/// Differences between the lock and the manifest: lock entries whose source
/// hash differs or that the manifest does not list, then manifest files the
/// lock does not list. The lock must be regenerated when this is not empty.
fn source_problems(
  lock : Array[LockEntry],
  manifest : Array[(String, String)],
) -> Array[String] {
  let expected : Map[String, String] = Map::from_array(manifest)
  let problems = []
  let locked : Map[String, Bool] = Map([])
  for entry in lock {
    locked[entry.key] = true
    match expected.get(entry.key) {
      None => problems.push("not in the manifest: \{entry.key}")
      Some(sha) =>
        if sha != entry.source_sha256 {
          problems.push("source hash differs from the manifest: \{entry.key}")
        }
    }
  }
  for m in manifest {
    if !locked.contains(m.0) {
      problems.push("not in the lock: \{m.0}")
    }
  }
  problems
}
