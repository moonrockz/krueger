///|
fn find_function_decl(
  result : @krueger.ParseResult,
  name : String,
) -> @krueger.FunctionDeclaration? {
  match result.ast {
    Some(ast) => {
      for decl in ast.declarations {
        match decl {
          @krueger.Declaration::FunctionDecl(fn_decl) if fn_decl.name == name =>
            return Some(fn_decl)
          _ => ()
        }
      }
      None
    }
    None => None
  }
}

///|
fn has_comment_kind_in_cst(
  result : @krueger.ParseResult,
  kind : @krueger.CommentKind,
) -> Bool {
  match result.cst {
    Some(cst) =>
      cst.tokens.any(fn(token) {
        token.trivia_before.any(fn(trivia) {
          match trivia {
            @krueger.Trivia::Comment(comment) => comment.kind == kind
            _ => false
          }
        }) ||
        token.trivia_after.any(fn(trivia) {
          match trivia {
            @krueger.Trivia::Comment(comment) => comment.kind == kind
            _ => false
          }
        })
      })
    None => false
  }
}

///|
fn has_malformed_comment_diagnostic(result : @krueger.ParseResult) -> Bool {
  result.diagnostics.any(fn(diag) {
    (diag.code == "KR-SCAN-001" || diag.code == "KR-SCAN-002") &&
    diag.span.start.offset <= diag.span.end.offset
  })
}

///|
struct ParserWorld {
  mut source : String
  mut result : @krueger.ParseResult?
} derive(Default)

///|
impl @moonspec.World for ParserWorld with configure(self, setup) {
  setup.given("Elm source:", fn(ctx) {
    match ctx[0] {
      { value: @moonspec.StepValue::DocStringVal(doc), .. } =>
        self.source = doc.content
      _ => ()
    }
  })
  setup.when("I parse the source", fn(_ctx) {
    let source = @krueger.SourceText::{ module_name: None, text: self.source }
    self.result = Some(@krueger.parse_module(source))
  })
  setup.then("parsing succeeds without diagnostics", fn(_ctx) raise {
    match self.result {
      Some(result) => {
        assert_eq(result.diagnostics.length(), 0)
        assert_true(result.ast != None)
      }
      None => fail("expected parse result")
    }
  })
  setup.then("parsing succeeds", fn(_ctx) raise {
    match self.result {
      Some(result) => {
        assert_eq(result.diagnostics.length(), 0)
        assert_true(result.ast != None)
      }
      None => fail("expected parse result")
    }
  })
  setup.then("the AST contains function declaration {string}", fn(ctx) raise {
    match (self.result, ctx[0]) {
      (Some(result), { value: @moonspec.StepValue::StringVal(name), .. }) =>
        assert_true(find_function_decl(result, name) != None)
      _ => fail("expected parse result and function name")
    }
  })
  setup.then("declaration {string} has the attached doc comment {string}", fn(
    ctx,
  ) raise {
    match (self.result, ctx[0], ctx[1]) {
      (
        Some(result),
        { value: @moonspec.StepValue::StringVal(name), .. },
        { value: @moonspec.StepValue::StringVal(expected), .. },
      ) =>
        match find_function_decl(result, name) {
          Some(fn_decl) =>
            match fn_decl.meta.doc_comment {
              Some(doc) => assert_eq(doc.text, expected)
              None => fail("expected attached doc comment")
            }
          None => fail("expected function declaration")
        }
      _ => fail("expected parse result and step arguments")
    }
  })
  setup.then(
    "declaration {string} has no attached doc comment in AST metadata",
    fn(ctx) raise {
      match (self.result, ctx[0]) {
        (Some(result), { value: @moonspec.StepValue::StringVal(name), .. }) =>
          match find_function_decl(result, name) {
            Some(fn_decl) => assert_eq(fn_decl.meta.doc_comment, None)
            None => fail("expected function declaration")
          }
        _ => fail("expected parse result and declaration name")
      }
    },
  )
  setup.then("both comments are preserved in CST or token trivia", fn(
    _ctx,
  ) raise {
    match self.result {
      Some(result) => {
        let has_regular = has_comment_kind_in_cst(
            result,
            @krueger.CommentKind::Line,
          ) ||
          has_comment_kind_in_cst(result, @krueger.CommentKind::Block)
        assert_true(has_comment_kind_in_cst(result, @krueger.CommentKind::Doc))
        assert_true(has_regular)
      }
      None => fail("expected parse result")
    }
  })
  setup.then("parsing returns diagnostics", fn(_ctx) raise {
    match self.result {
      Some(result) => assert_true(result.diagnostics.length() > 0)
      None => fail("expected parse result")
    }
  })
  setup.then(
    "at least one diagnostic reports malformed comment with a source span",
    fn(_ctx) raise {
      match self.result {
        Some(result) => assert_true(has_malformed_comment_diagnostic(result))
        None => fail("expected parse result")
      }
    },
  )
}

///|
async test "parser feature: attach doc comment scenario" {
  let options = @moonspec.RunOptions::new([
    @moonspec.FeatureSource::File("tests/features/parser.feature"),
  ])
  options.scenario_name("Attach doc comment to following declaration")
  @moonspec.run_or_fail(ParserWorld::default, options) |> ignore
}

///|
async test "parser feature: separated comment does not attach scenario" {
  let options = @moonspec.RunOptions::new([
    @moonspec.FeatureSource::File("tests/features/parser.feature"),
  ])
  options.scenario_name(
    "Do not attach doc comment when separated by regular comment",
  )
  @moonspec.run_or_fail(ParserWorld::default, options) |> ignore
}

///|
async test "parser feature: malformed comment diagnostics scenario" {
  let options = @moonspec.RunOptions::new([
    @moonspec.FeatureSource::File("tests/features/parser.feature"),
  ])
  options.scenario_name("Surface malformed comment as diagnostic during parse")
  @moonspec.run_or_fail(ParserWorld::default, options) |> ignore
}
