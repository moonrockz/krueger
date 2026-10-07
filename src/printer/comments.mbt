///|
priv enum Role {
  Leading
  Trailing
  Inner
}

///|
priv struct Placed {
  comment : @ast.Node[String]
  owner : @ast.Range
  child : @ast.Range?
  role : Role
}

///|
/// The placed comments and a lookup by role and range. `printed` marks the
/// comments that the printer has written.
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
/// The children of `node` that can own a comment, in source order, with
/// their ranges. `ordered` tells that each range starts at or before its
/// end and ends at or before the start of the next one. Then a binary
/// search finds the same child as a scan in source order.
priv struct Level {
  node : @syntax.NodeRef
  kids : Array[@syntax.NodeRef]
  ranges : Array[@ast.Range]
  ordered : Bool
}

///|
fn Level::new(node : @syntax.NodeRef) -> Level {
  let kids = node.children().filter(ch => !is_skipped(ch))
  let ranges = kids.map(ch => ch.range())
  let mut ordered = true
  for i, r in ranges {
    if !at_or_before(r.start, r.end) ||
      (i > 0 && !at_or_before(ranges[i - 1].end, r.start)) {
      ordered = false
      break
    }
  }
  { node, kids, ranges, ordered, }
}

///|
/// The number of leading ranges for which `before` holds. `before` must
/// hold for a prefix of the ranges only.
fn Level::count_while(self : Level, before : (@ast.Range) -> Bool) -> Int {
  let mut lo = 0
  let mut hi = self.ranges.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if before(self.ranges[mid]) {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}

///|
/// The index of the first child whose range contains `l`.
fn Level::containing(self : Level, l : @ast.Location) -> Int? {
  guard self.ordered else {
    for i, r in self.ranges {
      if range_contains(r, l) {
        return Some(i)
      }
    }
    return None
  }
  // At most one range contains `l`: the last one that starts at or before
  // it.
  let n = self.count_while(r => at_or_before(r.start, l))
  if n > 0 && range_contains(self.ranges[n - 1], l) {
    Some(n - 1)
  } else {
    None
  }
}

///|
/// The last child that ends at or before the start of `c`, and the first
/// other child that starts at or after the end of `c`.
fn Level::around(self : Level, c : @ast.Range) -> (Int?, Int?) {
  guard self.ordered && compare_location(c.start, c.end) < 0 else {
    let mut prev = None
    let mut next = None
    for i, r in self.ranges {
      if at_or_before(r.end, c.start) {
        prev = Some(i)
      } else if next is None && at_or_before(c.end, r.start) {
        next = Some(i)
      }
    }
    return (prev, next)
  }
  // The ends are in order too. A child that starts at or after the end of
  // `c` ends after its start, so it is not `prev`.
  let p = self.count_while(r => at_or_before(r.end, c.start))
  let n = self.count_while(r => compare_location(r.start, c.end) < 0)
  (
    if p > 0 {
      Some(p - 1)
    } else {
      None
    },
    if n < self.ranges.length() {
      Some(n)
    } else {
      None
    },
  )
}

///|
/// Decides for each regular comment which node owns it and in which role:
/// `Trailing` when a child ends on the comment's row before it, else
/// `Leading` of the next child, else `Inner` of the owner. Doc comments are
/// not placed.
///
/// The children of each node on the path to the last comment's owner are
/// kept (`levels`), and `chosen[d]` is the child of `levels[d]` that gave
/// `levels[d + 1]`. The comments are in source order, so the next comment
/// usually shares most of the path, and no node's children are built
/// again for it.
fn place_comments(file : @ast.File) -> CommentTable {
  let levels = [Level::new(File(file, [][:]))]
  let chosen : Array[Int] = []
  let placed = []
  let index : Map[(Int, Int, Int, Int, Int), Array[Int]] = Map([])
  for c in file.comments {
    guard !c.value.has_prefix("{-|") else { continue }
    // Descend to the innermost node that contains the comment start.
    let mut d = 0
    while levels[d].containing(c.range.start) is Some(i) {
      if !(d < chosen.length() && chosen[d] == i) {
        levels.truncate(d + 1)
        chosen.truncate(d)
        chosen.push(i)
        levels.push(Level::new(levels[d].kids[i]))
      }
      d += 1
    }
    let level = levels[d]
    let (prev, next) = level.around(c.range)
    let (role, child) = match (prev, next) {
      (Some(p), _) if level.ranges[p].end.row == c.range.start.row =>
        (Trailing, Some(level.ranges[p]))
      (_, Some(n)) => (Leading, Some(level.ranges[n]))
      _ => (Inner, None)
    }
    placed.push({ comment: c, owner: level.node.range(), child, role, })
  }
  for i, p in placed {
    let key = index_key(p.role, p.child.unwrap_or(p.owner))
    match index.get(key) {
      Some(list) => list.push(i)
      None => index[key] = [i]
    }
  }
  { placed, printed: Array::make(placed.length(), false), index, }
}

///|
/// The indices of the not yet printed comments with this role at this
/// range, in source order. For `Inner` the range is the owner's; otherwise
/// it is the child's.
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

///|
/// Whether a comment lies inside `start ..= end` (from the start of
/// `start` to the end of `end`). The comments are in source order.
fn CommentTable::has_between(
  self : CommentTable,
  start : @ast.Location,
  end : @ast.Location,
) -> Bool {
  let mut lo = 0
  let mut hi = self.placed.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if compare_location(self.placed[mid].comment.range.start, start) < 0 {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo < self.placed.length() &&
  at_or_before(self.placed[lo].comment.range.end, end)
}
