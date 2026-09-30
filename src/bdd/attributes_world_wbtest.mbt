///|
/// Scenario state for `tests/features/attributes.feature`.
struct AttributesWorld {
  mut source : String
  mut dialect : @krueger.Dialect
  mut result : @krueger.ParseResult?
}

///|
fn AttributesWorld::new() -> AttributesWorld {
  { source: "", dialect: @krueger.Dialect::elm_0_19_1(), result: None, }
}

///|
fn AttributesWorld::parsed(
  self : AttributesWorld,
) -> @krueger.ParseResult raise {
  guard self.result is Some(r) else { fail("the source was not parsed") }
  r
}

///|
/// The source text of `range` (rows and columns count code points).
fn slice(source : String, range : @krueger.Range) -> String {
  let lines = source.split("\n").map(l => l.to_owned().to_array()).collect()
  let sb = StringBuilder()
  for row = range.start.row; row <= range.end.row; row = row + 1 {
    let chars = lines.get(row - 1).unwrap_or([])
    let from = if row == range.start.row { range.start.column - 1 } else { 0 }
    let to = if row == range.end.row {
      range.end.column - 1
    } else {
      chars.length()
    }
    for i = from; i < to && i < chars.length(); i = i + 1 {
      sb.write_char(chars[i])
    }
    if row < range.end.row {
      sb.write_string("\\n")
    }
  }
  sb.to_string()
}

///|
fn render_attributes(source : String, result : @krueger.ParseResult) -> String {
  let lines = []
  for group in result.attributes {
    let target = match group.target {
      Module => "module"
      Declaration(name~, ..) => name
    }
    for attribute in group.attributes {
      match attribute {
        Attribute(name~, arguments~, range~) =>
          lines.push(
            "\{target} @\{name.value}(" +
            arguments.map(a => slice(source, a.range)).join(" | ") +
            ") \{range.start.row}:\{range.start.column}",
          )
        Docs(names~, range~) =>
          lines.push(
            "\{target} @docs(" +
            names.map(n => n.value).join(", ") +
            ") \{range.start.row}:\{range.start.column}",
          )
      }
    }
  }
  lines.join("\n")
}

///|
impl @moonspec.World for AttributesWorld with fn configure(self, setup) {
  setup.given1("Elm source:", fn(doc : @moonspec.DocString) {
    self.source = doc.content
  })
  setup.given1("the Elm file {string}", fn(path : String) raise {
    self.source = @fs.read_file_to_string(path)
  })
  setup.given0("the attribute syntax is off", fn() {
    self.dialect = { ..@krueger.Dialect::elm_0_19_1(), attributes: Off, }
  })
  setup.when0("I parse the source", fn() {
    let source = @krueger.SourceText::{ module_name: None, text: self.source, }
    self.result = Some(@krueger.parse_module(source, dialect=self.dialect))
  })
  setup.then1("the attributes are:", fn(doc : @moonspec.DocString) raise {
    @expect.expect(render_attributes(self.source, self.parsed())).to_equal(
      doc.content,
    )
  })
  setup.then0("there are no attributes", fn() raise {
    @expect.expect(self.parsed().attributes.length()).to_equal(0)
  })
  setup.then0("there are no warnings", fn() raise {
    @expect.expect(self.parsed().diagnostics.map(d => d.code)).to_equal([])
  })
  setup.then2("warning {string} is reported at {string}", fn(
    code : String,
    at : String,
  ) raise {
    let found = self.parsed().diagnostics.any(d => {
      d.code == code &&
      d.severity is Warning &&
      "\{d.span.start.line}:\{d.span.start.column}" == at
    })
    @expect.expect(found).to_equal(true)
  })
}

///|
async test "attributes feature" {
  @moonspec.run_or_fail(
    AttributesWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("tests/features/attributes.feature"),
    ]),
  )
  |> ignore
}
