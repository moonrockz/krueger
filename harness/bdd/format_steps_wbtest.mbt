///|
/// Scenario state for `tests/features/format.feature`.
struct FormatWorld {
  mut source : String
  mut output : Result[String, String]
}

///|
fn FormatWorld::new() -> FormatWorld {
  { source: "", output: Err("not run"), }
}

///|
impl @moonspec.World for FormatWorld with fn configure(self, setup) {
  setup.given("the Elm source:", fn(ctx) raise {
    guard ctx.args()
      is [{ value: @moonspec.StepValue::DocStringVal(doc), .. }, ..] else {
      fail("the step needs a doc string")
    }
    self.source = doc.content
  })
  setup.when("I format it", fn(_ctx) {
    self.output = try @krueger.format(self.source) catch {
      e => Err(@debug.to_string(e))
    } noraise {
      s => Ok(s)
    }
  })
  setup.then("the output is:", fn(ctx) raise {
    guard ctx.args()
      is [{ value: @moonspec.StepValue::DocStringVal(doc), .. }, ..] else {
      fail("the step needs a doc string")
    }
    // A doc string has no final line feed.
    @expect.expect(self.output.map(s => s.trim_end().to_owned())).to_equal(
      Ok(doc.content),
    )
  })
}

///|
async test "format feature" {
  @moonspec.run_or_fail(
    FormatWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("../tests/features/format.feature"),
    ]),
  )
  |> ignore
}
