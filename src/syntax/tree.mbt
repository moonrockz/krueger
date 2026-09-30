///|
/// A parse result as a tree with random access: parents, ancestors, paths,
/// the node at a position and the tokens in a range. It is built once and
/// never changes; its indexes are private.
pub struct Tree {
  priv root : NodeRef
  /// identity key → (node, parent) for every node below the root.
  priv parents : Map[String, Array[(NodeRef, NodeRef)]]
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
  Some({ root, parents, })
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
