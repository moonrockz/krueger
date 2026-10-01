///|
/// Scenario state for `tests/features/traversal.feature`.
struct TraversalWorld {
  mut text : String
  mut tree : @krueger.Tree?
  mut entered : Array[String]
}

///|
fn TraversalWorld::new() -> TraversalWorld {
  { text: "", tree: None, entered: [], }
}

///|
fn TraversalWorld::root(self : TraversalWorld) -> @krueger.NodeRef raise {
  guard self.tree is Some(tree) else { fail("no syntax tree was built") }
  tree.root()
}

///|
fn traversal_label(n : @krueger.NodeRef) -> String {
  let r = n.range()
  "\{n.category()}/\{n.kind()} \{r.start.row}:\{r.start.column}-\{r.end.row}:\{r.end.column}"
}

///|
/// Pre-order over children(), independent of walk.
fn children_preorder(root : @krueger.NodeRef) -> Array[String] {
  let out = []
  let stack = [root]
  while stack.pop() is Some(n) {
    out.push(traversal_label(n))
    n.children().rev_each(c => stack.push(c))
  }
  out
}

///|
/// Records every node for the consistency check.
struct Collect {
  seen : Array[String]
}

///|
fn Collect::add(self : Collect, n : @krueger.NodeRef) -> @krueger.Control {
  self.seen.push(traversal_label(n))
  Continue
}

///|
impl @krueger.Visitor for Collect with fn visit_other(self, n) {
  self.add(n)
}

///|
impl @krueger.Visitor for Collect with fn visit_declaration(self, n) {
  self.add(n)
}

///|
impl @krueger.Visitor for Collect with fn visit_function(self, n) {
  self.add(n)
}

///|
impl @krueger.Visitor for Collect with fn visit_expression(self, n) {
  self.add(n)
}

///|
impl @krueger.Visitor for Collect with fn visit_pattern(self, n) {
  self.add(n)
}

///|
impl @krueger.Visitor for Collect with fn visit_type(self, n) {
  self.add(n)
}

///|
impl @krueger.Visitor for Collect with fn visit_case(self, n) {
  self.add(n)
}

///|
impl @krueger.Visitor for Collect with fn visit_import(self, n) {
  self.add(n)
}

///|
impl @krueger.Visitor for Collect with fn visit_comment(self, n) {
  self.add(n)
}

///|
impl @krueger.Visitor for Collect with fn visit_attribute(self, n) {
  self.add(n)
}

///|
/// A node's category, kind and start: what an `Enter` event shows.
fn start_label(
  category : String,
  kind : String,
  start : @krueger.Location,
) -> String {
  "\{category}/\{kind} \{start.row}:\{start.column}"
}

///|
/// Records the start label of every pushed `Enter`.
struct StartLog {
  starts : Array[String]
}

///|
impl @krueger.Handler for StartLog with fn on_enter(self, e) {
  self.starts.push(start_label(e.category, e.kind, e.start))
  Continue
}

///|
/// The nodes a full cursor navigation (first child, next sibling, parent)
/// enters.
fn cursor_preorder(root : @krueger.NodeRef) -> Array[String] {
  let c = @krueger.TreeCursor::new(root)
  let out = [traversal_label(c.node())]
  while true {
    if c.goto_first_child() {
      out.push(traversal_label(c.node()))
      continue
    }
    while !c.goto_next_sibling() {
      if !c.goto_parent() {
        return out
      }
    }
    out.push(traversal_label(c.node()))
  }
  out
}

///|
/// The number written with the decimal digits `s`, if it has only digits.
fn digits(s : StringView) -> Int? {
  let mut n = 0
  for c in s {
    if c < '0' || c > '9' {
      return None
    }
    n = n * 10 + (c.to_int() - '0'.to_int())
  }
  if s.is_empty() {
    None
  } else {
    Some(n)
  }
}

///|
/// A node path as the features show it: `(start)` for the start node.
fn shown_path(path : @krueger.NodePath) -> String {
  if path.depth() == 0 {
    "(start)"
  } else {
    path.to_string()
  }
}

///|
/// Checks that each pushed Leave closes the latest open Enter.
struct PairCheck {
  open : Array[@krueger.NodePath]
  mut problems : Int
}

///|
impl @krueger.Handler for PairCheck with fn on_enter(self, e) {
  self.open.push(e.path)
  Continue
}

///|
impl @krueger.Handler for PairCheck with fn on_leave(self, e) {
  if self.open.pop() != Some(e.path) {
    self.problems = self.problems + 1
  }
}

///|
impl @moonspec.World for TraversalWorld with fn configure(self, setup) {
  setup.given1("the Elm file {string}", fn(path : String) raise {
    self.text = @fs.read_file_to_string(repo_path(path))
  })
  setup.given1("Elm source:", fn(doc : @moonspec.DocString) {
    self.text = doc.content
  })
  // The fixtures are elm-syntax output, so they parse in its dialect.
  setup.when0("I build the syntax tree", fn() {
    let source = @krueger.SourceText::{ module_name: None, text: self.text, }
    self.tree = @krueger.Tree::new(
      @krueger.parse_module(
        source,
        dialect=@krueger.Dialect::elm_syntax_7_3_9(),
      ),
    )
  })
  setup.when0("I walk it and skip the children of functions", fn() raise {
    let entered = []
    @krueger.walk(self.root(), n => {
      entered.push("\{n.category()}/\{n.kind()}")
      if n.kind() == "function" && n.category() == "declaration" {
        SkipChildren
      } else {
        Continue
      }
    })
    self.entered = entered
  })
  setup.then0(
    "walk, fold, accept, the event reader, push_events and a cursor visit the same nodes as the children pre-order",
    fn() raise {
      @expect.expect_all(soft => {
        let root = self.root()
        let expected = children_preorder(root)
        let walked = []
        @krueger.walk(root, n => {
          walked.push(traversal_label(n))
          Continue
        })
        let folded = @krueger.fold(root, [], (acc : Array[String], n) => {
          acc.push(traversal_label(n))
          (acc, Continue)
        })
        let visitor = { seen: [], }
        @krueger.accept(root, visitor)
        soft.expect(walked).to_equal(expected)
        soft.expect(folded).to_equal(expected)
        soft.expect(visitor.seen).to_equal(expected)
        // Events show only a node's start.
        let starts = []
        @krueger.walk(root, n => {
          starts.push(start_label(n.category(), n.kind(), n.range().start))
          Continue
        })
        let read = []
        let reader = @krueger.EventReader::new(root)
        while reader.next() is Some(e) {
          if e is Enter({ category, kind, start, .. }) {
            read.push(start_label(category, kind, start))
          }
        }
        let pushed : StartLog = { starts: [], }
        @krueger.push_events(@krueger.EventReader::new(root), pushed)
        soft.expect(read).to_equal(starts)
        soft.expect(pushed.starts).to_equal(starts)
        soft.expect(cursor_preorder(root)).to_equal(expected)
      })
    },
  )
  setup.then0("every entered node is left once, after its children", fn() raise {
    @expect.expect_all(soft => {
      // Each leave gets the same object as the most recent unmatched enter.
      let open : Array[@krueger.NodeRef] = []
      let mut problems = 0
      @krueger.walk(
        self.root(),
        n => {
          open.push(n)
          Continue
        },
        leave=n => {
          if !(open.pop() is Some(o) && physical_equal(o, n)) {
            problems = problems + 1
          }
        },
      )
      soft.expect(problems).to_equal(0)
      soft.expect(open.length()).to_equal(0)
      // The event reader and push_events: each Leave closes the latest open
      // Enter, with the same path and the node that path leads to.
      let root = self.root()
      let reader = @krueger.EventReader::new(root)
      let paths : Array[@krueger.NodePath] = []
      let mut reader_problems = 0
      while reader.next() is Some(e) {
        match e {
          Enter(e) => paths.push(e.path)
          Leave(e) =>
            if !(paths.pop() == Some(e.path) &&
              e.path.resolve(root).map(traversal_label) ==
              Some(traversal_label(e.node))) {
              reader_problems = reader_problems + 1
            }
        }
      }
      soft.expect(reader_problems).to_equal(0)
      soft.expect(paths.length()).to_equal(0)
      let pairs : PairCheck = { open: [], problems: 0, }
      @krueger.push_events(@krueger.EventReader::new(root), pairs)
      soft.expect(pairs.problems).to_equal(0)
      soft.expect(pairs.open.length()).to_equal(0)
    })
  })
  setup.then1("the entered nodes are:", fn(doc : @moonspec.DocString) raise {
    @expect.expect(self.entered.join("\n")).to_equal(doc.content)
  })
  setup.when0("I read its events", fn() raise {
    let lines = []
    let reader = @krueger.EventReader::new(self.root())
    while reader.next() is Some(e) {
      match e {
        Enter(e) =>
          lines.push(
            "+ \{e.category}/\{e.kind} \{e.depth} \{shown_path(e.path)}",
          )
        Leave(e) =>
          lines.push(
            "- \{e.node.category()}/\{e.node.kind()} \{e.depth} \{shown_path(e.path)}",
          )
      }
    }
    self.entered = lines
  })
  setup.then1("the events are:", fn(doc : @moonspec.DocString) raise {
    @expect.expect(self.entered.join("\n")).to_equal(doc.content)
  })
  setup.when1("I move a cursor toward {string}", fn(at : String) raise {
    guard at.split(":").map(digits).collect() is [Some(row), Some(column)] else {
      fail("expected row:column, got \{at}")
    }
    let c = @krueger.TreeCursor::new(self.root())
    let lines = []
    while c.goto_first_child_for({ row, column, }) {
      let n = c.node()
      lines.push(
        "\{n.category()}/\{n.kind()} \{c.field_name().unwrap_or("-")} \{shown_path(c.path())}",
      )
    }
    self.entered = lines
  })
  setup.then1("the cursor passes through:", fn(
    doc : @moonspec.DocString,
  ) raise {
    @expect.expect(self.entered.join("\n")).to_equal(doc.content)
  })
}

///|
async test "traversal feature" {
  @moonspec.run_or_fail(
    TraversalWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("../tests/features/traversal.feature"),
    ]),
  )
  |> ignore
}
