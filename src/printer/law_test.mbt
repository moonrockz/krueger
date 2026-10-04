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
