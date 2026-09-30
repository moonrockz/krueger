///|
test "krueger_accepts ignores warnings and counts errors" {
  let d = @krueger.Dialect::elm_0_19_1()
  @expect.expect(
    krueger_accepts("module Fixture exposing (..)\n\n\nf = 1\n", d),
  ).to_equal(true)
  @expect.expect(
    krueger_accepts("module Fixture exposing (..)\n\n\nf = (\n", d),
  ).to_equal(false)
}

///|
test "mismatches compares both dialects and checks hashes" {
  let text = "module Fixture exposing (..)\n\n\nf = 1\n"
  let verdicts : Json = {
    "a.elm": {
      "sha256": sha256_hex(text).to_json(),
      "elm-0.19.1": { "accepted": false },
      "elm-syntax-7.3.9": { "accepted": true },
    },
  }
  @expect.expect(mismatches(verdicts, _ => text)).to_equal([
    { fixture: "a.elm", dialect: "elm-0.19.1", check: "verdict", },
  ])
  let stale = try mismatches(verdicts, _ => text + " ") catch {
    e => e.to_string()
  } noraise {
    _ => "no error"
  }
  @expect.expect(stale).to_contain("run `mise run rejection:record`")
}

///|
test "pending entries round-trip through JSON" {
  let entries = [
    { fixture: "b.elm", dialect: "elm-0.19.1", check: "verdict", },
    { fixture: "a.elm", dialect: "elm-syntax-7.3.9", check: "verdict", },
  ]
  let text = format_pending(entries)
  @expect.expect(text).to_contain("\"a.elm\"")
  @expect.expect(parse_pending(text)).to_equal([entries[1], entries[0]])
}

///|
test "fixtures on disk and recorded verdicts must agree" {
  let text = "module Fixture exposing (..)\n\n\nf = 1\n"
  let verdicts : Json = {
    "a.elm": {
      "sha256": sha256_hex(text).to_json(),
      "elm-0.19.1": { "accepted": true },
      "elm-syntax-7.3.9": { "accepted": true },
    },
  }
  @expect.expect(unrecorded(verdicts, ["a.elm"])).to_equal([])
  @expect.expect(unrecorded(verdicts, ["a.elm", "b/new.elm"])).to_equal([
    "b/new.elm not recorded: run `mise run rejection:record`",
  ])
  @expect.expect(unrecorded(verdicts, [])).to_equal([
    "a.elm removed: run `mise run rejection:record`",
  ])
}
