# Changelog

All notable changes to `moonrockz/krueger` are listed here, newest first.
Versions follow [Semantic Versioning](https://semver.org); while the version
is 0.x, a minor release can contain breaking changes.

<!-- git-cliff: end of header -->

## [0.8.0] - 2026-10-16

<!-- Highlights: replace this comment with a few sentences on what this release brings. -->

### 🚀 Features

- *(release)* Open the release PR as a draft; refresh marks it ready ([#58](https://github.com/moonrockz/krueger/pull/58)) by @DamianReeves

### ⚡ Performance

- *(syntax)* Fast tokens_in, node_path and children() of wide nodes ([#60](https://github.com/moonrockz/krueger/pull/60)) by @DamianReeves
- *(syntax)* Struct index keys and cached root children in Tree ([#61](https://github.com/moonrockz/krueger/pull/61)) by @DamianReeves

### 🚜 Refactoring

- *(syntax)* Call EventSource::next explicitly in EventReader::iter ([#59](https://github.com/moonrockz/krueger/pull/59)) by @DamianReeves

**Full changelog**: https://github.com/moonrockz/krueger/compare/v0.7.0...v0.8.0

## [0.7.0] - 2026-10-16

The parser's fixed depth limits are replaced by one budget that you set: pass `fuel` to `parse_module`, `parse_tokens`, `format` or `format_parsed` (default `DEFAULT_FUEL`, 1200, which keeps the limits of 0.6). A nesting refusal now has its own code, `KR-PARSE-010`, and carries the fuel and the walk that ran out in the new `Diagnostic.detail` field, so tools can tell "too deep" from "malformed" without reading the message. The AST encoder and decoder and the pattern and type printing use explicit stacks: a 2000-level AST encodes, decodes and prints on wasm, wasm-gc, js and native, and a left-associative operator chain or a record access chain has no limit. The new cookbook article "Set the nesting budget" explains the fuel and the stack setting of each target.

### ⚠️ Breaking changes

- *(scanner)* `Diagnostic` has a new field `detail`. Code that builds a `Diagnostic` literal must add `detail: None`. ([#54](https://github.com/moonrockz/krueger/pull/54))
- *(printer)* `PrintProblem::TooDeep` is removed: the printer prints an AST of any depth. Remove `TooDeep` from matches on `PrintProblem`. ([#54](https://github.com/moonrockz/krueger/pull/54))
- *(parser)* A `::`, `->` or right-associative operator chain is refused after 596 steps (was 399), and a left-associative operator chain or a record access chain is no longer refused. A refusal is `KR-PARSE-010`, not the declaration's `KR-PARSE-003`, `004` or `008`. ([#54](https://github.com/moonrockz/krueger/pull/54))

### 🚀 Features

- *(parser)* [**breaking**] One caller-set fuel, KR-PARSE-010 for nesting refusals, stack-safe encoder and printer ([#54](https://github.com/moonrockz/krueger/pull/54)) by @DamianReeves
- *(ast)* Decode with an explicit stack, not recursion ([#55](https://github.com/moonrockz/krueger/pull/55)) by @DamianReeves

### 🐛 Bug fixes

- *(lawkit)* Strip ranges without recursion; test deep comments in format ([#56](https://github.com/moonrockz/krueger/pull/56)) by @DamianReeves

**Full changelog**: https://github.com/moonrockz/krueger/compare/v0.6.0...v0.7.0

## [0.6.0] - 2026-10-14

This is a maintenance release. The parser, printer and formatter give the same output as in 0.5.0, and the public API does not change. krueger is now built and tested with MoonBit 0.10.15. It now depends on `moonrockz/pretty` 0.1.1, `moonbit-community/cmark` 0.4.12 and `moonrockz/expect` 0.6.1. The release process also improved: `release:refresh` updates the release pull request body, `release:plan` stops a release that has no highlights, and `release:prepare` warns about breaking commits without a `BREAKING CHANGE:` footer.

### 🚀 Features

- *(release)* Release:refresh updates the release PR body; plan needs highlights ([#46](https://github.com/moonrockz/krueger/pull/46)) by @DamianReeves
- *(release)* Warn about breaking commits without a BREAKING CHANGE footer ([#47](https://github.com/moonrockz/krueger/pull/47)) by @DamianReeves

### 🏗️ Build and CI

- Add ci-ok job as the single required check ([#48](https://github.com/moonrockz/krueger/pull/48)) by @DamianReeves
- *(deps)* Upgrade MoonBit toolchain to 0.10.15, moonrockz packages and cmark ([#49](https://github.com/moonrockz/krueger/pull/49)) by @DamianReeves

**Full changelog**: https://github.com/moonrockz/krueger/compare/v0.5.0...v0.6.0

## [0.5.0] - 2026-10-07

krueger can now format Elm source. `format(source)` gives the same bytes
as elm-format 0.8.7 and keeps every comment in its place. A comment that
cannot be placed raises an error; it is never dropped. `Layout::Width(n)`
gives the width-fit layout of `print_file`, with comments.
`format_parsed` formats a parse result that you already have. On the
pinned corpus, 297 of 299 files that elm-format leaves unchanged come out
byte for byte, and 124 of 135 other files match elm-format's output.

The formatter applies elm-format's rewrites, and `print_file` applies them
too, through the new public `normalize_file`:
- the exposing list is grouped by the `@docs` lines;
- imports are sorted and merged;
- parentheses follow elm-format;
- literals use elm-format's forms;
- doc comments are formatted as elm-format formats them, Elm code blocks
  included.

The doc comment Markdown support is the new package `src/markdown`, on
`moonbit-community/cmark`.

### ⚠️ Breaking changes

- *(printer)* `print_file` now applies `normalize_file`, so its output changes for existing ASTs: exposing lists, imports, parentheses and doc comments follow elm-format. The round trip is now `parse(print_file(ast)) == normalize_file(ast)`, without ranges ([#44](https://github.com/moonrockz/krueger/pull/44))
- *(printer)* `PrintProblem` has a new variant, `UnplacedComment`. A `match` that lists every case must handle it ([#44](https://github.com/moonrockz/krueger/pull/44))
- `moonbit-community/cmark` is a new dependency ([#44](https://github.com/moonrockz/krueger/pull/44))

### 🚀 Features

- *(printer)* [**breaking**] Elm formatter with elm-format 0.8.7 parity: `format`, `format_parsed`, `Layout`, `normalize_file` and `src/markdown` ([#44](https://github.com/moonrockz/krueger/pull/44)) by @DamianReeves

**Full changelog**: https://github.com/moonrockz/krueger/compare/v0.4.0...v0.5.0

## [0.4.0] - 2026-10-02

krueger can now write Elm source. The new printer prints an AST as Elm code
in the elm-format 0.8.7 layout: `print_file`, `print_declaration`,
`print_expression`, `print_pattern` and `print_type_annotation`. It fits
lines to a width of 120 by default and adds only the parentheses that the
parser needs. When an AST cannot print as valid Elm, the printer raises
`PrintError` with a `NodePath` to the bad node. `ModuleCst::to_source()`
prints a concrete syntax tree back to its source text, byte for byte. The
layout engine is a new dependency,
[moonrockz/pretty](https://github.com/moonrockz/pretty): a Wadler-style
engine in its own repository and module. For property tests, lawkit adds the
`ElmAst` generator and `without_ranges`.

The AST printer prints doc comments, but it does not print regular comments
yet. On the parity corpus, the output for 150 of 363 files is identical to
the elm-format output. A formatter that keeps all comments is future work.

### ⚠️ Breaking changes

- `ModuleCst` has a new field, `trivia`: the whitespace and comments of a text that has no tokens. Code that builds a `ModuleCst` must set it (`[]` when there are tokens) ([#41](https://github.com/moonrockz/krueger/pull/41))

### 🚀 Features

- [**breaking**] Elm printer: AST printer and lossless CST print ([#41](https://github.com/moonrockz/krueger/pull/41)) by @DamianReeves

### 🏗️ Build and CI

- Use moonrockz/pretty 0.1.0 from mooncakes.io ([#42](https://github.com/moonrockz/krueger/pull/42)) by @DamianReeves

**Full changelog**: https://github.com/moonrockz/krueger/compare/v0.3.0...v0.4.0

## [0.3.0] - 2026-10-01

The syntax tree answers field and position questions faster, and it has more ways to walk a file. `Tree::field_of` and `Tree::step` read a parent index built once. `TreeCursor::goto_node_at` moves to the node at a position, `EventReader::iter` yields the remaining events, and `NodePath::from_steps` and `NodePath::append` build a path. `SourceText::new` makes a source text from a string. A cookbook of tested articles shows the common tasks: reports, traversal, editor queries and an AST explorer.

### 🚀 Features

- *(release)* A release:status check and a release-manager skill ([#35](https://github.com/moonrockz/krueger/pull/35)) by @DamianReeves
- Tested API examples, a cookbook and SourceText::new ([#36](https://github.com/moonrockz/krueger/pull/36)) by @DamianReeves
- *(syntax)* TreeCursor::goto_node_at, EventReader::iter and NodePath helpers; faster children() ([#38](https://github.com/moonrockz/krueger/pull/38)) by @DamianReeves
- *(bench)* Benchmarks with a saved history, an HTML report and a manual workflow ([#39](https://github.com/moonrockz/krueger/pull/39)) by @DamianReeves

### ⚡ Performance

- *(syntax)* Linear file entries, O(1) field lookup through Tree ([#37](https://github.com/moonrockz/krueger/pull/37)) by @DamianReeves

### 🏗️ Build and CI

- *(release)* Make a repeated release run for one tag succeed ([#33](https://github.com/moonrockz/krueger/pull/33)) by @DamianReeves
- *(release)* Release pull requests, CHANGELOG.md and release notes from it ([#34](https://github.com/moonrockz/krueger/pull/34)) by @DamianReeves

**Full changelog**: https://github.com/moonrockz/krueger/compare/v0.2.0...v0.3.0

## [0.2.0] - 2026-10-01

The published package is smaller. The test harness (moonspec features,
parity and rejection checks) moved to an unpublished workspace module,
`harness/`, so users no longer download moonspec and its dependencies. The
property-test generators are now a public package, `moonrockz/krueger/lawkit`,
for writing laws over Elm source in your own tests.

### 🚀 Features

- Publish lawkit; move test-only dependencies to an unpublished harness module ([#32](https://github.com/moonrockz/krueger/pull/32)) by @DamianReeves

**Full changelog**: https://github.com/moonrockz/krueger/compare/v0.1.0...v0.2.0

## [0.1.0] - 2026-10-01

The first release. krueger scans and parses Elm 0.19.1 into an exact mirror
of the elm-syntax 7.3.9 AST, with a JSON encoder and decoder that match
elm-syntax byte for byte on all 363 files of the pinned package corpus. It
also gives a lossless CST, `elm make`-style diagnostics with renderers,
dialects (`elm-0.19.1`, `elm-syntax-7.3.9`) that reject what each oracle
rejects, doc-comment attributes, and a read-only syntax tree with walk, fold,
visitor, pull events and a cursor.

### 🚀 Features

- *(beads)* Add Elm parser epic, design phase, and stories by @DamianReeves
- *(parser)* Implement q56.3 parser baseline with diagnostics ([#2](https://github.com/moonrockz/krueger/pull/2)) by @DamianReeves
- *(ast)* Add dedicated AST package and migrate parser AST output ([#3](https://github.com/moonrockz/krueger/pull/3)) by @DamianReeves
- *(cst)* Introduce dedicated CST package and parser integration ([#4](https://github.com/moonrockz/krueger/pull/4)) by @DamianReeves
- *(scripts)* Port tooling scripts to MoonBit with moonspec features ([#6](https://github.com/moonrockz/krueger/pull/6)) by @DamianReeves
- *(ast)* Mirror elm-syntax 7.3.9 AST and parse into it ([#7](https://github.com/moonrockz/krueger/pull/7)) by @DamianReeves
- *(parity)* Measure Elm 0.19.1 parity against elm-syntax on a pinned corpus ([#8](https://github.com/moonrockz/krueger/pull/8)) by @DamianReeves
- *(parity)* HTML, JSON and JUnit XML parity reports attached to CI runs ([#9](https://github.com/moonrockz/krueger/pull/9)) by @DamianReeves
- *(scanner)* Tokenize all of Elm 0.19.1 ([#10](https://github.com/moonrockz/krueger/pull/10)) by @DamianReeves
- *(parser)* Port the elm-syntax 7.3.9 parser (363/363 corpus files match) ([#11](https://github.com/moonrockz/krueger/pull/11)) by @DamianReeves
- *(dialect)* Add Elm dialects and pass them through scanner, parser and API ([#12](https://github.com/moonrockz/krueger/pull/12)) by @DamianReeves
- Elm-style diagnostics with elm make titles, reports and renderers ([#14](https://github.com/moonrockz/krueger/pull/14)) by @DamianReeves
- *(parser)* Layout and literal rejection rules ([#15](https://github.com/moonrockz/krueger/pull/15)) by @DamianReeves
- Module-level rules, Unicode names and number warnings (rejection parity complete) ([#16](https://github.com/moonrockz/krueger/pull/16)) by @DamianReeves
- Attributes in doc comments ([#17](https://github.com/moonrockz/krueger/pull/17)) by @DamianReeves
- *(parser)* Attributes blocks use the fence info string attributes ([#18](https://github.com/moonrockz/krueger/pull/18)) by @DamianReeves
- *(syntax)* Node model and Tree over the parse result ([#21](https://github.com/moonrockz/krueger/pull/21)) by @DamianReeves
- *(syntax)* Walk, fold and Visitor over the node model ([#22](https://github.com/moonrockz/krueger/pull/22)) by @DamianReeves
- *(ast)* Read-only syntax trees ([#23](https://github.com/moonrockz/krueger/pull/23)) by @DamianReeves
- *(syntax)* Events, node paths and TreeCursor ([#26](https://github.com/moonrockz/krueger/pull/26)) by @DamianReeves
- *(ast)* Exact Int literals in JSON ([#31](https://github.com/moonrockz/krueger/pull/31)) by @DamianReeves

### 📚 Documentation

- *(design)* Design phase in progress, test strategy growth-per-story by @DamianReeves
- *(design)* Complete parser design phase contracts and seed bdd ([#1](https://github.com/moonrockz/krueger/pull/1)) by @DamianReeves

### 🧪 Testing

- *(rejection)* Record elm make and elm-syntax verdicts and check krueger against them ([#13](https://github.com/moonrockz/krueger/pull/13)) by @DamianReeves
- Soft assertions for tests with several checks ([#24](https://github.com/moonrockz/krueger/pull/24)) by @DamianReeves
- Boundary laws A — lawkit generators and syntax boundary laws ([#28](https://github.com/moonrockz/krueger/pull/28)) by @DamianReeves
- Boundary laws B — scanner and parser laws, eight bugs fixed ([#29](https://github.com/moonrockz/krueger/pull/29)) by @DamianReeves
- Boundary laws C — AST round trip, renderers and corpus prefix fuzz ([#30](https://github.com/moonrockz/krueger/pull/30)) by @DamianReeves

### 🏗️ Build and CI

- *(moonbit)* Upgrade toolchain to 0.10.14 and refresh beads setup ([#5](https://github.com/moonrockz/krueger/pull/5)) by @DamianReeves

### ⚙️ Maintenance

- Initial project setup for moonrockz/krueger by @DamianReeves
- *(git)* Ignore target symlink path by @DamianReeves
