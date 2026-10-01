///|
/// Scenario state for `tests/features/parity.feature`.
struct ParityWorld {
  mut json : Json
  mut golden : Json
  mut lock_text : String
  mut lock_result : Result[String, String]
  mut counts : Counts
  mut baseline : Counts
  mut manifest : Array[(String, String)]
}

///|
fn ParityWorld::new() -> ParityWorld {
  let zero = { files: 0, tokenized: 0, parsed: 0, matched: 0, }
  {
    json: Json::null(),
    golden: Json::null(),
    lock_text: "",
    lock_result: Ok(""),
    counts: zero,
    baseline: zero,
    manifest: [],
  }
}

///|
impl @moonspec.World for ParityWorld with fn configure(self, setup) {
  setup.given1("the JSON {string}", fn(text : String) raise {
    self.json = @json.parse(text)
  })
  setup.then1("the canonical form is {string}", fn(expected : String) raise {
    @expect.expect(canonical(self.json)).to_equal(expected)
  })
  setup.given1("the lock text:", fn(doc : @moonspec.DocString) {
    self.lock_text = doc.content
  })
  setup.when0("I read and write the lock", fn() {
    self.lock_result = try format_lock(parse_lock(self.lock_text)) catch {
      err => Err(err.to_string())
    } noraise {
      text => Ok(text)
    }
  })
  setup.then1("the lock text is:", fn(doc : @moonspec.DocString) raise {
    @expect.expect(self.lock_result).to_equal(Ok(doc.content + "\n"))
  })
  setup.then0("reading the lock fails", fn() raise {
    @expect.expect(self.lock_result is Err(_)).to_be_true()
  })
  setup.given4(
    "the counts {int} files, {int} tokenized, {int} parsed, {int} matched",
    fn(files : Int, tokenized : Int, parsed : Int, matched : Int) {
      self.counts = { files, tokenized, parsed, matched, }
    },
  )
  setup.given4(
    "the baseline {int} files, {int} tokenized, {int} parsed, {int} matched",
    fn(files : Int, tokenized : Int, parsed : Int, matched : Int) {
      self.baseline = { files, tokenized, parsed, matched, }
    },
  )
  setup.then1("the regressions are {string}", fn(expected : String) raise {
    @expect.expect(regressions(self.counts, self.baseline).join("; ")).to_equal(
      expected,
    )
  })
  setup.given1("the manifest sources {string}", fn(text : String) {
    self.manifest = text
      .split(", ")
      .map(item => {
        let parts = item.split(" ").map(p => p.to_owned()).collect()
        (parts[0], parts[1])
      })
      .collect()
  })
  setup.then1("the source problems are {string}", fn(expected : String) raise {
    let lock = parse_lock(self.lock_text)
    @expect.expect(source_problems(lock, self.manifest).join("; ")).to_equal(
      expected,
    )
  })
  setup.then1("ratcheting gives {string}", fn(expected : String) raise {
    let actual = match ratchet(self.counts, self.baseline) {
      Ok(c) =>
        "\{c.files} files, \{c.tokenized} tokenized, \{c.parsed} parsed, \{c.matched} matched"
      Err(message) => "refused: \{message}"
    }
    @expect.expect(actual).to_equal(expected)
  })
  setup.then1("the S-expression is {string}", fn(expected : String) raise {
    @expect.expect(sexpr(self.json)).to_equal(expected)
  })
  setup.given1("the golden JSON {string}", fn(text : String) raise {
    self.golden = @json.parse(text)
  })
  setup.given1("the krueger JSON {string}", fn(text : String) raise {
    self.json = @json.parse(text)
  })
  setup.then1("the first difference is at {string}", fn(path : String) raise {
    guard first_difference(self.golden, self.json) is Some(d) else {
      fail("expected a difference")
    }
    @expect.expect(d.path).to_equal(path)
  })
}

///|
async test "parity feature" {
  @moonspec.run_or_fail(
    ParityWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("../tests/features/parity.feature"),
    ]),
  )
  |> ignore
}
