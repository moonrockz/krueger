///|
let manifest_path : String = "../tests/corpus/manifest.json"

///|
let corpus_dir : String = "../.corpus"

///|
let fixtures_dir : String = "../tests/fixtures/parser"

///|
/// The corpus file keys (`<package>@<version>/<path>`), in manifest order.
fn manifest_keys() -> Array[String] raise {
  guard @json.parse(@fs.read_file_to_string(manifest_path)) is Object(root) &&
    root.get("packages") is Some(Array(packages)) else {
    fail("\{manifest_path}: missing packages array")
  }
  let keys = []
  for p in packages {
    guard p is Object(pkg) &&
      pkg.get("name") is Some(String(name)) &&
      pkg.get("version") is Some(String(version)) &&
      pkg.get("files") is Some(Array(files)) else {
      fail("\{manifest_path}: malformed package entry")
    }
    for f in files {
      guard f is Object(file) && file.get("path") is Some(String(path)) else {
        fail("\{manifest_path}: malformed file entry in \{name}")
      }
      keys.push("\{name}@\{version}/\{path}")
    }
  }
  keys
}

///|
/// An input file: its key (a corpus key such as `elm/core@1.0.5/src/Task.elm`,
/// `fixtures/<name>` or `large`) and its text.
priv struct Source {
  key : String
  text : String
}

///|
/// The dialect the parity harness uses for a corpus file in the default
/// dialect: `elm make` lets only `elm/*` and `elm-explorations/*` packages
/// declare effect modules and infix operators.
fn dialect_of(s : Source) -> @krueger.Dialect {
  {
    ..@krueger.Dialect::elm_0_19_1(),
    core_package: s.key.has_prefix("elm/") ||
    s.key.has_prefix("elm-explorations/"),
  }
}

///|
fn source_text(s : Source) -> @scanner.SourceText {
  @scanner.SourceText::new(s.text)
}

///|
fn parse_source(s : Source) -> @parser.ParseResult {
  @krueger.parse_module(source_text(s), dialect=dialect_of(s))
}

///|
/// Every corpus file under `dir`, in manifest order. `mise run
/// corpus:fetch` checks the hashes, so this does not.
fn corpus_sources_in(dir : String) -> Array[Source] raise {
  let sources = []
  for key in manifest_keys() {
    let path = "\{dir}/\{key}"
    if !@fs.path_exists(path) {
      fail("missing corpus file \{path}; run `mise run corpus:fetch`")
    }
    sources.push({ key, text: @fs.read_file_to_string(path), })
  }
  sources
}

///|
fn corpus_sources() -> Array[Source] raise {
  corpus_sources_in(corpus_dir)
}

///|
/// The parser fixtures (`tests/fixtures/parser/*.elm`), sorted by name.
fn fixture_sources() -> Array[Source] raise {
  let names = @fs.read_dir(fixtures_dir)
    .to_owned()
    .filter(n => n.has_suffix(".elm"))
  names.sort()
  let sources = []
  for n in names {
    sources.push({
      key: "fixtures/\{n}",
      text: @fs.read_file_to_string("\{fixtures_dir}/\{n}"),
    })
  }
  sources
}

///|
/// The corpus in `Run` mode; the parser fixtures in `Smoke` mode.
fn sources_for(mode : Mode) -> Array[Source] raise {
  match mode {
    Smoke => fixture_sources()
    Run(_) => corpus_sources()
  }
}

///|
/// A module with `declarations` functions: each has a doc comment with an
/// attribute, a signature, a comment, `let`, `case`, a lambda and a record
/// update. The same text in every run, so runs compare.
fn large_module(declarations : Int) -> String {
  let buf = StringBuilder()
  buf.write_string(
    "module Bench exposing (..)\n\nimport Dict exposing (Dict)\nimport Html exposing (div, text)\n\n\n",
  )
  for i in 0..<declarations {
    buf.write_string(
      "{-| Doc \{i}.\n\n@unit \"EUR\"\n-}\nf\{i} : Int -> { a : Int, b : List String } -> Int\nf\{i} x r =\n    -- a comment\n    let\n        y = case x of\n            0 -> [ 1, 2, 3 ]\n            _ -> List.map (\\z -> z + x * 2) [ x, x + 1 ]\n    in\n    if x > 0 then List.length y + r.a else f\{i} (x - 1) { r | a = r.a + 1 }\n\n\n",
    )
  }
  buf.to_string()
}

///|
test "large_module parses without diagnostics" {
  let result = @krueger.parse_module(@scanner.SourceText::new(large_module(20)))
  @expect.expect_all(s => {
    s.expect(result.diagnostics.length()).to_equal(0)
    s.expect(result.ast.map(f => f.declarations.length())).to_equal(Some(20))
  })
}

///|
test "fixture_sources reads the parser fixtures" {
  let sources = fixture_sources()
  @expect.expect(sources.length() > 5).to_be_true()
}

///|
test "missing corpus names the fix" {
  let message = try corpus_sources_in("../.no-such-corpus") catch {
    e => e.to_string()
  } noraise {
    _ => "no error"
  }
  @expect.expect(message).to_contain("run `mise run corpus:fetch`")
}

///|
test "an elm/* effect module parses in its source's dialect" {
  let src : Source = {
    key: "elm/core@1.0.5/src/Task.elm",
    text: "effect module Task where { command = MyCmd } exposing (Task)\n\n\ntype alias Task x a = Platform.Task x a\n",
  }
  let other : Source = { ..src, key: "someone/pkg@1.0.0/src/Task.elm", }
  @expect.expect_all(s => {
    s.expect(parse_source(src).ast is Some(_)).to_be_true()
    s.expect(parse_source(other).ast is Some(_)).to_be_false()
  })
}
