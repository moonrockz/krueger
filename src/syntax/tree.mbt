///|
/// A parse result as a tree with random access: parents, ancestors, paths,
/// the node at a position and the tokens in a range. It is built once and
/// never changes; its indexes are private.
pub struct Tree {
  priv root : NodeRef
  /// identity key → (node, parent) for every node below the root.
  priv parents : Map[String, Array[(NodeRef, NodeRef)]]
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
/// The tree of `result`, or `None` when the parse produced no AST.
pub fn Tree::new(result : @parser.ParseResult) -> Tree? {
  guard NodeRef::of_result(result) is Some(root) else { return None }
  let parents : Map[String, Array[(NodeRef, NodeRef)]] = Map([])
  // An explicit stack: trees can be deeper than the call stack allows.
  let stack = [root]
  while stack.pop() is Some(node) {
    for child in node.children() {
      let key = identity(child)
      match parents.get(key) {
        Some(bucket) => bucket.push((child, node))
        None => parents[key] = [(child, node)]
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
  guard self.parents.get(identity(n)) is Some(bucket) else { return None }
  if bucket.length() == 1 {
    return if same(bucket[0].0, n) { Some(bucket[0].1) } else { None }
  }
  for entry in bucket {
    if same(entry.0, n) {
      return Some(entry.1)
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
/// ranges the deeper node wins, then the first in source order.
pub fn Tree::node_at(self : Tree, p : @ast.Location) -> NodeRef? {
  if !contains(self.root.range(), p) {
    return None
  }
  let mut best = self.root
  let mut best_depth = 0
  // An explicit stack, visited in source order.
  let stack = [(self.root, 0)]
  while stack.pop() is Some((node, depth)) {
    let r = node.range()
    let b = best.range()
    if (within(r, b) && r != b) || (r == b && depth > best_depth) {
      best = node
      best_depth = depth
    }
    let inside = node.children().filter(c => contains(c.range(), p))
    inside.rev_each(c => stack.push((c, depth + 1)))
  }
  Some(best)
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
/// trivia arrays, so changing them changes nothing in the tree.
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
