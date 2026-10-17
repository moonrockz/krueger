///|
/// `module A exposing (f)` with the doc comment `{-|<doc>-}` before `f`.
fn doc_module(doc : String) -> String {
  "module A exposing (f)\n\n{-|" + doc + "-}\n\n\nf =\n    1\n"
}

///|
test "code in a doc comment is formatted; indented code too" {
  let source =
    #|module A exposing (f)
    #|
    #|{-| Doc.
    #|
    #|```elm
    #|f   x =   x
    #|```
    #|
    #|    g =  1
    #|
    #|-}
    #|
    #|
    #|f x =
    #|    x
    #|
  let expected =
    #|module A exposing (f)
    #|
    #|{-| Doc.
    #|
    #|    f x =
    #|        x
    #|
    #|    g =
    #|        1
    #|
    #|-}
    #|
    #|
    #|f x =
    #|    x
    #|
  @expect.expect(@printer.format(source)).to_equal(expected)
}

///|
test "code that does not parse stays as written" {
  let source = "module A exposing (f)\n\n{-| Doc.\n\n```elm\nf = (\n```\n\n-}\n\n\nf =\n    1\n"
  @expect.expect(@printer.format(source)).to_equal(
    "module A exposing (f)\n\n{-| Doc.\n\n    f = (\n\n-}\n\n\nf =\n    1\n",
  )
}

///|
test "doc code preserves a multiline expression with a trailing line comment" {
  // Recorded with elm-format 0.8.7: its expression parser leaves this code alone.
  let input =
    #| A.
    #|
    #|    f
    #|        [1,2] -- x
    #|
  let expected = doc_module(input + "\n")
  @expect.expect(@printer.format(doc_module(input))).to_equal(expected)
}

///|
test "doc code formats a multiline trailing comment when another expression follows" {
  // Recorded with elm-format 0.8.7: the comment leads the next expression.
  let input =
    #| A.
    #|
    #|    f
    #|        [1,2] -- x
    #|    g [3,4]
    #|
  let output =
    #| A.
    #|
    #|    f
    #|        [ 1, 2 ]
    #|
    #|    -- x
    #|    g [ 3, 4 ]
    #|
    #|
  @expect.expect(@printer.format(doc_module(input))).to_equal(
    doc_module(output),
  )
}

///|
test "doc code keeps a comment between the module header and imports" {
  // Recorded with elm-format 0.8.7.
  let input =
    #| A.
    #|
    #|    module B exposing (x)
    #|    -- c
    #|    import C
    #|    x = 1
    #|
  let output =
    #| A.
    #|
    #|    module B exposing (x)
    #|
    #|    -- c
    #|
    #|    import C
    #|
    #|    x =
    #|        1
    #|
    #|
  @expect.expect(@printer.format(doc_module(input))).to_equal(
    doc_module(output),
  )
}

///|
test "doc code moves a trailing import comment before the imports" {
  // Recorded with elm-format 0.8.7.
  let input =
    #| A.
    #|
    #|    import Time -- elm install elm/time
    #|    import Task
    #|    x = 1
    #|
  let output =
    #| A.
    #|
    #|    -- elm install elm/time
    #|
    #|    import Task
    #|    import Time
    #|
    #|    x =
    #|        1
    #|
    #|
  @expect.expect(@printer.format(doc_module(input))).to_equal(
    doc_module(output),
  )
}

///|
test "doc code keeps leading, moved and final import comments in their sections" {
  // Recorded with elm-format 0.8.7. Comments follow source order even when
  // sorting reverses the imports.
  let input =
    #| A.
    #|
    #|    -- leading
    #|    import Z -- first
    #|    import M -- middle
    #|    import A -- last
    #|    x = 1
    #|
  let output =
    #| A.
    #|
    #|    -- leading
    #|
    #|
    #|    -- first
    #|    -- middle
    #|
    #|    import A
    #|    import M
    #|    import Z
    #|
    #|
    #|    -- last
    #|    x =
    #|        1
    #|
    #|
  @expect.expect(@printer.format(doc_module(input))).to_equal(
    doc_module(output),
  )
}

///|
test "doc code keeps the only import's trailing comment after it" {
  // Recorded with elm-format 0.8.7: the last import is different.
  let input =
    #| A.
    #|
    #|    import Time -- last
    #|
  let output =
    #| A.
    #|
    #|    import Time
    #|
    #|
    #|    -- last
    #|
    #|
  @expect.expect(@printer.format(doc_module(input))).to_equal(
    doc_module(output),
  )
}

///|
test "doc code moves a block comment from an earlier import before the imports" {
  // Recorded with elm-format 0.8.7.
  let input =
    #| A.
    #|
    #|    import Z {- first -}
    #|    import A
    #|    x = 1
    #|
  let output =
    #| A.
    #|
    #|    {- first -}
    #|
    #|    import A
    #|    import Z
    #|
    #|    x =
    #|        1
    #|
    #|
  @expect.expect(@printer.format(doc_module(input))).to_equal(
    doc_module(output),
  )
}

///|
test "law: import comments follow elm-format's first and second passes" {
  // Enumerate all header, fence and line-ending combinations for every
  // generated comment. Both the moved and final comments must survive once.
  @quickcheck.check(
    (n : UInt32) => {
      [false, true]
      .iter()
      .all(header => {
        let prefix = if header { "module B exposing (x)\n" } else { "" }
        let comment = "café 😀 \{n}"
        let code = prefix +
          "import Z -- before " +
          comment +
          "\nimport A -- after " +
          comment +
          "\nx = 1\n"
        let output = prefix +
          (if header { "\n" } else { "" }) +
          "-- before " +
          comment +
          "\n\nimport A\nimport Z\n\n\n-- after " +
          comment +
          "\nx =\n    1\n\n"
        let indent = (s : String) => {
          s
          .split("\n")
          .map(l => if l == "" { "" } else { "    " + l.to_owned() })
          .join("\n")
        }
        let expected = doc_module(" A.\n\n" + indent(output))
        [false, true]
        .iter()
        .all(fenced => {
          let doc = if fenced {
            " A.\n\n```elm\n" + code + "```\n"
          } else {
            " A.\n\n" + indent(code)
          }
          [false, true]
          .iter()
          .all(crlf => {
            let source = doc_module(doc)
            let source = if crlf {
              source.replace_all(old="\n", new="\r\n")
            } else {
              source
            }
            let formatted = @printer.format(source) catch { _ => return false }
            guard formatted == expected else { return false }
            // elm-format treats the moved comment as a leading comment
            // on the next pass, adding a blank line before headerless imports.
            let stable = if header {
              expected
            } else {
              expected.replace_all(
                old="-- before " + comment + "\n\n",
                new="-- before " + comment + "\n\n\n",
              )
            }
            let second = @printer.format(formatted) catch { _ => return false }
            second == stable &&
            (@printer.format(second) catch { _ => return false }) == stable
          })
        })
      })
    },
    count=20,
    max_size=24,
    seed=263,
  )
}

///|
test "law: a final multiline expression with a line comment keeps its source text" {
  // Edges: one to four argument lines, ASCII and non-ASCII comments,
  // indented and fenced code, LF and CRLF input.
  @quickcheck.check(
    (input : (UInt32, Bool, Bool)) => {
      let (n, fenced, crlf) = input
      let lines = ["f"]
      for _ in 0..<(1 + (n % 4).reinterpret_as_int()) {
        lines.push("    [\{n % 100},2]")
      }
      let comment = if n % 2 == 0 { "-- x" } else { "-- café 😀" }
      lines[lines.length() - 1] += " " + comment
      let indented = lines.map(l => "    " + l).join("\n")
      let expected = doc_module(" A.\n\n" + indented + "\n\n")
      let doc = if fenced {
        " A.\n\n```elm\n" + lines.join("\n") + "\n```\n"
      } else {
        " A.\n\n" + indented + "\n"
      }
      let source = doc_module(doc)
      let source = if crlf {
        source.replace_all(old="\n", new="\r\n")
      } else {
        source
      }
      let formatted = @printer.format(source) catch { _ => return false }
      formatted == expected &&
      (@printer.format(formatted) catch { _ => return false }) == expected
    },
    count=100,
    max_size=24,
    seed=257,
  )
}

///|
/// Recorded with elm-format 0.8.7: the doc comment of `doc_module(input)`
/// becomes the doc comment of `doc_module(output)`.
let code_recordings : Array[(String, String)] = [
  // Declarations: one blank line between them, none after a comment.
  (
    " A.\n\n    f : Int\n    f = 1\n    g = 2\n    -- c\n    h = 3\n", " A.\n\n    f : Int\n    f =\n        1\n\n    g =\n        2\n\n    -- c\n    h =\n        3\n\n",
  ),
  (
    " A.\n\n    type alias A = Int\n    type B = B\n    {-| d -}\n    port p : Int -> Cmd msg\n",
    " A.\n\n    type alias A =\n        Int\n\n    type B\n        = B\n\n    {-| d\n    -}\n    port p : Int -> Cmd msg\n\n",
  ),
  // Expressions: each one that starts in column 1.
  (
    " A.\n\n    toString [1,2]\n    toString 3 -- n\n\n    -- c\n    x\n", " A.\n\n    toString [ 1, 2 ]\n\n    toString 3 -- n\n\n    -- c\n    x\n\n",
  ),
  // A module, with or without its header.
  (
    " A.\n\n    import Html exposing (text)\n    import Array\n\n    main =\n      text \"hi\"\n    foo = 1\n",
    " A.\n\n    import Array\n    import Html exposing (text)\n\n    main =\n        text \"hi\"\n\n    foo =\n        1\n\n",
  ),
  (
    " A.\n\n    module B exposing (x)\n    x = 1\n    y = 2\n", " A.\n\n    module B exposing (x)\n\n    x =\n        1\n\n    y =\n        2\n\n",
  ),
  (
    " Doc.\n\n    module B exposing (x)\n    import C\n    import B\n    x = 1\n\n",
    " Doc.\n\n    module B exposing (x)\n\n    import B\n    import C\n\n    x =\n        1\n\n",
  ),
  // Header comments stay in the import section, with or without imports.
  (
    " A.\n\n    module B exposing (x)\n    -- a\n    {- b -}\n    import Z\n    -- d\n    import C\n    x = 1\n",
    " A.\n\n    module B exposing (x)\n\n    -- a\n    {- b -}\n    -- d\n\n    import C\n    import Z\n\n    x =\n        1\n\n",
  ),
  (
    " A.\n\n    module B exposing (x)\n    -- c\n    x = 1\n", " A.\n\n    module B exposing (x)\n\n    -- c\n\n    x =\n        1\n\n",
  ),
  (
    " A.\n\n    module B exposing (x)\n    {-| Module. -}\n    -- c\n    import C\n    x = 1\n",
    " A.\n\n    module B exposing (x)\n\n    {-| Module.\n    -}\n\n    -- c\n\n    import C\n\n    x =\n        1\n\n",
  ),
  // A comment inside an expression does not prevent formatting it.
  (
    " A.\n\n    f -- x\n        [1,2]\n    g [3,4]\n", " A.\n\n    f\n        -- x\n        [ 1, 2 ]\n\n    g [ 3, 4 ]\n\n",
  ),
  // elm-format reads no comment after the last expression: the code stays.
  (" A.\n\n    f [1,2]\n    --> x\n", " A.\n\n    f [1,2]\n    --> x\n\n"),
  (" A.\n\n    f [1,2]\n        -- x\n", " A.\n\n    f [1,2]\n        -- x\n\n"),
  (
    " A.\n\n    f [1,2]\n\n    {-\n\n    [ 1 ]\n    ╷\n    -}\n", " A.\n\n    f [1,2]\n\n    {-\n\n    [ 1 ]\n    ╷\n    -}\n\n",
  ),
  (
    " A.\n\n    f [1,2]\n    -- x\n    g [1,2]\n", " A.\n\n    f [ 1, 2 ]\n\n    -- x\n    g [ 1, 2 ]\n\n",
  ),
  (" A.\n\n    f [1,2] -- x\n", " A.\n\n    f [ 1, 2 ] -- x\n\n"),
  // Declarations that end with a comment get a blank line before them;
  // code with only comments gets two blank lines after it.
  (
    " A.\n\n    f = 1\n    -- x\n", " A.\n\n\n    f =\n        1\n\n    -- x\n\n",
  ),
  (" A.\n\n    -- x\n", " A.\n\n    -- x\n\n\n\n"),
  (
    " A.\n\n    import B\n    f = 1\n    -- x\n", " A.\n\n    import B\n\n    f =\n        1\n\n    -- x\n\n",
  ),
  // Two definitions of one name: no blank line between them.
  (
    " A.\n\n    isEmpty graph =\n        graph == empty\n    isEmpty graph =\n        size graph == 0\n",
    " A.\n\n    isEmpty graph =\n        graph == empty\n    isEmpty graph =\n        size graph == 0\n\n",
  ),
  // A module in a doc comment (elm-format `formatModule`): comments at the
  // start, then two blank lines; a body that starts with a comment gets two
  // blank lines before it.
  (
    " A.\n\n    import B\n    -- c\n    f = 1\n", " A.\n\n    import B\n\n\n    -- c\n    f =\n        1\n\n",
  ),
  (" A.\n\n    -- a\n\n    -- b\n", " A.\n\n    -- a\n    -- b\n\n\n\n"),
  (" A.\n\n    -- a\n    {- b -}\n", " A.\n\n    -- a\n\n\n\n\n    {- b -}\n\n"),
  (" A.\n\n    {- a -}\n\n    -- b\n", " A.\n\n    {- a -}\n    -- b\n\n\n\n"),
  (
    " A.\n\n    -- a\n\n    f = 1\n    -- y\n", " A.\n\n    -- a\n\n\n\n    f =\n        1\n\n    -- y\n\n",
  ),
  (
    " A.\n\n    f = 1\n\n    -- x\n\n    -- y\n", " A.\n\n\n    f =\n        1\n\n    -- x\n    -- y\n\n",
  ),
  (
    " A.\n\n    f [1,2]\n    -- x\n    f = 2\n", " A.\n\n    f [1,2]\n    -- x\n    f = 2\n\n",
  ),
  (
    " A.\n\n    module Main exposing (x)\n\n    {-|\n\n    @docs x\n\n    -}\n\n    import String\n\n    x =\n        ()\n",
    " A.\n\n    module Main exposing (x)\n\n    {-|\n\n    @docs x\n\n    -}\n\n    import String\n\n    x =\n        ()\n\n",
  ),
  // Code after a list stays fenced.
  (
    " A.\n\n  - a\n\n```\nx = 1\n```\n", " A.\n\n  - a\n\n```\nx =\n    1\n```\n\n",
  ),
]

///|
test "code in doc comments is formatted as elm-format does" {
  @expect.expect_all(s => {
    for r in code_recordings {
      let (input, output) = r
      s.expect(@printer.format(doc_module(input))).to_equal(doc_module(output))
    }
  })
}

///|
test "attributes blocks stay and doc attributes survive formatting" {
  let doc = " A.\n\n```attributes\n@derive [ Json.encoder ]\n@morphir\n    { kind = \"entity\"\n    }\n```\n\n"
  let formatted = @printer.format(doc_module(doc))
  let parsed = @parser.parse_module(
    @scanner.SourceText::new(formatted),
    @scanner.DefaultScanner::new(),
  )
  @expect.expect_all(s => {
    s.expect(formatted).to_equal(doc_module(doc))
    s.expect(parsed.attributes.length()).to_equal(1)
  })
}

///|
test "print_file formats doc comments too" {
  let source = doc_module(" A *b* and snake_case.\n\n    f x = x\n")
  let file = @parser.parse_module(
    @scanner.SourceText::new(source),
    @scanner.DefaultScanner::new(),
  ).ast.unwrap()
  @expect.expect(@printer.print_file(file)).to_equal(
    doc_module(" A _b_ and snake\\_case.\n\n    f x =\n        x\n\n"),
  )
}

///|
test "normalize_file formats doc comments" {
  let source = doc_module(" A *b*.\n")
  let file = @parser.parse_module(
    @scanner.SourceText::new(source),
    @scanner.DefaultScanner::new(),
  ).ast.unwrap()
  // The first doc comment after the header is the module documentation.
  let normalized = @printer.normalize_file(file)
  @expect.expect(normalized.comments.map(c => c.value)).to_equal([
    "{-| A _b_.\n-}",
  ])
}

///|
test "a doc comment that formatting would not close at its end stays as written" {
  // Markdown reads `{\-` and `-\}` as `{-` and `-}`, which would open or
  // close a comment: the doc comment stays exactly as written (also the
  // `*b*` that elm-format writes `_b_`).
  @expect.expect_all(s => {
    for doc in [" A *b* {\\- c.\n", " A *b* -\\} c.\n"] {
      let source = doc_module(doc)
      s.expect(@printer.format(source)).to_equal(source)
    }
  })
}
