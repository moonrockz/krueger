///|
/// Render one token as `kind:lexeme`, or the lexeme alone for punctuation.
fn render_token(token : @krueger.Token) -> String {
  let text = token.lexeme
  match token.kind {
    Keyword(_) => "kw:\{text}"
    Identifier =>
      match text.get_char(0) {
        Some(c) if @krueger.is_upper_start(c) => "upper:\{text}"
        _ => "lower:\{text}"
      }
    IntLiteral => "int:\{text}"
    FloatLiteral => "float:\{text}"
    StringLiteral => "str:\{text}"
    CharLiteral => "char:\{text}"
    Glsl => "glsl:\{text}"
    Operator(op) => "op:\{op}"
    _ => text
  }
}

///|
/// Scenario state for `tests/features/lexer.feature`.
struct LexerWorld {
  mut source : String
  mut result : Result[@krueger.TokenStream, @krueger.ScanErrorList]?
}

///|
fn LexerWorld::new() -> LexerWorld {
  { source: "", result: None, }
}

///|
fn LexerWorld::tokens(self : LexerWorld) -> Array[@krueger.Token] raise {
  match self.result {
    Some(Ok(stream)) => stream.tokens
    Some(Err(errs)) =>
      fail(
        "tokenization failed: " + errs.diagnostics.map(d => d.code).join(", "),
      )
    None => fail("tokenize the source first")
  }
}

///|
impl @moonspec.World for LexerWorld with fn configure(self, setup) {
  setup.given1("Elm source:", fn(doc : @moonspec.DocString) {
    self.source = doc.content
  })
  setup.given0("Elm source with a tab", fn() { self.source = "x =\t1" })
  setup.when0("I tokenize the source", fn() {
    self.result = Some(
      @krueger.tokenize({ module_name: None, text: self.source, }),
    )
  })
  setup.then1("the tokens are:", fn(doc : @moonspec.DocString) raise {
    @expect.expect(self.tokens().map(render_token).join(" ")).to_equal(
      doc.content,
    )
  })
  setup.then2("token {int} starts at {string}", fn(
    index : Int,
    position : String,
  ) raise {
    let tokens = self.tokens()
    let start = tokens[index - 1].span.start
    @expect.expect("\{start.line}:\{start.column}").to_equal(position)
  })
  setup.then1("tokenization fails with code {string}", fn(code : String) raise {
    guard self.result is Some(Err(errs)) else {
      fail("expected tokenization to fail")
    }
    @expect.expect(errs.diagnostics.map(d => d.code)).to_contain_element(code)
  })
}

///|
async test "lexer feature" {
  @moonspec.run_or_fail(
    LexerWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("../tests/features/lexer.feature"),
    ]),
  )
  |> ignore
}
