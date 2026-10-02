///|
/// Scenario state for `tests/features/printer.feature`.
struct PrinterWorld {
  mut source : String
  mut printed : Result[String, String]
}

///|
fn PrinterWorld::new() -> PrinterWorld {
  { source: "", printed: Err("not run"), }
}

///|
fn printed_source(text : String, width : Int) -> Result[String, String] {
  let result = @krueger.parse_module(@krueger.SourceText::new(text))
  guard result.ast is Some(file) else { return Err("no AST") }
  try @krueger.print_file(file, width~) catch {
    e => Err(@debug.to_string(e))
  } noraise {
    s => Ok(s)
  }
}

///|
fn without_final_newlines(s : String) -> String {
  s.trim_end(chars="\n").to_owned()
}

///|
impl @moonspec.World for PrinterWorld with fn configure(self, setup) {
  setup.given("the Elm module:", fn(ctx) {
    match ctx[0] {
      { value: @moonspec.StepValue::DocStringVal(doc), .. } =>
        self.source = doc.content
      _ => ()
    }
  })
  setup.when("I print its AST", fn(_ctx) {
    self.printed = printed_source(self.source, 120)
  })
  setup.when1("I print its AST with width {int}", fn(width : Int) {
    self.printed = printed_source(self.source, width)
  })
  setup.then("the printed source equals the module", fn(_ctx) raise {
    @expect.expect(self.printed.map(without_final_newlines)).to_equal(
      Ok(without_final_newlines(self.source)),
    )
  })
  setup.then("the printed source is:", fn(ctx) raise {
    guard ctx[0] is { value: @moonspec.StepValue::DocStringVal(doc), .. } else {
      fail("the step needs a doc string")
    }
    @expect.expect(self.printed.map(without_final_newlines)).to_equal(
      Ok(without_final_newlines(doc.content)),
    )
  })
}

///|
async test "printer feature" {
  @moonspec.run_or_fail(
    PrinterWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("../tests/features/printer.feature"),
    ]),
  )
  |> ignore
}
