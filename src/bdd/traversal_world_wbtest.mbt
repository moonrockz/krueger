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
impl @moonspec.World for TraversalWorld with fn configure(self, setup) {
  setup.given1("the Elm file {string}", fn(path : String) raise {
    self.text = @fs.read_file_to_string(path)
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
    "walk, fold and accept visit the same nodes as the children pre-order",
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
    })
  })
  setup.then1("the entered nodes are:", fn(doc : @moonspec.DocString) raise {
    @expect.expect(self.entered.join("\n")).to_equal(doc.content)
  })
}

///|
async test "traversal feature" {
  @moonspec.run_or_fail(
    TraversalWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("tests/features/traversal.feature"),
    ]),
  )
  |> ignore
}
