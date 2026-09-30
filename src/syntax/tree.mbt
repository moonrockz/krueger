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
    Some(cst) => cst.tokens
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
    return if bucket[0].0 == n { Some(bucket[0].1) } else { None }
  }
  for entry in bucket {
    if entry.0 == n {
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
/// At each level the smallest child containing `p` wins, so a comment inside
/// a declaration (both children of the file) is found.
pub fn Tree::node_at(self : Tree, p : @ast.Location) -> NodeRef? {
  if !contains(self.root.range(), p) {
    return None
  }
  let mut current = self.root
  while true {
    let mut best : NodeRef? = None
    for child in current.children() {
      if contains(child.range(), p) {
        best = match best {
          Some(b) if !within(child.range(), b.range()) => Some(b)
          Some(b) if child.range() == b.range() => Some(b)
          _ => Some(child)
        }
      }
    }
    match best {
      Some(b) => current = b
      None => break
    }
  }
  Some(current)
}

///|
/// The tokens that lie inside `r`, in source order (a new array).
pub fn Tree::tokens_in(self : Tree, r : @ast.Range) -> Array[@scanner.Token] {
  self.tokens.filter(t => {
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
}
