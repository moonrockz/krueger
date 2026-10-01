///|
fn event_label(e : @syntax.Event) -> String {
  match e {
    Enter(e) => {
      let f = match e.field {
        Some(f) => " " + f
        None => ""
      }
      "+\{e.category}/\{e.kind}\{f} \{e.start.row}:\{e.start.column}"
    }
    Leave(e) => "-" + label(e.node)
  }
}

///|
fn read_all(r : @syntax.EventReader) -> Array[String] {
  let out = []
  while r.next() is Some(e) {
    out.push(event_label(e))
  }
  out
}

///|
test "an event reader gives walk's events with fields and starts" {
  @expect.expect(read_all(@syntax.EventReader::new(parse_root(small)))).to_equal([
      "+file/file 1:1", "+module/normal moduleDefinition 1:1", "+module_name/module_name moduleName 1:8",
      "-module_name/module_name", "+exposing/all exposingList 1:10", "-exposing/all",
      "-module/normal", "+declaration/function declarations 4:1", "+implementation/implementation declaration 4:1",
      "+name/name name 4:1", "-name/name", "+expression/application expression 5:5",
      "+expression/functionOrValue application 5:5", "-expression/functionOrValue",
      "+expression/integer application 5:7", "-expression/integer", "-expression/application",
      "-implementation/implementation", "-declaration/function", "-file/file",
    ],
  )
}

///|
test "skip_children right after an Enter makes the next event its Leave" {
  @expect.expect_all(s => {
    let r = @syntax.EventReader::new(parse_root(small))
    let out = []
    while r.next() is Some(e) {
      out.push(event_label(e))
      if e is Enter({ category: "declaration", .. }) {
        r.skip_children()
      }
    }
    let i = out.search("+declaration/function declarations 4:1").unwrap()
    s.expect(out[i + 1]).to_equal("-declaration/function")
    // file, module (with its name and exposing), the skipped declaration.
    s.expect(out.length()).to_equal(10)
  })
}

///|
test "skip_children elsewhere does nothing" {
  @expect.expect_all(s => {
    let root = parse_root(small)
    let r = @syntax.EventReader::new(root)
    // Before the first event, after a Leave, and after the end.
    r.skip_children()
    let out = []
    while r.next() is Some(e) {
      out.push(event_label(e))
      if e is Leave(_) {
        r.skip_children()
      }
    }
    r.skip_children()
    s.expect(out).to_equal(read_all(@syntax.EventReader::new(root)))
    s.expect(r.next()).to_equal(None)
  })
}

///|
test "a finished reader returns None every time" {
  @expect.expect_all(s => {
    let r = @syntax.EventReader::new(parse_root(small))
    ignore(read_all(r))
    s.expect(r.next()).to_equal(None)
    s.expect(r.next()).to_equal(None)
  })
}

///|
test "two readers over one tree do not affect each other" {
  @expect.expect_all(s => {
    let root = parse_root(expression_source)
    let a = @syntax.EventReader::new(root)
    let b = @syntax.EventReader::new(root)
    let from_a = []
    let from_b = []
    // b reads two events for each one a reads.
    let mut more = true
    while more {
      more = false
      if a.next() is Some(e) {
        from_a.push(event_label(e))
        more = true
      }
      for _ in 0..<2 {
        if b.next() is Some(e) {
          from_b.push(event_label(e))
          more = true
        }
      }
    }
    let alone = read_all(@syntax.EventReader::new(root))
    s.expect(from_a).to_equal(alone)
    s.expect(from_b).to_equal(alone)
  })
}

///|
test "an event reader handles a 398-level tree" {
  let root = tree_of(deep_source()).root()
  let out = read_all(@syntax.EventReader::new(root))
  @expect.expect(out.length()).to_equal(2 * (399 + 398 + 7))
}

///|
test "events carry the depth and path of their node" {
  let r = @syntax.EventReader::new(parse_root(small))
  let seen = []
  while r.next() is Some(e) {
    match e {
      Enter(e) if e.kind == "integer" || e.kind == "file" =>
        seen.push("+\{e.kind} \{e.depth} \{e.path}")
      Leave(e) if label(e.node) == "expression/integer" =>
        seen.push("-integer \{e.depth} \{e.path}")
      _ => ()
    }
  }
  @expect.expect(seen).to_equal([
    "+file 0 ", "+integer 4 declarations[0].declaration[0].expression[0].application[1]",
    "-integer 4 declarations[0].declaration[0].expression[0].application[1]",
  ])
}

///|
test "iter continues where next stopped, and ends after the root's Leave" {
  let root = @syntax.NodeRef::of_result(
    parse_result("module M exposing (..)\n\nf x = x\n"),
  ).unwrap()
  let all = read_all(@syntax.EventReader::new(root))
  let reader = @syntax.EventReader::new(root)
  let first = reader.next().map(event_label)
  let rest = reader.iter().map(event_label).to_array()
  @expect.expect_all(s => {
    s.expect(first).to_equal(Some(all[0]))
    s.expect(rest).to_equal(all[1:].to_owned())
    s.expect(reader.iter().to_array()).to_equal([])
  })
}
