///|
/// A parse result as a tree with random access: parents, ancestors, paths,
/// the node at a position and the tokens in a range. It is built once and
/// never changes; its indexes are private.
pub struct Tree {
  priv root : NodeRef
  /// The root's `children_with_fields()`, built once: a file can have
  /// thousands, and every `node_at` starts there.
  priv root_children : Array[(PathStep, NodeRef)]
  /// The root's range, built once: a file's range reads all its imports,
  /// declarations and comments.
  priv root_range : @ast.Range
  /// Key → the first index entry with that key; one entry for every node
  /// below the root.
  priv parents : Map[Key, Entry]
  /// In source order: starts and ends both ascend.
  priv tokens : Array[@scanner.Token]
}

///|
/// A node below the root, with its parent and its path from the root: the
/// steps innermost first (the first is the step from the parent) and their
/// number. A child's steps are one list cell on its parent's, so the index
/// holds one cell per node, not a whole path. `next` is the next entry with
/// the same key, in the order of `Tree::new`.
priv struct Entry {
  node : NodeRef
  parent : NodeRef
  steps : @list.List[PathStep]
  depth : Int32
  mut next : Entry?
}

///|
/// The step from the parent to the entry's node.
fn Entry::step(self : Entry) -> PathStep? {
  self.steps.head()
}

///|
/// The path from the root to the entry's node.
fn Entry::path(self : Entry) -> NodePath {
  { reversed: self.steps, length: self.depth, }
}

///|
/// The index key of a node: its case and its range. Two different nodes
/// with the same key are told apart by structural equality.
priv struct Key {
  case_ : Int32
  start_row : Int32
  start_column : Int32
  end_row : Int32
  end_column : Int32
} derive(Eq, Hash)

///|
fn key_of(n : NodeRef) -> Key {
  let r = n.range()
  {
    case_: case_number(n),
    start_row: r.start.row,
    start_column: r.start.column,
    end_row: r.end.row,
    end_column: r.end.column,
  }
}

///|
/// The number of the node's case: a key part that needs no string.
fn case_number(n : NodeRef) -> Int32 {
  match n {
    File(_, _) => 0
    Module(_) => 1
    ModuleName(_) => 2
    Exposing(_) => 3
    Expose(_) => 4
    Import(_) => 5
    Declaration(_, _) => 6
    Documentation(_) => 7
    Signature(_) => 8
    Implementation(_) => 9
    Constructor(_) => 10
    Expression(_) => 11
    LetDeclaration(_) => 12
    Case(_) => 13
    RecordSetter(_) => 14
    Pattern(_) => 15
    TypeAnnotation(_) => 16
    RecordField(_) => 17
    Name(_) => 18
    Comment(_) => 19
    Attribute(_) => 20
  }
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
  let parents : Map[Key, Entry] = Map([])
  let tails : Map[Key, Entry] = Map([])
  let root_children = root.children_with_fields()
  // An explicit stack: trees can be deeper than the call stack allows. A
  // child's path is one step on its parent's path, so it shares its steps.
  let stack : Array[(NodeRef, @list.List[PathStep], Int32)] = [
    (root, @list.List([]), 0),
  ]
  while stack.pop() is Some((node, steps, depth)) {
    let kids = if depth == 0 {
      root_children
    } else {
      node.children_with_fields()
    }
    for entry in kids {
      let (step, child) = entry
      let key = key_of(child)
      let item = {
        node: child,
        parent: node,
        steps: steps.prepend(step),
        depth: depth + 1,
        next: None,
      }
      match parents.get(key) {
        // The item goes last, so the first entry stays first. `tails` has
        // the last entry of each chain longer than one, so that many nodes
        // with one key (a hand-built AST with one range) stay linear.
        Some(first) => {
          tails.get(key).unwrap_or(first).next = Some(item)
          tails[key] = item
        }
        None => parents[key] = item
      }
      stack.push((child, item.steps, item.depth))
    }
  }
  let tokens = match result.cst {
    Some(cst) => cst.tokens.map(copy_token)
    None => []
  }
  Some({ root, root_children, root_range: root.range(), parents, tokens, })
}

///|
/// The file node at the top of the tree.
pub fn Tree::root(self : Tree) -> NodeRef {
  self.root
}

///|
/// The parent of `n`, or `None` for the root and for nodes not in the tree.
pub fn Tree::parent(self : Tree, n : NodeRef) -> NodeRef? {
  self.entry(n).map(e => e.parent)
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
  self.entry(n).bind(e => e.step())
}

///|
/// The field of the parent of `n` that holds `n`, or `None` for the root and
/// for nodes not in the tree. It gives what `parent.field_of(n)` gives, but
/// reads the tree's index, so a walk can call it for every node. See `step`
/// for an example.
pub fn Tree::field_of(self : Tree, n : NodeRef) -> String? {
  self.entry(n).bind(e => e.step()).map(s => s.field)
}

///|
/// The index entry of `n`, or `None` for the root and for nodes not in the
/// tree.
fn Tree::entry(self : Tree, n : NodeRef) -> Entry? {
  let mut next = self.parents.get(key_of(n))
  while next is Some(entry) {
    if same(entry.node, n) {
      return Some(entry)
    }
    next = entry.next
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
  // One lookup: the index keeps each node's path. Only a node that is not
  // below the root is compared with the root.
  match self.entry(n) {
    Some(entry) => Some(entry.path())
    None => if same(n, self.root) { Some(NodePath::root()) } else { None }
  }
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
  innermost_at(
    self.root,
    p,
    start_children=self.root_children,
    start_range=self.root_range,
  ).map(found => found.0)
}

///|
/// The innermost node at or below `start` whose range contains `p` (the rule
/// of `Tree::node_at`), with each step down: the child's index among its
/// siblings and the siblings (its parent's `children_with_fields()`), or
/// `None` when `start` does not contain `p`. `start_children` and
/// `start_range` are the start node's children and range when the caller has
/// them already.
fn innermost_at(
  start : NodeRef,
  p : @ast.Location,
  start_children? : Array[(PathStep, NodeRef)],
  start_range? : @ast.Range,
) -> (NodeRef, Array[(Int32, Array[(PathStep, NodeRef)])])? {
  let start_range = match start_range {
    Some(r) => r
    None => start.range()
  }
  if !contains(start_range, p) {
    return None
  }
  let mut best = start
  let mut best_range = start_range
  let mut best_trail : @list.List[(Int32, Array[(PathStep, NodeRef)])] = @list.List([],
  )
  let mut best_depth = 0
  // An explicit stack, visited in source order, with each node's range. A
  // trail holds the steps from `start`, innermost first.
  let stack : Array[
    (
      NodeRef,
      @ast.Range,
      Int32,
      @list.List[(Int32, Array[(PathStep, NodeRef)])],
    ),
  ] = [(start, start_range, 0, @list.List([]))]
  while stack.pop() is Some((node, r, depth, trail)) {
    let b = best_range
    if (within(r, b) && r != b) || (r == b && depth > best_depth) {
      best = node
      best_range = r
      best_trail = trail
      best_depth = depth
    }
    let kids = match (depth, start_children) {
      (0, Some(kids)) => kids
      _ => node.children_with_fields()
    }
    for i = kids.length() - 1; i >= 0; i = i - 1 {
      let kid_range = kids[i].1.range()
      if contains(kid_range, p) {
        stack.push((kids[i].1, kid_range, depth + 1, trail.prepend((i, kids))))
      }
    }
  }
  let steps = best_trail.to_array()
  steps.rev_in_place()
  Some((best, steps))
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
  // The tokens tile the source, so their starts and their ends both ascend:
  // search for the first token that starts at or after `r.start`, then take
  // tokens until one ends after `r.end`.
  let tokens = self.tokens
  let mut lo = 0
  let mut hi = tokens.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if at_or_before(r.start, token_start(tokens[mid])) {
      hi = mid
    } else {
      lo = mid + 1
    }
  }
  let found = []
  for i in lo..<tokens.length() {
    guard at_or_before(token_end(tokens[i]), r.end) else { break }
    found.push(copy_token(tokens[i]))
  }
  found
}

///|
fn token_start(t : @scanner.Token) -> @ast.Location {
  { row: t.span.start.line, column: t.span.start.column, }
}

///|
fn token_end(t : @scanner.Token) -> @ast.Location {
  { row: t.span.end.line, column: t.span.end.column, }
}
