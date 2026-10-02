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
    None | Some(WriteLock) | Some(WritePrinted) => ()
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
        problems.append(walk_problems(key, tree.root(), count))
        problems.append(descent_problems(key, tree))
        problems.append(scan_problems(key, text))
        problems.append(
          scan_problems(key + " (CRLF)", text.replace_all(old="\n", new="\r\n")),
        )
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

///|
/// A node's occurrence tag: category, kind, full range.
fn walk_tag(n : @krueger.NodeRef) -> String {
  let r = n.range()
  "\{n.category()}/\{n.kind()}@\{r.start.row}:\{r.start.column}-\{r.end.row}:\{r.end.column}"
}

///|
/// Counts the nodes a visitor leaves (defaults elsewhere).
struct LeaveCount {
  mut count : Int
}

///|
impl @krueger.Visitor for LeaveCount with fn leave(self, _) {
  self.count = self.count + 1
}

///|
/// walk, fold and accept over one corpus file: walk enters the `count` nodes
/// in children() pre-order (tag and depth), every leave gets the object of
/// the latest open enter, and fold and accept see `count` nodes.
fn walk_problems(
  key : String,
  root : @krueger.NodeRef,
  count : Int,
) -> Array[String] {
  let pre = []
  let pre_starts = []
  let stack = [(root, 0)]
  while stack.pop() is Some((n, depth)) {
    pre.push("\{depth} \{walk_tag(n)}")
    let s = n.range().start
    pre_starts.push("\{depth} \{n.category()}/\{n.kind()}@\{s.row}:\{s.column}")
    n.children().rev_each(c => stack.push((c, depth + 1)))
  }
  let entered = []
  let open : Array[@krueger.NodeRef] = []
  let mut nested = true
  let walk_fields : Array[String?] = []
  @krueger.walk(
    root,
    n => {
      entered.push("\{open.length()} \{walk_tag(n)}")
      walk_fields.push(open.last().bind(parent => parent.field_of(n)))
      open.push(n)
      Continue
    },
    leave=n => {
      if !(open.pop() is Some(o) && physical_equal(o, n)) {
        nested = false
      }
    },
  )
  let folded = @krueger.fold(root, 0, (k, _) => (k + 1, Continue))
  let visitor = { count: 0, }
  @krueger.accept(root, visitor)
  let problems = []
  if pre.length() != count || folded != count || visitor.count != count {
    problems.push(
      "\{key}: walk/fold/accept visit \{entered.length()}/\{folded}/\{visitor.count} nodes, expected \{count}",
    )
  }
  if entered != pre {
    problems.push("\{key}: walk order is not the children() pre-order")
  }
  if !nested || !open.is_empty() {
    problems.push("\{key}: a leave does not match its enter")
  }
  // The event reader: enters with their own depth and field, in pre-order;
  // every event's depth matches its path, every Leave its Enter's, and every
  // 8th path resolves to its node.
  let read = []
  let read_fields = []
  let open = []
  let mut paths_agree = true
  let reader = @krueger.EventReader::new(root)
  while reader.next() is Some(e) {
    match e {
      Enter({ category, kind, field, start, depth, path, }) => {
        let start_tag = "\{category}/\{kind}@\{start.row}:\{start.column}"
        read.push("\{depth} \{start_tag}")
        read_fields.push(field)
        paths_agree = paths_agree && depth == path.depth()
        if read.length() % 8 == 1 {
          paths_agree = paths_agree &&
            path
            .resolve(root)
            .map(n => {
              let s = n.range().start
              "\{n.category()}/\{n.kind()}@\{s.row}:\{s.column}"
            }) ==
            Some(start_tag)
        }
        open.push(path)
      }
      Leave({ depth, path, .. }) =>
        paths_agree = paths_agree &&
          open.pop() == Some(path) &&
          depth == path.depth()
    }
  }
  if read_fields != walk_fields {
    problems.push("\{key}: an Enter's field is not its parent's field_of it")
  }
  if read != pre_starts || !open.is_empty() || !paths_agree {
    problems.push(
      "\{key}: the event reader's order is not the children() pre-order",
    )
  }
  // A full cursor navigation: first child, next sibling, parent.
  let navigated = []
  let c = @krueger.TreeCursor::new(root)
  navigated.push("\{c.depth()} \{walk_tag(c.node())}")
  let mut going = true
  while going {
    if c.goto_first_child() {
      navigated.push("\{c.depth()} \{walk_tag(c.node())}")
      continue
    }
    while !c.goto_next_sibling() {
      if !c.goto_parent() {
        going = false
        break
      }
    }
    if going {
      navigated.push("\{c.depth()} \{walk_tag(c.node())}")
    }
  }
  if navigated != pre {
    problems.push("\{key}: the cursor's order is not the children() pre-order")
  }
  problems
}

///|
fn corpus_contains(r : @krueger.Range, p : @krueger.Location) -> Bool {
  let after_start = r.start.row < p.row ||
    (r.start.row == p.row && r.start.column <= p.column)
  let before_end = p.row < r.end.row ||
    (p.row == r.end.row && p.column < r.end.column)
  after_start && before_end
}

///|
/// At every 8th non-empty node start, a cursor descent with
/// goto_first_child_for ends at `Tree::node_at`.
fn descent_problems(key : String, tree : @krueger.Tree) -> Array[String] {
  let root = tree.root()
  let starts = []
  let mut i = 0
  @krueger.walk(root, n => {
    let r = n.range()
    if r.start != r.end {
      if i % 8 == 0 {
        starts.push(r.start)
      }
      i = i + 1
    }
    Continue
  })
  let problems = []
  for p in starts {
    let c = @krueger.TreeCursor::new(root)
    while c.goto_first_child_for(p) {
      if !corpus_contains(c.node().range(), p) {
        ignore(c.goto_parent())
        break
      }
    }
    match tree.node_at(p) {
      Some(found) if walk_tag(found) == walk_tag(c.node()) => ()
      _ =>
        problems.push(
          "\{key}: a cursor descent to \{p.row}:\{p.column} does not end at node_at",
        )
    }
  }
  problems
}

///|
fn corpus_trivia(t : @krueger.Trivia) -> (String, @krueger.Span) {
  match t {
    Whitespace(s, span) | Newline(s, span) => (s, span)
    Comment(c) => (c.text, c.span)
  }
}

///|
fn scan_problems(key : String, text : String) -> Array[String] {
  let source = @krueger.SourceText::{ module_name: None, text, }
  guard @krueger.tokenize(source) is Ok(ts) else {
    return ["\{key}: the scanner reports errors"]
  }
  let pieces = ts.trivia.map(corpus_trivia)
  for t in ts.tokens {
    pieces.append(t.trivia_before.map(corpus_trivia))
    pieces.push((t.lexeme, t.span))
    pieces.append(t.trivia_after.map(corpus_trivia))
  }
  let problems = []
  if pieces.map(p => p.0).join("") != text {
    problems.push("\{key}: tokens and trivia do not rebuild the text")
  }
  // One pass over the text for every boundary (offsets in order when the
  // pieces tile the text; an offset out of order maps to `None`).
  let offsets = []
  for p in pieces {
    offsets.push(p.1.start.offset)
    offsets.push(p.1.end.offset)
  }
  let expected = @lawkit.positions_of(text, offsets)
  let mut at = 0
  for k, p in pieces {
    let (piece, span) = p
    let agrees = (q : @krueger.Position, e : @ast.Location?) => {
      @lawkit.between_characters(text, q.offset) &&
      e == Some({ row: q.line, column: q.column, })
    }
    if span.start.offset != at ||
      span.end.offset != at + piece.length() ||
      !agrees(span.start, expected[2 * k]) ||
      !agrees(span.end, expected[2 * k + 1]) {
      problems.push(
        "\{key}: a span at offset \{span.start.offset} does not tile the text",
      )
      break
    }
    at = span.end.offset
  }
  if problems.is_empty() && at != text.length() {
    problems.push("\{key}: the pieces stop at offset \{at}")
  }
  problems
}
