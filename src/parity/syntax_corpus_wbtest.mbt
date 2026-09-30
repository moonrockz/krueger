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
/// Node model problems in one corpus file: kinds missing from the kind table,
/// children outside their parent, wrong parents, and `node_at` misses.
fn syntax_problems(
  key : String,
  tree : @krueger.Tree,
  kinds : Map[String, Bool],
) -> (Int, Array[String]) {
  let problems = []
  let nodes = syntax_nodes(tree.root())
  for node in nodes {
    let r = node.range()
    let label = "\{key}: \{node.category()}/\{node.kind()} at \{r.start.row}:\{r.start.column}"
    if !kinds.contains("\{node.category()}/\{node.kind()}") {
      problems.push("\{label} is not in the kind table")
    }
    for c in node.children() {
      let cr = c.range()
      if !syntax_before_or_at(r.start, cr.start) ||
        !syntax_before_or_at(cr.end, r.end) {
        problems.push("\{label} has a child outside it")
      }
      if tree.parent(c) != Some(node) {
        problems.push("\{label} is not the parent of its child")
      }
    }
    // An empty range contains no position.
    if r.start != r.end {
      match tree.node_at(r.start) {
        Some(found) if tree.path(found).contains(node) => ()
        _ => problems.push("\{label}: node_at misses it")
      }
    }
  }
  (nodes.length(), problems)
}

///|
/// The node model over the corpus. Runs in the parity modes that score.
test "syntax corpus" {
  match parity_mode() {
    None | Some(WriteLock) => ()
    Some(_) => {
      let kinds : Map[String, Bool] = Map([])
      for row in @krueger.kind_table() {
        let (category, kind, _) = row
        kinds["\{category}/\{kind}"] = true
      }
      let dialect = @krueger.Dialect::elm_syntax_7_3_9()
      let problems = []
      let mut files = 0
      let mut nodes = 0
      for source in manifest_sources() {
        let (key, sha256) = source
        let text = verified_source(key, sha256)
        let result = @krueger.parse_module(
          @krueger.SourceText::{ module_name: None, text, },
          dialect~,
        )
        guard @krueger.Tree::new(result) is Some(tree) else {
          problems.push("\{key}: no syntax tree")
          continue
        }
        let (count, found) = syntax_problems(key, tree, kinds)
        files = files + 1
        nodes = nodes + count
        problems.append(found)
      }
      println("syntax: \{files} files, \{nodes} nodes")
      if !problems.is_empty() {
        fail(
          "syntax: \{problems.length()} problems:\n" +
          problems.iter().take(10).collect().join("\n"),
        )
      }
    }
  }
}
