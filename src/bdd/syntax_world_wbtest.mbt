///|
/// Scenario state for `tests/features/syntax.feature`.
struct SyntaxWorld {
  mut text : String
  mut tree : @krueger.Tree?
}

///|
fn SyntaxWorld::new() -> SyntaxWorld {
  { text: "", tree: None, }
}

///|
fn SyntaxWorld::built(self : SyntaxWorld) -> @krueger.Tree raise {
  guard self.tree is Some(tree) else { fail("no syntax tree was built") }
  tree
}

///|
/// Every node below `root` (and `root`), with an explicit stack.
fn syntax_nodes(root : @krueger.NodeRef) -> Array[@krueger.NodeRef] {
  let found = []
  let stack = [root]
  while stack.pop() is Some(node) {
    found.push(node)
    for c in node.children() {
      stack.push(c)
    }
  }
  found
}

///|
fn syntax_before_or_at(a : @krueger.Location, b : @krueger.Location) -> Bool {
  a.row < b.row || (a.row == b.row && a.column <= b.column)
}

///|
fn syntax_label(n : @krueger.NodeRef) -> String {
  let r = n.range()
  "\{n.category()}/\{n.kind()} \{r.start.row}:\{r.start.column}-\{r.end.row}:\{r.end.column}"
}

///|
/// Children outside their parent or out of source order.
fn containment_problems(tree : @krueger.Tree) -> Array[String] {
  let problems = []
  for node in syntax_nodes(tree.root()) {
    let r = node.range()
    let mut previous : @krueger.Location? = None
    for c in node.children() {
      let cr = c.range()
      if !syntax_before_or_at(r.start, cr.start) ||
        !syntax_before_or_at(cr.end, r.end) {
        problems.push("\{syntax_label(c)} is outside \{syntax_label(node)}")
      }
      if previous is Some(p) && !syntax_before_or_at(p, cr.start) {
        problems.push(
          "\{syntax_label(c)} is out of order in \{syntax_label(node)}",
        )
      }
      previous = Some(cr.start)
    }
  }
  problems
}

///|
fn parent_problems(tree : @krueger.Tree) -> Array[String] {
  let problems = []
  for node in syntax_nodes(tree.root()) {
    for c in node.children() {
      if tree.parent(c) != Some(node) {
        problems.push(
          "parent of \{syntax_label(c)} is not \{syntax_label(node)}",
        )
      }
    }
  }
  problems
}

///|
fn field_problems(tree : @krueger.Tree) -> Array[String] {
  let table : Map[String, Array[String]] = Map([])
  for row in @krueger.kind_table() {
    let (category, kind, fields) = row
    table["\{category}/\{kind}"] = fields
  }
  let problems = []
  for node in syntax_nodes(tree.root()) {
    match table.get("\{node.category()}/\{node.kind()}") {
      None => problems.push("\{syntax_label(node)} is not in the kind table")
      Some(fields) => {
        if node.fields() != fields {
          problems.push(
            "\{syntax_label(node)} has fields \{node.fields().join(", ")}",
          )
        }
        for c in node.children() {
          match node.field_of(c) {
            Some(f) if fields.contains(f) => ()
            _ => problems.push("\{syntax_label(c)} has no field in its parent")
          }
        }
      }
    }
  }
  problems
}

///|
fn node_at_problems(tree : @krueger.Tree) -> Array[String] {
  let problems = []
  for node in syntax_nodes(tree.root()) {
    let r = node.range()
    // An empty range contains no position.
    if r.start == r.end {
      continue
    }
    match tree.node_at(r.start) {
      Some(found) if tree.path(found).contains(node) => ()
      _ => problems.push("node_at misses \{syntax_label(node)}")
    }
  }
  problems
}

///|
/// The kind table as the markdown AGENTS.md shows between its markers.
fn kind_table_markdown() -> String {
  let lines = ["| Category | Kind | Fields |", "|---|---|---|"]
  for row in @krueger.kind_table() {
    let (category, kind, fields) = row
    let cell = if fields.is_empty() { "—" } else { fields.join(", ") }
    lines.push("| `\{category}` | `\{kind}` | \{cell} |")
  }
  lines.join("\n")
}

///|
/// The text between `<!-- kinds:start -->` and `<!-- kinds:end -->`.
fn marked_kind_table(text : String) -> String raise {
  let lines = text.split("\n").map(l => l.to_owned()).collect()
  guard lines.search("<!-- kinds:start -->") is Some(start) &&
    lines.search("<!-- kinds:end -->") is Some(end) &&
    start < end else {
    fail("AGENTS.md has no kind table markers")
  }
  lines[start + 1:end].join("\n").trim().to_owned()
}

///|
impl @moonspec.World for SyntaxWorld with fn configure(self, setup) {
  setup.given1("the Elm file {string}", fn(path : String) raise {
    self.text = @fs.read_file_to_string(path)
  })
  setup.given1("the file {string}", fn(path : String) raise {
    self.text = @fs.read_file_to_string(path)
  })
  // The fixtures are elm-syntax output, so they parse in its dialect (effect
  // modules included).
  setup.when0("I build the syntax tree", fn() {
    let source = @krueger.SourceText::{ module_name: None, text: self.text, }
    self.tree = @krueger.Tree::new(
      @krueger.parse_module(
        source,
        dialect=@krueger.Dialect::elm_syntax_7_3_9(),
      ),
    )
  })
  setup.then0("every child lies inside its parent, in source order", fn() raise {
    @expect.expect(containment_problems(self.built())).to_equal([])
  })
  setup.then0("every child's parent is the node it came from", fn() raise {
    @expect.expect(parent_problems(self.built())).to_equal([])
  })
  setup.then0("every node's fields match the kind table", fn() raise {
    @expect.expect(field_problems(self.built())).to_equal([])
  })
  setup.then0(
    "node_at at the start of every node finds that node or a descendant",
    fn() raise { @expect.expect(node_at_problems(self.built())).to_equal([]) },
  )
  setup.then0("the kind table between the markers matches the node model", fn() raise {
    @expect.expect(marked_kind_table(self.text)).to_equal(kind_table_markdown())
  })
}

///|
async test "syntax feature" {
  @moonspec.run_or_fail(
    SyntaxWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("tests/features/syntax.feature"),
    ]),
  )
  |> ignore
}
