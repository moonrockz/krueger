///|
test "krueger_accepts ignores warnings and counts errors" {
  @expect.expect_all(s => {
    let d = @krueger.Dialect::elm_0_19_1()
    s
    .expect(krueger_accepts("module Fixture exposing (..)\n\n\nf = 1\n", d))
    .to_equal(true)
    s
    .expect(krueger_accepts("module Fixture exposing (..)\n\n\nf = (\n", d))
    .to_equal(false)
  })
}

///|
test "mismatches compares both dialects and checks hashes" {
  @expect.expect_all(s => {
    let text = "module Fixture exposing (..)\n\n\nf = 1\n"
    let verdicts : Json = {
      "a.elm": {
        "sha256": sha256_hex(text).to_json(),
        "elm-0.19.1": { "accepted": false },
        "elm-syntax-7.3.9": { "accepted": true },
      },
    }
    s
    .expect(mismatches(verdicts, _ => text))
    .to_equal([{ fixture: "a.elm", dialect: "elm-0.19.1", check: "verdict", }])
    let stale = try mismatches(verdicts, _ => text + " ") catch {
      e => e.to_string()
    } noraise {
      _ => "no error"
    }
    s.expect(stale).to_contain("run `mise run rejection:record`")
  })
}

///|
test "pending entries round-trip through JSON" {
  @expect.expect_all(s => {
    let entries = [
      { fixture: "b.elm", dialect: "elm-0.19.1", check: "verdict", },
      { fixture: "a.elm", dialect: "elm-syntax-7.3.9", check: "verdict", },
    ]
    let text = format_pending(entries)
    s.expect(text).to_contain("\"a.elm\"")
    s.expect(parse_pending(text)).to_equal([entries[1], entries[0]])
  })
}

///|
test "fixtures on disk and recorded verdicts must agree" {
  @expect.expect_all(s => {
    let text = "module Fixture exposing (..)\n\n\nf = 1\n"
    let verdicts : Json = {
      "a.elm": {
        "sha256": sha256_hex(text).to_json(),
        "elm-0.19.1": { "accepted": true },
        "elm-syntax-7.3.9": { "accepted": true },
      },
    }
    s.expect(unrecorded(verdicts, ["a.elm"])).to_equal([])
    s
    .expect(unrecorded(verdicts, ["a.elm", "b/new.elm"]))
    .to_equal(["b/new.elm not recorded: run `mise run rejection:record`"])
    s
    .expect(unrecorded(verdicts, []))
    .to_equal(["a.elm removed: run `mise run rejection:record`"])
  })
}

///|
test "title parity only compares fixtures that both reject" {
  @expect.expect_all(s => {
    let accepted_text = "module Fixture exposing (..)\n\n\nf = 1\n"
    let rejected_text = "module Fixture exposing (..)\n\n\nf =\n    case x of\n"
    let elm : Json = { "accepted": false, "title": "UNFINISHED CASE" }
    s.expect(title_mismatch("a.elm", accepted_text, elm)).to_equal(None)
    s.expect(title_mismatch("a.elm", rejected_text, elm)).to_equal(None)
    s
    .expect(
      title_mismatch("a.elm", rejected_text, {
        "accepted": false,
        "title": "UNFINISHED LET",
      }),
    )
    .to_equal(
      Some({ fixture: "a.elm", dialect: "elm-0.19.1", check: "title", }),
    )
    s
    .expect(title_mismatch("a.elm", rejected_text, { "accepted": true }))
    .to_equal(None)
  })
}

///|
test "snapshots live next to the fixtures under messages/" {
  @expect.expect(snapshot_path("layout/in_col1.elm")).to_equal(
    "tests/rejection/messages/layout/in_col1.txt",
  )
}

///|
test "elm make messages render as plain text" {
  let message : Json = [
    "I got stuck:\n\n1| x\n   ",
    { "bold": false, "underline": false, "color": "RED", "string": "^" },
    "\nTry again.",
  ]
  @expect.expect(elm_message_text(message)).to_equal(
    "I got stuck:\n\n1| x\n   ^\nTry again.",
  )
}

///|
test "the side-by-side report escapes HTML" {
  @expect.expect_all(s => {
    let html = report_html([
      {
        fixture: "a/b.elm",
        elm_title: "UNFINISHED LIST",
        elm_message: "x <y> & z",
        krueger_title: "UNFINISHED LIST",
        krueger_message: "-- UNFINISHED LIST\n[ 1 <",
        elm_accepted: false,
        krueger_accepted: false,
      },
    ])
    s.expect(html).to_contain("x &lt;y&gt; &amp; z")
    s.expect(html).to_contain("[ 1 &lt;")
    s.expect(html).to_contain("a/b.elm")
  })
}
