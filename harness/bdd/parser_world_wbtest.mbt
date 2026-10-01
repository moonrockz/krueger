///|
fn find_custom_type(result : @krueger.ParseResult, name : String) -> @ast.Type? {
  guard result.ast is Some(file) else { return None }
  for decl in file.declarations {
    if decl.value is CustomTypeDeclaration(t) && t.name.value == name {
      return Some(t)
    }
  }
  None
}

///|
fn has_comment_kind_in_cst(
  result : @krueger.ParseResult,
  kind : @krueger.CommentKind,
) -> Bool {
  guard result.cst is Some(cst) else { return false }
  cst.tokens.any(token => {
    let is_kind = trivia => {
      trivia is @krueger.Trivia::Comment(c) && c.kind == kind
    }
    token.trivia_before.any(is_kind) || token.trivia_after.any(is_kind)
  })
}

///|
fn cst_declaration_name(decl : @krueger.DeclarationCst) -> String {
  match decl {
    Function(f) => f.name
    TypeAlias(a) => a.name
    UnionType(u) => u.name
  }
}

///|
/// Scenario state for `tests/features/parser.feature`.
struct ParserWorld {
  mut source : String
  mut result : @krueger.ParseResult?
  /// Fixtures are compared with elm-syntax output, so they parse in its dialect.
  mut dialect : @krueger.Dialect
}

///|
fn ParserWorld::new() -> ParserWorld {
  { source: "", result: None, dialect: @krueger.Dialect::elm_0_19_1(), }
}

///|
fn ParserWorld::parsed(self : ParserWorld) -> @krueger.ParseResult raise {
  guard self.result is Some(result) else { fail("expected a parse result") }
  result
}

///|
impl @moonspec.World for ParserWorld with fn configure(self, setup) {
  setup.given1("Elm source:", fn(doc : @moonspec.DocString) {
    self.source = doc.content
  })
  setup.given1("the Elm fixture {string}", fn(name : String) raise {
    self.source = @fs.read_file_to_string(
      "../tests/fixtures/parser/\{name}.elm",
    )
    self.dialect = @krueger.Dialect::elm_syntax_7_3_9()
  })
  setup.given1("the Elm fixture {string} from the AST fixtures", fn(
    name : String,
  ) raise {
    self.source = @fs.read_file_to_string("../tests/fixtures/ast/\{name}.elm")
    self.dialect = @krueger.Dialect::elm_syntax_7_3_9()
  })
  setup.then1(
    "the AST JSON equals the elm-syntax output for AST fixture {string}",
    fn(name : String) raise {
      guard self.parsed().ast is Some(file) else { fail("expected an AST") }
      let expected = @fs.read_file_to_string(
          "../tests/fixtures/ast/\{name}.json",
        )
        .trim_end(chars="\n")
        .to_owned()
      @expect.expect(@ast.encode_file(file).stringify()).to_equal(expected)
    },
  )
  setup.when0("I parse the source", fn() {
    let source = @krueger.SourceText::{ module_name: None, text: self.source, }
    self.result = Some(@krueger.parse_module(source, dialect=self.dialect))
  })
  setup.then0("parsing succeeds without diagnostics", fn() raise {
    @expect.expect_all(soft => {
      let result = self.parsed()
      soft.expect(result.diagnostics.map(d => d.code)).to_equal([])
      soft.expect(result.ast is Some(_)).to_be_true()
    })
  })
  setup.then1("the AST JSON equals the elm-syntax output for {string}", fn(
    name : String,
  ) raise {
    guard self.parsed().ast is Some(file) else { fail("expected an AST") }
    let expected = @fs.read_file_to_string(
        "../tests/fixtures/parser/\{name}.json",
      )
      .trim_end(chars="\n")
      .to_owned()
    @expect.expect(@ast.encode_file(file).stringify()).to_equal(expected)
  })
  setup.then2("declaration {string} has documentation {string}", fn(
    name : String,
    expected : String,
  ) raise {
    guard find_custom_type(self.parsed(), name) is Some(t) else {
      fail("expected type declaration \{name}")
    }
    @expect.expect(t.documentation.map(d => d.value)).to_equal(Some(expected))
  })
  setup.then1("declaration {string} has no documentation", fn(
    name : String,
  ) raise {
    guard find_custom_type(self.parsed(), name) is Some(t) else {
      fail("expected type declaration \{name}")
    }
    @expect.expect(t.documentation is None).to_be_true()
  })
  setup.then1("the file comments are {string}", fn(expected : String) raise {
    guard self.parsed().ast is Some(file) else { fail("expected an AST") }
    @expect.expect(file.comments.map(c => c.value).join(", ")).to_equal(
      expected,
    )
  })
  setup.then0("both comments are preserved in CST or token trivia", fn() raise {
    @expect.expect_all(soft => {
      let result = self.parsed()
      soft.expect(has_comment_kind_in_cst(result, Doc)).to_be_true()
      soft.expect(has_comment_kind_in_cst(result, Line)).to_be_true()
    })
  })
  setup.then1("the diagnostics are {string}", fn(expected : String) raise {
    @expect.expect(self.parsed().diagnostics.map(d => d.code).join(", ")).to_equal(
      expected,
    )
  })
  setup.then1("the diagnostics include {string}", fn(code : String) raise {
    @expect.expect(self.parsed().diagnostics.map(d => d.code)).to_contain_element(
      code,
    )
  })
  setup.then0("the AST has no declarations", fn() raise {
    guard self.parsed().ast is Some(file) else { fail("expected an AST") }
    @expect.expect(file.declarations.length()).to_equal(0)
  })
  setup.then1("the CST has declaration {string}", fn(name : String) raise {
    guard self.parsed().cst is Some(cst) else { fail("expected a CST") }
    @expect.expect(cst.declarations.map(cst_declaration_name)).to_contain_element(
      name,
    )
  })
  setup.then0("there is no AST", fn() raise {
    @expect.expect(self.parsed().ast is None).to_be_true()
  })
  setup.then0("parsing returns diagnostics", fn() raise {
    @expect.expect(self.parsed().diagnostics.length() > 0).to_be_true()
  })
  setup.then0(
    "at least one diagnostic reports malformed comment with a source span",
    fn() raise {
      let found = self.parsed().diagnostics.any(d => {
        (d.code == "KR-SCAN-001" || d.code == "KR-SCAN-002") &&
        d.span.start.offset <= d.span.end.offset
      })
      @expect.expect(found).to_be_true()
    },
  )
}

///|
async test "parser feature" {
  @moonspec.run_or_fail(
    ParserWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("../tests/features/parser.feature"),
    ]),
  )
  |> ignore
}
