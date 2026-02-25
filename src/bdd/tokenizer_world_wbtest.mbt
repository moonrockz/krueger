///|
fn has_comment_kind(
  stream : @krueger.TokenStream,
  kind : @krueger.CommentKind,
) -> Bool {
  stream.tokens.any(fn(token) {
    token.trivia_before.any(fn(trivia) {
      match trivia {
        @krueger.Trivia::Comment(comment) => comment.kind == kind
        _ => false
      }
    })
  })
}

///|
struct TokenizerWorld {
  mut source : String
  mut result : Result[@krueger.TokenStream, @krueger.ScanErrorList]?
} derive(Default)

///|
impl @moonspec.World for TokenizerWorld with configure(self, setup) {
  setup.given("Elm source:", fn(ctx) {
    match ctx[0] {
      { value: @moonspec.StepValue::DocStringVal(doc), .. } =>
        self.source = doc.content
      _ => ()
    }
  })
  setup.when("I tokenize the source", fn(_ctx) {
    let source = @krueger.SourceText::{ module_name: None, text: self.source }
    self.result = Some(@krueger.tokenize(source))
  })
  setup.then("tokenization succeeds", fn(_ctx) raise {
    match self.result {
      Some(Ok(_)) => ()
      _ => fail("expected tokenization success")
    }
  })
  setup.then(
    "the token stream contains a module declaration and function declaration",
    fn(_ctx) raise {
      match self.result {
        Some(Ok(stream)) => {
          assert_true(
            stream.tokens.any(fn(token) {
              token.kind == @krueger.TokenKind::module_kw()
            }),
          )
          assert_true(stream.tokens.any(fn(token) { token.lexeme == "add" }))
        }
        _ => fail("expected successful token stream")
      }
    },
  )
  setup.then("regular comments are preserved in trivia", fn(_ctx) raise {
    match self.result {
      Some(Ok(stream)) =>
        assert_true(
          has_comment_kind(stream, @krueger.CommentKind::Line) ||
          has_comment_kind(stream, @krueger.CommentKind::Block),
        )
      _ => fail("expected successful token stream")
    }
  })
  setup.then("the doc comment is preserved and identified as a doc comment", fn(
    _ctx,
  ) raise {
    match self.result {
      Some(Ok(stream)) =>
        assert_true(has_comment_kind(stream, @krueger.CommentKind::Doc))
      _ => fail("expected successful token stream")
    }
  })
  setup.then("tokenization fails with at least one diagnostic", fn(_ctx) raise {
    match self.result {
      Some(Err(errs)) => assert_true(errs.diagnostics.length() > 0)
      _ => fail("expected tokenization failure")
    }
  })
  setup.then(
    "a diagnostic indicates malformed block comment with a source span",
    fn(_ctx) raise {
      match self.result {
        Some(Err(errs)) => {
          assert_true(errs.diagnostics.length() > 0)
          assert_true(
            errs.diagnostics.any(fn(diag) { diag.code == "KR-SCAN-001" }),
          )
        }
        _ => fail("expected tokenization failure")
      }
    },
  )
}

///|
async test "tokenizer feature: comments and doc comments scenario" {
  let options = @moonspec.RunOptions::new([
    @moonspec.FeatureSource::File("tests/features/tokenizer.feature"),
  ])
  options.scenario_name("Tokenize module with comments and doc comment")
  @moonspec.run_or_fail(TokenizerWorld::default, options) |> ignore
}

///|
async test "tokenizer feature: malformed comment diagnostics scenario" {
  let options = @moonspec.RunOptions::new([
    @moonspec.FeatureSource::File("tests/features/tokenizer.feature"),
  ])
  options.scenario_name("Report malformed block comment")
  @moonspec.run_or_fail(TokenizerWorld::default, options) |> ignore
}

///|
async test "tokenizer feature: invalid character diagnostics scenario" {
  let options = @moonspec.RunOptions::new([
    @moonspec.FeatureSource::File("tests/features/tokenizer.feature"),
  ])
  options.scenario_name("Report invalid character sequence")
  @moonspec.run_or_fail(TokenizerWorld::default, options) |> ignore
}
