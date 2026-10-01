///|
/// A parse result as a tree with random access: parents, ancestors, paths,
/// the node at a position and the tokens in a range. It is built once and
/// never changes; its indexes are private.
pub struct Tree {
  priv root : NodeRef
  /// identity key → (node, parent, step in the parent) for every node below
  /// the root.
  priv parents : Map[String, Array[(NodeRef, NodeRef, PathStep)]]
  priv tokens : Array[@scanner.Token]
}

///|
/// The index key of a node: category, kind and range. Two different nodes
/// with the same key are told apart by structural equality.
fn identity(n : NodeRef) -> String {
  let r = n.range()
  "\{n.category()}/\{n.kind()}/\{r.start.row}:\{r.start.column}-\{r.end.row}:\{r.end.column}"
}

///|
/// The tree of `result`, or `None` when the parse produced no AST. It walks
/// the whole tree once to index the parents, so build it once and keep it.
///
/// ```mbt check
/// test {
///   let src = "module Main exposing (..)\n\nadd x y =\n    x + y\n"
///   let result = @parser.parse_module(
///     @scanner.SourceText::new(src),
///     @scanner.DefaultScanner::new(),
///   )
///   let tree = @syntax.Tree::new(result).unwrap()
///   let decl = tree.root().field("declarations")[0]
///   let body = decl.field("declaration")[0].field("expression")[0]
///   inspect(tree.parent(body).unwrap().kind(), content="implementation")
///   inspect(tree.parent(tree.root()) is None, content="true")
///   debug_inspect(
///     tree.ancestors(body).map(n => n.kind()),
///     content="[\"implementation\", \"function\", \"file\"]",
///   )
///   debug_inspect(
///     tree.path(body).map(n => n.kind()),
///     content="[\"file\", \"function\", \"implementation\", \"operatorapplication\"]",
///   )
/// }
/// ```
pub fn Tree::new(result : @parser.ParseResult) -> Tree? {
  guard NodeRef::of_result(result) is Some(root) else { return None }
  let parents : Map[String, Array[(NodeRef, NodeRef, PathStep)]] = Map([])
  // An explicit stack: trees can be deeper than the call stack allows.
  let stack = [root]
  while stack.pop() is Some(node) {
    for entry in node.children_with_fields() {
      let (step, child) = entry
      let key = identity(child)
      let item = (child, node, step)
      match parents.get(key) {
        Some(bucket) => bucket.push(item)
        None => parents[key] = [item]
      }
      stack.push(child)
    }
  }
  let tokens = match result.cst {
    Some(cst) => cst.tokens.map(copy_token)
    None => []
  }
  Some({ root, parents, tokens, })
}

///|
/// The file node at the top of the tree.
pub fn Tree::root(self : Tree) -> NodeRef {
  self.root
}

///|
/// The parent of `n`, or `None` for the root and for nodes not in the tree.
pub fn Tree::parent(self : Tree, n : NodeRef) -> NodeRef? {
  self.parent_entry(n).map(e => e.0)
}

///|
/// The step from the parent of `n` to `n` (its field and its index in that
/// field), or `None` for the root and for nodes not in the tree. It reads
/// the tree's index, so it does not look through the parent's fields.
///
/// ```mbt check
/// test {
///   let src = "module Main exposing (..)\n\nadd x y =\n    x + y\n"
///   let result = @parser.parse_module(
///     @scanner.SourceText::new(src),
///     @scanner.DefaultScanner::new(),
///   )
///   let tree = @syntax.Tree::new(result).unwrap()
///   let implementation = tree.root().field("declarations")[0].field("declaration")[0]
///   let y = implementation.field("arguments")[1]
///   debug_inspect(
///     tree.step(y),
///     content="Some({ field: \"arguments\", index: 1 })",
///   )
///   debug_inspect(tree.field_of(y), content="Some(\"arguments\")")
///   debug_inspect(tree.field_of(tree.root()), content="None")
/// }
/// ```
pub fn Tree::step(self : Tree, n : NodeRef) -> PathStep? {
  self.parent_entry(n).map(e => e.1)
}

///|
/// The field of the parent of `n` that holds `n`, or `None` for the root and
/// for nodes not in the tree. It gives what `parent.field_of(n)` gives, but
/// reads the tree's index, so a walk can call it for every node. See `step`
/// for an example.
pub fn Tree::field_of(self : Tree, n : NodeRef) -> String? {
  self.parent_entry(n).map(e => e.1.field)
}

///|
/// The parent of `n` and the step from the parent to `n`.
fn Tree::parent_entry(self : Tree, n : NodeRef) -> (NodeRef, PathStep)? {
  guard self.parents.get(identity(n)) is Some(bucket) else { return None }
  for entry in bucket {
    if same(entry.0, n) {
      return Some((entry.1, entry.2))
    }
  }
  None
}

///|
/// The parents of `n`, nearest first, ending at the root (a new array).
pub fn Tree::ancestors(self : Tree, n : NodeRef) -> Array[NodeRef] {
  let found = []
  let mut current = n
  while self.parent(current) is Some(p) {
    found.push(p)
    current = p
  }
  found
}

///|
/// The nodes from the root down to `n`, both included (a new array).
pub fn Tree::path(self : Tree, n : NodeRef) -> Array[NodeRef] {
  let path = self.ancestors(n)
  path.rev_in_place()
  path.push(n)
  path
}

///|
/// The steps from the root to `n`, or `None` when `n` is not in the tree.
/// With `node_at`, this takes an editor from a position to a path.
///
/// ```mbt check
/// test {
///   let src = "module Main exposing (..)\n\nadd x y =\n    x + y\n"
///   let result = @parser.parse_module(
///     @scanner.SourceText::new(src),
///     @scanner.DefaultScanner::new(),
///   )
///   let tree = @syntax.Tree::new(result).unwrap()
///   // Row 4, column 9 is the `y` in `x + y`.
///   let y = tree.node_at({ row: 4, column: 9, }).unwrap()
///   inspect("\{y.category()}/\{y.kind()}", content="expression/functionOrValue")
///   inspect(
///     tree.node_path(y).unwrap(),
///     content="declarations[0].declaration[0].expression[0].right[0]",
///   )
/// }
/// ```
pub fn Tree::node_path(self : Tree, n : NodeRef) -> NodePath? {
  // Up the parent index (the steps nearest first), then down from the root.
  let steps = []
  let mut current = n
  while self.parent_entry(current) is Some((parent, step)) {
    steps.push(step)
    current = parent
  }
  guard same(current, self.root) else { return None }
  let mut path = NodePath::root()
  for step in steps.rev_iter() {
    path = path.child(step.field, step.index)
  }
  Some(path)
}

///|
fn at_or_before(a : @ast.Location, b : @ast.Location) -> Bool {
  a.row < b.row || (a.row == b.row && a.column <= b.column)
}

///|
/// Whether `r` contains `p` (`start <= p < end`; an empty range contains
/// nothing).
fn contains(r : @ast.Range, p : @ast.Location) -> Bool {
  at_or_before(r.start, p) && !at_or_before(r.end, p)
}

///|
/// Whether `a` fits inside `b`.
fn within(a : @ast.Range, b : @ast.Range) -> Bool {
  at_or_before(b.start, a.start) && at_or_before(a.end, b.end)
}

///|
/// The innermost node whose range contains `p`, or `None` outside the file.
/// Every branch that contains `p` is searched, because siblings can overlap: a
/// comment (a child of the file) lies inside a declaration, and a port's doc
/// comment holds the port's attributes. The smallest range wins; for equal
/// ranges the deeper node wins, then the first in source order. See
/// `node_path` for an example.
pub fn Tree::node_at(self : Tree, p : @ast.Location) -> NodeRef? {
  innermost_at(self.root, p).map(found => found.0)
}

///|
/// The innermost node at or below `start` whose range contains `p` (the rule
/// of `Tree::node_at`), with the index of each step down in its parent's
/// `children()`, or `None` when `start` does not contain `p`.
fn innermost_at(start : NodeRef, p : @ast.Location) -> (NodeRef, Array[Int])? {
  if !contains(start.range(), p) {
    return None
  }
  let mut best = start
  let mut best_trail : @list.List[Int] = @list.empty()
  let mut best_depth = 0
  // An explicit stack, visited in source order. A trail holds the child
  // indices from `start`, innermost first.
  let stack : Array[(NodeRef, Int, @list.List[Int])] = [
    (start, 0, @list.empty()),
  ]
  while stack.pop() is Some((node, depth, trail)) {
    let r = node.range()
    let b = best.range()
    if (within(r, b) && r != b) || (r == b && depth > best_depth) {
      best = node
      best_trail = trail
      best_depth = depth
    }
    let kids = node.children()
    for i = kids.length() - 1; i >= 0; i = i - 1 {
      if contains(kids[i].range(), p) {
        stack.push((kids[i], depth + 1, trail.add(i)))
      }
    }
  }
  let indices = best_trail.to_array()
  indices.rev_in_place()
  Some((best, indices))
}

///|
/// A token whose trivia arrays are new: a `Token`'s trivia lists are mutable
/// arrays, so the tree never shares them with the parse result or a caller.
fn copy_token(t : @scanner.Token) -> @scanner.Token {
  {
    ..t,
    trivia_before: t.trivia_before.copy(),
    trivia_after: t.trivia_after.copy(),
  }
}

///|
/// The tokens that lie inside `r`, in source order: new tokens with new
/// trivia arrays, so changing them changes nothing in the tree. A token
/// that lies only partly inside `r` is left out. The tree has no tokens when
/// the parse produced no CST.
///
/// ```mbt check
/// test {
///   let src = "module Main exposing (..)\n\nadd x y =\n    x + y\n"
///   let result = @parser.parse_module(
///     @scanner.SourceText::new(src),
///     @scanner.DefaultScanner::new(),
///   )
///   let tree = @syntax.Tree::new(result).unwrap()
///   let decl = tree.root().field("declarations")[0]
///   let lexemes = tree.tokens_in(decl.range()).map(t => t.lexeme)
///   debug_inspect(
///     lexemes,
///     content="[\"add\", \"x\", \"y\", \"=\", \"x\", \"+\", \"y\"]",
///   )
/// }
/// ```
pub fn Tree::tokens_in(self : Tree, r : @ast.Range) -> Array[@scanner.Token] {
  self.tokens
  .filter(t => {
    let start : @ast.Location = {
      row: t.span.start.line,
      column: t.span.start.column,
    }
    let end : @ast.Location = {
      row: t.span.end.line,
      column: t.span.end.column,
    }
    at_or_before(r.start, start) && at_or_before(end, r.end)
  })
  .map(copy_token)
}
