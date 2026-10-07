///|
/// A module with `declarations` functions and two comments for each: a
/// line comment before the function and one in its body. It is in
/// elm-format's layout, so `format` gives the same text back. The number
/// of comments makes comment placement a large part of the work.
fn commented_module(declarations : Int) -> String {
  let buf = StringBuilder()
  buf.write_string("module Bench exposing (..)\n")
  for i in 0..<declarations {
    // elm-format leaves one blank line after the header, two between
    // declarations and a comment before the next one.
    buf.write_string(if i == 0 { "\n" } else { "\n\n\n" })
    buf.write_string(
      "-- before \{i}\n\n\nf\{i} : Int -> Int\nf\{i} x =\n    -- inside \{i}\n    x + \{i}\n",
    )
  }
  buf.to_string()
}

///|
/// `format/*`: `format` of every source (`corpus`) and of `commented`, a
/// module with many comments. One sample formats all its sources once.
fn format_cases(sources : Array[Source], commented : Source) -> Array[Case] {
  let format_all = (sources : Array[Source]) => {
    () => {
      let mut n = 0
      for s in sources {
        n += @krueger.format(s.text, dialect=dialect_of(s)).length() catch {
          _ => 0
        }
      }
      n
    }
  }
  let corpus = format_all(sources)
  let commented_run = format_all([commented])
  [
    {
      suite: "format",
      name: "format",
      input: "corpus",
      run: corpus,
      check: () => {
        for s in sources {
          @krueger.format(s.text, dialect=dialect_of(s)) |> ignore
        }
      },
    },
    {
      suite: "format",
      name: "format",
      input: "commented",
      run: commented_run,
      check: () => {
        let out = @krueger.format(commented.text)
        if out != commented.text {
          fail("format/format/commented: the output is not the input")
        }
      },
    },
  ]
}

///|
test "format cases cover the corpus and a commented module and pass their checks" {
  let commented : Source = { key: "commented", text: commented_module(5), }
  let cases = format_cases(fixture_sources(), commented)
  @expect.expect(cases.map(c => c.id())).to_equal([
    "format/format/corpus", "format/format/commented",
  ])
  for c in cases {
    (c.check)()
  }
}
