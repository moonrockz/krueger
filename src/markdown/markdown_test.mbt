///|
/// A `format_code` stub: the elm-format 0.8.7 output for the code of the
/// recordings below, `None` for other code.
fn stub_code(code : String) -> String? {
  match code {
    "f   x =   x" => Some("f x =\n    x\n")
    "f x = x" => Some("f x =\n    x\n")
    "x = 1" => Some("x =\n    1\n")
    "b\n\n\n\nc" => Some("b\n\nc\n")
    "" => Some("")
    _ => None
  }
}

///|
test "emphasis becomes underscores and underscores in words are escaped" {
  @expect.expect(@markdown.format_doc(" Doc with *emphasis* and snake_case.\n")).to_equal(
    " Doc with _emphasis_ and snake\\_case.\n",
  )
}

///|
test "bullet items are written with - and the doc ends with a blank line" {
  @expect.expect(@markdown.format_doc(" A.\n\n  - item one\n  - item two\n")).to_equal(
    " A.\n\n  - item one\n  - item two\n\n",
  )
}

///|
test "elm code blocks go to format_code, other code blocks stay" {
  let doc = " A.\n\n```elm\nf   x =   x\n```\n\n```attributes\n@derive [ Json.encoder ]\n```\n"
  @expect.expect(@markdown.format_doc(doc, format_code=stub_code)).to_equal(
    " A.\n\n    f x =\n        x\n\n```attributes\n@derive [ Json.encoder ]\n```\n\n",
  )
}

///|
test "@docs lines lose (..)" {
  @expect.expect(@markdown.format_doc(" A.\n\n@docs T(..), x\n")).to_equal(
    " A.\n\n@docs T, x\n\n",
  )
}

///|
/// Recorded with elm-format 0.8.7: each input is the text between `{-|` and
/// `-}` of `module A exposing (..)\n\n{-|<input>-}\n\n\nx =\n    1\n`, and
/// each output is that text after elm-format.
let recordings : Array[(String, String)] = [
  ("", " "),
  (" Doc.", " Doc.\n"),
  ("\n Doc.\n", " Doc.\n"),
  ("\n    f x = x\n", "\n\n    f x =\n        x\n\n"),
  (" A.\n\n    f = (\n\n    g\n", " A.\n\n    f = (\n\n    g\n\n"),
  (" A.\n\n> q1\n>\n> q2\n", " A.\n\n> q1\n>\n> q2\n\n"),
  (" A.\n# H\nB.\n", " A.\n\n\n# H\n\nB.\n\n"),
  (" A.\n\n3. x\n4. y\n", " A.\n\n1.  x\n2.  y\n\n"),
  (
    " A.\n\n---\n\n<div>\nhi\n</div>\n\n[a]: http://x \"T\"\n[b]: <y>\n", " A.\n\n---\n\n<div>\nhi\n</div>\n\n[a]: http://x \"T\"\n[b]: y\n\n",
  ),
  ("@docs a, b(..)\n@docs c\n", "\n\n@docs a, b\n@docs c\n\n"),
  (
    " See http://elm-lang.org. And &ldquo;x&rdquo; <http://a.b> [x](http://y \"t\") [http://z](http://z)\n",
    " See <http://elm-lang.org>. And &ldquo;x&rdquo; <http://a.b> [x](http://y \"t\") <http://z>\n",
  ),
  (" a  \nb\\\nc\n", " a\nb\nc\n"),
  (" A.\n\n  - a\n\n  - b\n", " A.\n\n  - a\n\n  - b\n\n"),
  (" A.\n\n  - a\n      - b\n  - c\n", " A.\n\n  - a\n      - b\n  - c\n\n"),
  (
    " A.\n\n  - a\n\n```\nx = 1\n```\n", " A.\n\n  - a\n\n```\nx =\n    1\n```\n\n",
  ),
  (" A.\n\n```\n```\n", " A.\n\n\n"),
  (
    " a_b *c* __d__ **e** ***f*** _g_h `x` ``y`z`` \\\\* &amp; &#65; <b>x</b> <a@b.c> [a_b] [x][y] ![i](u \"t\") [l](<u v>)\n",
    " a\\_b _c_ **d** **e** _**f**_ _g_h `x` `` y`z `` \\\\\\* &amp; &#65; <b>x</b> [a@b.c](mailto:a@b.c) [a\\_b][x][y] ![i](u \"t\") [l](u v)\n",
  ),
  (
    " [ab:c](ab:c) [a:c](a:c) see https://x.org/a_(b). http: (http://y.z)\n", " <ab:c> [a:c](a:c) see <https://x.org/a_(b)>. http: (<http://y.z>)\n",
  ),
  (" *a _b *c* d_ e* x** y **z\n", " _a _b _c_ d_ e_ x\\*\\* y \\*\\*z\n"),
  // cheapskate difference, bd krueger-rne.12: a setext underline makes
  // only the line before it a heading (fixed after parsing)
  (" Foo\nBar\n---\n\nBaz\n===\n", " Foo\n\n\n## Bar\n\n\n# Baz\n\n"),
  (" # T #\n## U \\#\n\n#\n", "\n\n\n# T\n\n\n## U #\n\n\n#\n\n"),
  (" a\n\n    b\n\n\n\n    c\n", " a\n\n    b\n\n    c\n\n"),
  (
    " A.\n\n> # q\n> - x\n> - y\n>\n>     code\n", " A.\n\n>\n> # q\n>\n>   - x\n>\n>   - y\n>\n>     code\n\n",
  ),
  (" a\n\n1. x\n\n    y\n\n10. z\n", " a\n\n1.  x\n\n    y\n\n2.  z\n\n"),
  (" tab\there\n\n\tcode\n", " tab here\n\n    code\n\n"),
  // cheapskate difference, bd krueger-rne.12: a `@docs` line ends a
  // paragraph (fixed after parsing)
  (" x\n@docs a\nb, c\n\nd\n", " x\n\n@docs a\n@docs b, c\n\nd\n\n"),
  (" a\n  - x\n  - y\nb\n", " a\n\n  - x\n  - y\n    b\n\n"),
  (" a 😀 b\nc *d* 😀_x_\n", " a 😀 b\nc _d_ 😀_x_\n"),
  (" A.\n\n> a `b\n> c` d\n> e\n", " A.\n\n> a `b\n> c` d\n> e\n\n"),
  (" A.\n\n  - x\n    `y\n    z` w\n", " A.\n\n  - x\n    `y\n    z` w\n\n"),
  (" a\n    > b\n", " a\n> b\n"),
  // cheapskate difference, bd krueger-rne.12: a blank line between the
  // items of a nested list makes the enclosing list loose (fixed after
  // parsing)
  (
    "- a\n- b\n    - c\n\n    - d\n\n    - e\n", "\n\n  - a\n\n  - b\n      - c\n\n      - d\n\n      - e\n\n",
  ),
  // cheapskate difference, bd krueger-rne.12: a list from any number
  // interrupts a paragraph (fixed after parsing)
  ("1. a\n    3. b\n", "\n\n1.  a\n    1.  b\n\n"),
  // elm-format writes emphasis that starts after a letter with `_`, which
  // it reads as text the next time.
  (" a*b c *em*\n", " a_b c _em\\*\n"),
  (" a_b c _em\\*\n", " a\\_b c \\_em\\*\n"),
  // cheapskate difference, bd krueger-rne.13: a line that starts with the
  // fence ends a fenced code block, and the rest of the line goes (fixed
  // after parsing)
  (
    " Doc\n\n```\n@docs a\n```x\n@docs b\n```\n\n@docs c\n\n", " Doc\n\n    @docs a\n\n@docs b\n\n\n    @docs c\n\n",
  ),
  // cheapskate difference, bd krueger-rne.12: an HTML block does not
  // interrupt a paragraph (fixed after parsing)
  (" a\n<div>\nb_c\n</div>\n", " a\n<div>\nb\\_c\n</div>\n"),
  // cheapskate difference, bd krueger-rne.12: a blank line after a nested
  // list at the end does not make the list loose (cmark says loose; fixed
  // after parsing)
  ("- a\n- b\n    - c\n\n", "\n\n  - a\n  - b\n      - c\n\n"),
  // cheapskate difference, bd krueger-rne.13: only a block-level tag,
  // `<!--` or `-->` starts an HTML block; other lines are a paragraph
  // (fixed after parsing)
  (" A.\n\n<span>\na_b\n</span>\n", " A.\n\n<span>\na\\_b\n</span>\n\n"),
  (" A.\n\n<script>\na_b\n</script>\n", " A.\n\n<script>\na\\_b\n</script>\n\n"),
  (" A.\n\n<div>\na_b\n</div>\n", " A.\n\n<div>\na_b\n</div>\n\n"),
  // elm-format writes two lists with different marks with `-`, which it
  // reads as one list the next time.
  (
    "- a\n\n- b\n\n* c\n* d\n\nx\n", "\n\n  - a\n\n  - b\n\n  - c\n  - d\n\nx\n\n",
  ),
  (
    "\n\n  - a\n\n  - b\n\n  - c\n  - d\n\nx\n\n", "\n\n  - a\n\n  - b\n\n  - c\n\n  - d\n\nx\n\n",
  ),
  // `(..)` goes from `@docs` lines at the top level only (elm-format
  // `cleanBlock`).
  (" A.\n\n- x\n\n  @docs a, b(..)\n", " A.\n\n  - x\n\n    @docs a, b(..)\n\n"),
  (" A.\n\n> @docs a, b(..)\n", " A.\n\n> @docs a, b(..)\n\n"),
  // elm-format reads `[a] [a]` as one reference link.
  (" [ref] [ref] x\n", " [ref] x\n"),
  // elm-format keeps the blank first line of an Elm code block that it
  // cannot format (and drops it when it formats the result again).
  (
    "\n*em* é `code`\n\n```\n\n@derive [ Json.encoder ]\n@derive [ Json.encoder ]\n```\n",
    " _em_ é `code`\n\n\n    @derive [ Json.encoder ]\n    @derive [ Json.encoder ]\n\n",
  ),
]

///|
test "format_doc gives elm-format's output" {
  @expect.expect_all(s => {
    for r in recordings {
      let (input, expected) = r
      s
      .expect(@markdown.format_doc(input, format_code=stub_code))
      .to_equal(expected)
    }
  })
}

///|
test "text that nests too deep stays as written" {
  let brackets = " " + "[".repeat(13) + "x" + "]".repeat(13) + " *a*\n"
  let quotes = " A *b*.\n\n" + "> ".repeat(101) + "x\n"
  let mut lists = " A *b*.\n\n"
  for i in 0..<120 {
    lists = lists + "  ".repeat(i) + "- a\n"
  }
  let inlines = " " + "*a _".repeat(40) + "x\n"
  @expect.expect_all(s => {
    s.expect(@markdown.format_doc(brackets)).to_equal(brackets)
    s.expect(@markdown.format_doc(quotes)).to_equal(quotes)
    s.expect(@markdown.format_doc(lists)).to_equal(lists)
    s.expect(@markdown.format_doc(inlines)).to_equal(inlines)
  })
}

///|
test "text at the nesting limits is formatted" {
  let brackets = " " + "[".repeat(12) + "x" + "]".repeat(12) + " *a*\n"
  let quotes = " A *b*.\n\n" + "> ".repeat(100) + "x\n"
  @expect.expect_all(s => {
    s.expect(@markdown.format_doc(brackets).contains("_a_")).to_be_true()
    s.expect(@markdown.format_doc(quotes).contains("_b_")).to_be_true()
  })
}

///|
test "HTML blocks end where CommonMark ends them" {
  // cheapskate difference, bd krueger-uyd: elm-format ends an HTML block
  // at the first blank line. These pin krueger's output; elm-format gives
  // " A.\n\n<!-- a_b -->\nc_d\n\n" and
  // " A.\n\n<pre>\na_b\n\nc\\_d\n</pre>\n\n".
  @expect.expect_all(s => {
    s
    .expect(@markdown.format_doc(" A.\n\n<!-- a_b -->\nc_d\n"))
    .to_equal(" A.\n\n<!-- a_b -->\n\nc\\_d\n\n")
    s
    .expect(@markdown.format_doc(" A.\n\n<pre>\na_b\n\nc_d\n</pre>\n"))
    .to_equal(" A.\n\n<pre>\na_b\n\nc_d\n</pre>\n\n")
  })
}
