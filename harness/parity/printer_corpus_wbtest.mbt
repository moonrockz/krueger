///|
let printer_lock_path : String = "../tests/printer/elm_format.lock"

///|
let printer_pending_path : String = "../tests/printer/pending.json"

///|
let printed_dir : String = "../.dev/out/printed"

///|
/// The default dialect for a corpus file: elm make lets only elm/* and
/// elm-explorations/* packages declare infix operators and effect modules.
fn corpus_dialect(key : String) -> @krueger.Dialect {
  {
    ..@krueger.Dialect::elm_0_19_1(),
    core_package: key.has_prefix("elm/") || key.has_prefix("elm-explorations/"),
  }
}

///|
/// The file with only its doc comments in `comments`: the printer prints
/// doc comments and drops regular comments.
fn printer_doc_comments_only(file : @ast.File) -> @ast.File {
  {
    ..file,
    comments: file.comments
    .iter()
    .filter(c => c.value.has_prefix("{-|"))
    .collect()[:],
  }
}

///|
/// The printed text of one corpus file (when it prints), and the problems
/// of the printer laws on it: lossless CST (LF and CRLF), round trip
/// through printing, idempotence.
fn printer_check(key : String, text : String) -> (String?, Array[String]) {
  let problems = []
  let dialect = corpus_dialect(key)
  let parse = (t : String) => {
    @krueger.parse_module(@krueger.SourceText::new(t), dialect~)
  }
  for variant in [text, text.replace_all(old="\n", new="\r\n")] {
    match parse(variant).cst {
      Some(cst) =>
        if cst.to_source() != variant {
          problems.push("\{key}: to_source differs from the source")
        }
      None => problems.push("\{key}: no CST")
    }
  }
  guard parse(text).ast is Some(first) else {
    problems.push("\{key}: no AST")
    return (None, problems)
  }
  let printed = try @krueger.print_file(first, dialect~) catch {
    e => {
      problems.push("\{key}: print_file raised \{@debug.to_string(e)}")
      return (None, problems)
    }
  } noraise {
    t => t
  }
  let again = parse(printed)
  // The location in `e` is in the printed source, not in the file.
  if dialect_errors("printed", again) is Some(e) {
    problems.push("\{key}: the printed source does not parse: \{e}")
  }
  match again.ast {
    Some(second) => {
      if @lawkit.without_ranges(printer_doc_comments_only(first)) !=
        @lawkit.without_ranges(printer_doc_comments_only(second)) {
        problems.push("\{key}: the AST changes through printing")
      }
      let reprinted = try @krueger.print_file(second, dialect~) catch {
        _ => None
      } noraise {
        t => Some(t)
      }
      if reprinted != Some(printed) {
        problems.push("\{key}: printing is not idempotent")
      }
    }
    None => problems.push("\{key}: the printed source has no AST")
  }
  (Some(printed), problems)
}

///|
/// `<key> -> (sha256, stable)` from the lock.
fn read_printer_lock() -> Map[String, (String, Bool)] raise {
  if !@fs.path_exists(printer_lock_path) {
    fail("missing \{printer_lock_path}; run mise run printer:record")
  }
  guard @json.parse(@fs.read_file_to_string(printer_lock_path)) is Object(root) else {
    fail("\{printer_lock_path}: not a JSON object")
  }
  let lock = Map([])
  for key, entry in root {
    guard entry is Object(e) &&
      e.get("sha256") is Some(String(hash)) &&
      e.get("elm_format") is Some(String(verdict)) else {
      fail("\{printer_lock_path}: malformed entry \{key}")
    }
    lock[key] = (hash, verdict == "stable")
  }
  lock
}

///|
fn read_printer_pending() -> Array[String] raise {
  guard @json.parse(@fs.read_file_to_string(printer_pending_path))
    is Array(items) else {
    fail("\{printer_pending_path}: not a JSON array")
  }
  let keys = []
  for item in items {
    guard item is String(key) else {
      fail("\{printer_pending_path}: not a string")
    }
    keys.push(key)
  }
  keys
}

///|
fn parent_dir(path : String) -> String {
  let parts = path.split("/").map(p => p.to_owned()).collect()
  parts[:parts.length() - 1].iter().collect().join("/")
}

///|
/// Print every corpus file to `printed_dir`. The law problems do not stop
/// the run (`test:parity` reports them); the first 20 are printed.
fn write_printed() -> Unit raise {
  let mut count = 0
  let problems = []
  for source in manifest_sources() {
    let (key, sha256) = source
    let (printed, found) = printer_check(key, verified_source(key, sha256))
    problems.append(found)
    if printed is Some(text) {
      let path = "\{printed_dir}/\{key}"
      ensure_dir(parent_dir(path))
      @fs.write_string_to_file(path, text)
      count += 1
    }
  }
  println("printer: wrote \{count} printed files to \{printed_dir}")
  for problem in problems.iter().take(20) {
    println("printer: \{problem}")
  }
  if !problems.is_empty() {
    println("printer: \{problems.length()} law problems")
  }
}

///|
fn check_printer_corpus() -> Unit raise {
  let lock = read_printer_lock()
  let pending = read_printer_pending()
  let problems = []
  let changed = []
  let mut stable = 0
  let mut total = 0
  for source in manifest_sources() {
    let (key, sha256) = source
    total += 1
    let (printed, found) = printer_check(key, verified_source(key, sha256))
    problems.append(found)
    guard printed is Some(text) else { continue }
    match lock.get(key) {
      None =>
        problems.push(
          "\{key}: not in \{printer_lock_path}; run mise run printer:record",
        )
      Some((hash, ok)) =>
        if hash != sha256_hex(text) {
          problems.push(
            "\{key}: the printed text changed after the lock; run mise run printer:record",
          )
        } else if ok {
          stable += 1
        } else {
          changed.push(key)
        }
    }
  }
  for key in changed {
    if !pending.contains(key) {
      problems.push(
        "\{key}: elm-format changes the printed text, and the file is not in \{printer_pending_path}",
      )
    }
  }
  for key in pending {
    if !changed.contains(key) {
      problems.push(
        "\{key}: listed in \{printer_pending_path}, but elm-format accepts it now; remove it",
      )
    }
  }
  println(
    "printer: \{stable} of \{total} corpus files are stable under elm-format 0.8.7",
  )
  if !problems.is_empty() {
    fail("printer corpus:\n" + problems.iter().take(20).collect().join("\n"))
  }
}

///|
test "printer corpus" {
  match parity_mode() {
    None | Some(WriteLock) => ()
    Some(WritePrinted) => write_printed()
    Some(_) => check_printer_corpus()
  }
}

///|
test "parent_dir drops the last path segment" {
  @expect.expect(
    parent_dir("../.dev/out/printed/elm/core@1.0.5/src/Basics.elm"),
  ).to_equal("../.dev/out/printed/elm/core@1.0.5/src")
}
