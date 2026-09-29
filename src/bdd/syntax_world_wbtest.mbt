///|
/// Scenario state for `tests/features/syntax_json.feature`.
struct SyntaxWorld {
  mut fixture : String
  mut encoded : Result[String, String]
}

///|
fn SyntaxWorld::new() -> SyntaxWorld {
  { fixture: "", encoded: Err("not run"), }
}

///|
impl @moonspec.World for SyntaxWorld with fn configure(self, setup) {
  setup.given1("the elm-syntax JSON fixture {string}", fn(name : String) raise {
    self.fixture = @fs.read_file_to_string("tests/fixtures/syntax/\{name}.json")
      .trim_end(chars="\n")
      .to_owned()
  })
  setup.when0("I decode and encode the fixture", fn() {
    self.encoded = try
      @syntax.encode_file(@syntax.decode_file(@json.parse(self.fixture))).stringify()
    catch {
      err => Err(err.to_string())
    } noraise {
      text => Ok(text)
    }
  })
  setup.then0("the encoded JSON equals the fixture byte for byte", fn() raise {
    @expect.expect(self.encoded).to_equal(Ok(self.fixture))
  })
}

///|
async test "syntax json feature" {
  @moonspec.run_or_fail(
    SyntaxWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("tests/features/syntax_json.feature"),
    ]),
  )
  |> ignore
}
