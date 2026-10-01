# Changelog

All notable changes to `moonrockz/krueger` are listed here, newest first.
Versions follow [Semantic Versioning](https://semver.org); while the version
is 0.x, a minor release can contain breaking changes.

<!-- git-cliff: end of header -->

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
