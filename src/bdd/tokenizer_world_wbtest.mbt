struct TokenizerWorld {
  mut saw_step : Bool
} derive(Default)

impl @moonspec.World for TokenizerWorld with configure(self, setup) {
  setup.given("a tokenizer world", fn(_ctx) {
    self.saw_step = true
  })
}

async test "tokenizer bdd harness is wired through moonspec" {
  let feature =
    #|Feature: Tokenizer BDD Harness
    #|  Scenario: Minimal smoke
    #|    Given a tokenizer world
  let options =
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::Text("test://tokenizer-harness", feature),
    ])
  @moonspec.run_or_fail(TokenizerWorld::default, options) |> ignore
}
