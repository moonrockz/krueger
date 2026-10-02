///|
// Task 6 is the first non-test user; it removes this suppression.
#warnings("-unused_value-unused_field")
priv enum Role {
  Leading
  Trailing
  Inner
} derive(Eq, Debug)

///|
// Task 6 is the first non-test user; it removes this suppression.
#warnings("-unused_value-unused_field")
priv struct Placed {
  comment : @ast.Node[String]
  owner : @ast.Range
  child : @ast.Range?
  role : Role
}

///|
/// The placed comments and a lookup by role and range. `printed` marks the
/// comments that the printer has written.
// Task 6 is the first non-test user; it removes this suppression.
#warnings("-unused_value-unused_field")
priv struct CommentTable {
  placed : Array[Placed]
  printed : Array[Bool]
  index : Map[(Int, Int, Int, Int, Int), Array[Int]]
}

///|
fn at_or_before(a : @ast.Location, b : @ast.Location) -> Bool {
  compare_location(a, b) <= 0
}

///|
fn range_contains(r : @ast.Range, l : @ast.Location) -> Bool {
  at_or_before(r.start, l) && compare_location(l, r.end) < 0
}

///|
fn role_index(role : Role) -> Int {
  match role {
    Leading => 0
    Trailing => 1
    Inner => 2
  }
}

///|
fn index_key(role : Role, r : @ast.Range) -> (Int, Int, Int, Int, Int) {
  (role_index(role), r.start.row, r.start.column, r.end.row, r.end.column)
}

///|
fn is_skipped(node : @syntax.NodeRef) -> Bool {
  node.category() is ("comment" | "attribute")
}

///|
/// Decides for each regular comment which node owns it and in which role:
/// `Trailing` when a child ends on the comment's row before it, else
/// `Leading` of the next child, else `Inner` of the owner. Doc comments are
/// not placed.
// Task 6 is the first non-test user; it removes this suppression.
#warnings("-unused_value")
fn place_comments(file : @ast.File) -> CommentTable {
  let root : @syntax.NodeRef = File(file, [][:])
  let placed = []
  let index : Map[(Int, Int, Int, Int, Int), Array[Int]] = Map([])
  for c in file.comments {
    guard !c.value.has_prefix("{-|") else { continue }
    // Descend to the innermost node that contains the comment start.
    let mut owner = root
    while true {
      let mut inner = None
      for ch in owner.children() {
        if !is_skipped(ch) && range_contains(ch.range(), c.range.start) {
          inner = Some(ch)
          break
        }
      }
      match inner {
        Some(n) => owner = n
        None => break
      }
    }
    let mut prev : @syntax.NodeRef? = None
    let mut next : @syntax.NodeRef? = None
    for ch in owner.children() {
      guard !is_skipped(ch) else { continue }
      if at_or_before(ch.range().end, c.range.start) {
        prev = Some(ch)
      } else if next is None && at_or_before(c.range.end, ch.range().start) {
        next = Some(ch)
      }
    }
    let (role, child) = match (prev, next) {
      (Some(p), _) if p.range().end.row == c.range.start.row =>
        (Trailing, Some(p.range()))
      (_, Some(n)) => (Leading, Some(n.range()))
      _ => (Inner, None)
    }
    let owner_range = owner.range()
    let key = index_key(role, child.unwrap_or(owner_range))
    match index.get(key) {
      Some(list) => list.push(placed.length())
      None => index[key] = [placed.length()]
    }
    placed.push({ comment: c, owner: owner_range, child, role, })
  }
  { placed, printed: Array::make(placed.length(), false), index, }
}

///|
/// The indices of the not yet printed comments with this role at this
/// range, in source order. For `Inner` the range is the owner's; otherwise
/// it is the child's.
// Task 6 is the first non-test user; it removes this suppression.
#warnings("-unused_value")
fn CommentTable::matching(
  self : CommentTable,
  role : Role,
  r : @ast.Range,
) -> Array[Int] {
  match self.index.get(index_key(role, r)) {
    Some(list) => list.filter(i => !self.printed[i])
    None => []
  }
}
