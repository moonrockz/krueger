///|
/// Scenario state for `tests/features/parity_report.feature`.
struct ReportWorld {
  mut baseline : Counts?
  files : Array[FileReport]
  mut output : String
}

///|
fn ReportWorld::new() -> ReportWorld {
  { baseline: None, files: [], output: "", }
}

///|
fn ReportWorld::report(self : ReportWorld) -> ParityReport {
  parity_report(self.files, self.baseline, commit=Some("abc123"))
}

///|
fn count_occurrences(text : String, needle : String) -> Int {
  text.split(needle).count() - 1
}

///|
fn json_field(json : Json, name : String) -> Json raise {
  guard json is Object(o) && o.get(name) is Some(v) else {
    fail("missing JSON field \{name}")
  }
  v
}

///|
fn string_field(json : Json, name : String) -> String? {
  match json {
    Object(o) =>
      match o.get(name) {
        Some(String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
fn json_counts(json : Json) -> String raise {
  let c = counts_from_json(json)
  "\{c.files} files, \{c.tokenized} tokenized, \{c.parsed} parsed, \{c.matched} matched"
}

///|
impl @moonspec.World for ReportWorld with fn configure(self, setup) {
  setup.given4(
    "a parity run with baseline {int} files, {int} tokenized, {int} parsed, {int} matched",
    fn(files : Int, tokenized : Int, parsed : Int, matched : Int) {
      self.baseline = Some({ files, tokenized, parsed, matched, })
    },
  )
  setup.given4(
    "the baseline was {int} files, {int} tokenized, {int} parsed, {int} matched",
    fn(files : Int, tokenized : Int, parsed : Int, matched : Int) {
      self.baseline = Some({ files, tokenized, parsed, matched, })
    },
  )
  setup.given1("the file {string} matched", fn(key : String) {
    self.files.push({
      key,
      tokenized: true,
      parsed: true,
      matched: true,
      diagnostic: None,
      difference: None,
    })
  })
  setup.given2("the file {string} parsed but differs at {string}", fn(
    key : String,
    path : String,
  ) {
    self.files.push({
      key,
      tokenized: true,
      parsed: true,
      matched: false,
      diagnostic: None,
      difference: Some(path),
    })
  })
  setup.given4("the file {string} failed with {string} at {string} {string}", fn(
    key : String,
    code : String,
    position : String,
    message : String,
  ) raise {
    guard position.split_once(":") is Some((line, column)) else {
      fail("position must be line:column")
    }
    self.files.push({
      key,
      tokenized: true,
      parsed: false,
      matched: false,
      diagnostic: Some({
        code,
        message,
        line: @string.parse_int(line),
        column: @string.parse_int(column),
      }),
      difference: None,
    })
  })
  setup.when0("I render the JSON report", fn() {
    self.output = report_json(self.report()).stringify()
  })
  setup.then4(
    "the JSON counts are {int} files, {int} tokenized, {int} parsed, {int} matched",
    fn(files : Int, tokenized : Int, parsed : Int, matched : Int) raise {
      @expect.expect(
        json_counts(json_field(@json.parse(self.output), "counts")),
      ).to_equal(
        "\{files} files, \{tokenized} tokenized, \{parsed} parsed, \{matched} matched",
      )
    },
  )
  setup.then4(
    "the JSON delta is {int} files, {int} tokenized, {int} parsed, {int} matched",
    fn(files : Int, tokenized : Int, parsed : Int, matched : Int) raise {
      @expect.expect(json_counts(json_field(@json.parse(self.output), "delta"))).to_equal(
        "\{files} files, \{tokenized} tokenized, \{parsed} parsed, \{matched} matched",
      )
    },
  )
  setup.then1("the JSON report lists {int} files", fn(n : Int) raise {
    guard json_field(@json.parse(self.output), "files") is Array(files) else {
      fail("files is not an array")
    }
    @expect.expect(files.length()).to_equal(n)
  })
  setup.then2("JSON file {string} has diagnostic {string}", fn(
    key : String,
    code : String,
  ) raise {
    guard json_field(@json.parse(self.output), "files") is Array(files) else {
      fail("files is not an array")
    }
    let found = files.any(f => {
      string_field(f, "key") == Some(key) &&
      (match f {
        Object(o) =>
          match o.get("diagnostic") {
            Some(d) => string_field(d, "code") == Some(code)
            None => false
          }
        _ => false
      })
    })
    @expect.expect(found).to_be_true()
  })
  setup.when0("I render the JUnit report", fn() {
    self.output = report_junit(self.report())
  })
  setup.then3(
    "the JUnit report has a testsuite {string} with {int} tests and {int} skipped",
    fn(name : String, tests : Int, skipped : Int) raise {
      @expect.expect(self.output).to_contain(
        "<testsuite name=\"\{name}\" tests=\"\{tests}\" failures=\"0\" skipped=\"\{skipped}\">",
      )
    },
  )
  setup.then1("the JUnit report contains {string}", fn(text : String) raise {
    @expect.expect(self.output).to_contain(text)
  })
  setup.then0("the JUnit baseline testcase passes", fn() raise {
    @expect.expect(self.output).to_contain(
      "<testcase classname=\"baseline\" name=\"counts do not drop below the baseline\"/>",
    )
  })
  setup.when0("I render the HTML report", fn() {
    self.output = report_html(self.report())
  })
  setup.then1("the HTML report contains {string}", fn(text : String) raise {
    @expect.expect(self.output).to_contain(text)
  })
  setup.then1("the HTML report has {int} file rows", fn(n : Int) raise {
    @expect.expect(count_occurrences(self.output, "<tr class=\"file\"")).to_equal(
      n,
    )
  })
  setup.when0("I render the Markdown summary", fn() {
    self.output = report_markdown(self.report())
  })
  setup.then1("the summary contains {string}", fn(text : String) raise {
    @expect.expect(self.output).to_contain(text)
  })
  setup.then2("the summary lists {string} before {string}", fn(
    first : String,
    second : String,
  ) raise {
    guard self.output.find("| \{first} |") is Some(a) &&
      self.output.find("| \{second} |") is Some(b) else {
      fail("expected both codes in the summary")
    }
    @expect.expect(a < b).to_be_true()
  })
}

///|
async test "parity report feature" {
  @moonspec.run_or_fail(
    ReportWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("tests/features/parity_report.feature"),
    ]),
  )
  |> ignore
}
