///|
/// The AST of `text`, or `None` when it does not parse without errors.
fn reparse(text : String) -> @ast.File? {
  let result = @parser.parse_module(
    @scanner.SourceText::new(text),
    @scanner.DefaultScanner::new(),
  )
  if result.diagnostics.iter().any(d => d.severity is Error) {
    None
  } else {
    result.ast
  }
}

///|
/// The printed text of `file`, or `None` when the printer raises.
fn printed(file : @ast.File, width? : Int = 120) -> String? {
  try @printer.print_file(file, width~) catch {
    _ => None
  } noraise {
    text => Some(text)
  }
}

///|
/// The file with only its doc comments (module and port documentation):
/// the printer prints those and no other comments.
fn doc_comments_only(file : @ast.File) -> @ast.File {
  {
    ..file,
    comments: file.comments
    .iter()
    .filter(c => c.value.has_prefix("{-|"))
    .collect()[:],
  }
}

///|
test "law: printing a parsed module and parsing it again gives the normalized AST" {
  @quickcheck.check(
    (m : @lawkit.ElmModule) => {
      guard reparse(m.text()) is Some(first) else { return false }
      guard printed(first) is Some(text) else { return false }
      guard reparse(text) is Some(second) else { return false }
      @lawkit.without_ranges(doc_comments_only(@printer.normalize_file(first))) ==
      @lawkit.without_ranges(doc_comments_only(second))
    },
    count=200,
    max_size=24,
    seed=2026,
  )
}

///|
test "law: printing is idempotent" {
  @quickcheck.check(
    (m : @lawkit.ElmModule) => {
      guard reparse(m.text()) is Some(first) else { return false }
      guard printed(first) is Some(once) else { return false }
      guard reparse(once) is Some(second) else { return false }
      printed(second) == Some(once)
    },
    count=200,
    max_size=24,
    seed=2027,
  )
}

///|
test "law: a built AST prints as source that parses to its canonical form" {
  @quickcheck.check(
    (a : @lawkit.ElmAst) => {
      let file = a.file()
      guard printed(file) is Some(text) else { return false }
      guard reparse(text) is Some(second) else { return false }
      @lawkit.without_ranges(canonical_file(file)) ==
      @lawkit.without_ranges(second)
    },
    count=300,
    max_size=20,
    seed=2028,
  )
}

///|
test "law: output ends with one line feed and has no trailing whitespace or tab" {
  @quickcheck.check(
    (a : @lawkit.ElmAst) => {
      guard printed(a.file(), width=40) is Some(text) else { return false }
      text.has_suffix("\n") &&
      !text.has_suffix("\n\n") &&
      !text.contains("\t") &&
      text.split("\n").all(l => !l.has_suffix(" "))
    },
    count=300,
    max_size=20,
    seed=2029,
  )
}

///|
/// The file decoded from `json`, or `None` when it does not decode.
fn decoded(json : String) -> @ast.File? {
  try @ast.decode_file(@json.parse(json)) catch {
    _ => None
  } noraise {
    f => Some(f)
  }
}

///|
test "law: a bad name raises with a path to the node that holds it" {
  @quickcheck.check(
    (a : @lawkit.ElmAst) => {
      let json = @ast.encode_file(a.file()).stringify()
      // The generator names values x; no other name is "x".
      guard json.contains("\"name\":\"x\"") else { return true }
      let bad_json = json.replace_all(
        old="\"name\":\"x\"",
        new="\"name\":\"if\"",
      )
      guard decoded(bad_json) is Some(bad) else { return false }
      let (path, problem) = try @printer.print_file(bad) catch {
        PrintError(path~, problem~) => (path, problem)
      } noraise {
        _ => return false
      }
      problem == InvalidName(Lower, "if") &&
      (match path.resolve(@syntax.NodeRef::File(bad, [][:])) {
        Some(Expression({ value: FunctionOrValue(_, "if"), .. })) => true
        _ => false
      })
    },
    count=200,
    max_size=20,
    seed=2030,
  )
}

///|
test "the built-AST laws reach their success branch" {
  // Every ElmAst prints (all names are valid) and most hold a value x.
  let mut with_x = 0
  let rs = @splitmix.new(seed=7UL)
  for i in 0..<100 {
    let a : @lawkit.ElmAst = @quickcheck.Arbitrary::arbitrary(i % 20, rs)
    if @ast.encode_file(a.file()).stringify().contains("\"name\":\"x\"") {
      with_x += 1
    }
  }
  @expect.expect(with_x > 50).to_be_true()
}

///|
/// The text of `format`, or `None` when it raises.
fn formatted(text : String) -> String? {
  try @printer.format(text) catch {
    _ => None
  } noraise {
    t => Some(t)
  }
}

///|
test "law: format and print_file give the parentheses of normalize_file" {
  // The printer decides the parentheses while it prints (elm-format's
  // rules); `normalize_file` rewrites the AST with the same rules. The
  // generated modules have no comment inside parentheses (`format` keeps
  // such parentheses) and no chain of operators of the same precedence
  // and different directions (`format` keeps it flat).
  @quickcheck.check(
    (m : @lawkit.ElmModule) => {
      guard reparse(m.text()) is Some(first) else { return false }
      guard formatted(m.text()) is Some(text) else { return false }
      guard reparse(text) is Some(second) else { return false }
      guard printed(first) is Some(printed_text) else { return false }
      guard reparse(printed_text) is Some(third) else { return false }
      let expected = @lawkit.without_ranges(
        doc_comments_only(@printer.normalize_file(first)),
      )
      expected == @lawkit.without_ranges(doc_comments_only(second)) &&
      expected == @lawkit.without_ranges(doc_comments_only(third))
    },
    count=200,
    max_size=24,
    seed=2043,
  )
}

///|
test "law: normalize_file is idempotent on modules" {
  @quickcheck.check(
    (m : @lawkit.ElmModule) => {
      guard reparse(m.text()) is Some(file) else { return false }
      let once = @printer.normalize_file(file)
      @printer.normalize_file(once) == once
    },
    count=200,
    max_size=24,
    seed=2044,
  )
}

///|
test "the parenthesis laws reach the rules they check" {
  // Count generated modules whose normalized AST differs from the parsed
  // one: parentheses removed or added.
  let mut changed = 0
  let rs = @splitmix.new(seed=11UL)
  for i in 0..<100 {
    let m : @lawkit.ElmModule = @quickcheck.Arbitrary::arbitrary(i % 24, rs)
    guard reparse(m.text()) is Some(file) else { continue }
    if @lawkit.without_ranges(@printer.normalize_file(file)) !=
      @lawkit.without_ranges(file) {
      changed += 1
    }
  }
  @expect.expect(changed > 20).to_be_true()
}

///|
/// The number of parenthesized expressions and patterns in `file`.
fn paren_count(file : @ast.File) -> Int {
  let json = @ast.encode_file(file).stringify()
  json.split("\"parenthesized\"").count() +
  json.split("\"parentisized\"").count() -
  2
}

///|
test "law: a normalized built AST holds every parenthesis that print_file writes" {
  // Printing `normalize_file(a)` and parsing it again gives its canonical
  // form, and that form has no parentheses that `normalize_file(a)` lacks.
  // (The canonical form also changes negative literals and `let`
  // destructurings of a name, which the parser reads differently.)
  @quickcheck.check(
    (a : @lawkit.ElmAst) => {
      let normalized = @printer.normalize_file(a.file())
      guard printed(normalized) is Some(text) else { return false }
      guard reparse(text) is Some(second) else { return false }
      let canonical = canonical_file(normalized)
      @lawkit.without_ranges(canonical) == @lawkit.without_ranges(second) &&
      paren_count(canonical) == paren_count(normalized)
    },
    count=300,
    max_size=20,
    seed=2045,
  )
}
