///|
/// `corpus/*`: one sample is one pass over all `sources`. `encode` parses
/// once, outside the measured work, and measures `encode_file` with the
/// JSON text.
fn corpus_cases(sources : Array[String]) -> Array[Case] {
  let texts = sources.map(s => @scanner.SourceText::new(s))
  let files = texts.filter_map(t => @krueger.parse_module(t).ast)
  let tokenize = () => {
    let mut n = 0
    for t in texts {
      if @krueger.tokenize(t) is Ok(stream) {
        n += stream.tokens.length()
      }
    }
    n
  }
  let parse = () => {
    let mut n = 0
    for t in texts {
      if @krueger.parse_module(t).ast is Some(_) {
        n += 1
      }
    }
    n
  }
  let encode = () => {
    let mut n = 0
    for f in files {
      n += @ast.encode_file(f).stringify().length()
    }
    n
  }
  [
    {
      suite: "corpus",
      name: "tokenize",
      input: "corpus",
      run: tokenize,
      check: () => if tokenize() <= 0 { fail("corpus/tokenize: no tokens") },
    },
    {
      suite: "corpus",
      name: "parse",
      input: "corpus",
      run: parse,
      check: () => {
        if parse() != texts.length() {
          fail("corpus/parse: a source did not parse")
        }
      },
    },
    {
      suite: "corpus",
      name: "encode",
      input: "corpus",
      run: encode,
      check: () => if encode() <= 0 { fail("corpus/encode: no output") },
    },
  ]
}

///|
test "corpus cases cover tokenize, parse and encode and pass their checks" {
  let cases = corpus_cases(fixture_sources())
  @expect.expect(cases.map(c => c.id())).to_equal([
    "corpus/tokenize/corpus", "corpus/parse/corpus", "corpus/encode/corpus",
  ])
  for c in cases {
    (c.check)()
  }
}
