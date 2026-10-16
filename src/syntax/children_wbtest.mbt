///|
/// The stable order of `keys` by the model: an insertion sort of the
/// indices.
fn model_order(keys : Array[@ast.Location]) -> Array[Int32] {
  let order = Array::makei(keys.length(), i => i)
  for i in 1..<order.length() {
    let x = order[i]
    let mut j = i
    while j > 0 && compare_locations(keys[x], keys[order[j - 1]]) < 0 {
      order[j] = order[j - 1]
      j -= 1
    }
    order[j] = x
  }
  order
}

///|
test "stable_order sorts by location and keeps ties in place, for every short list" {
  // Every list of length 0 to 6 over three locations: none, one and many
  // runs, ties inside and across runs, sorted and reversed lists.
  let domain : Array[@ast.Location] = [
    { row: 1, column: 5, },
    { row: 2, column: 1, },
    { row: 2, column: 3, },
  ]
  let mut checked = 0
  for n in 0..<=6 {
    let mut count = 1
    for _ in 0..<n {
      count *= domain.length()
    }
    for code in 0..<count {
      let keys = []
      let mut c = code
      for _ in 0..<n {
        keys.push(domain[c % domain.length()])
        c /= domain.length()
      }
      let expected = model_order(keys)
      let got = match stable_order(keys) {
        Some(order) => order
        None => Array::makei(keys.length(), i => i)
      }
      if got != expected {
        fail(
          "stable_order(\{keys.map(show_location).join(",")}) = \{got.map(i => i.to_string()).join(",")}, expected \{expected.map(i => i.to_string()).join(",")}",
        )
      }
      // None exactly when the keys are in order already.
      let sorted = expected == Array::makei(keys.length(), i => i)
      if (stable_order(keys) is None) != sorted {
        fail(
          "stable_order(\{keys.map(show_location).join(",")}): None only for sorted keys",
        )
      }
      checked += 1
    }
  }
  inspect(checked, content="1093")
}

///|
fn show_location(l : @ast.Location) -> String {
  "\{l.row}:\{l.column}"
}

///|
/// Every list of length 0 to 3 over `domain`.
fn[T] short_lists(domain : Array[T]) -> Array[Array[T]] {
  let lists : Array[Array[T]] = [[]]
  let mut previous : Array[Array[T]] = [[]]
  for _ in 0..<3 {
    let next = []
    for l in previous {
      for x in domain {
        next.push([..l, x])
      }
    }
    lists.append(next)
    previous = next
  }
  lists
}

///|
test "attributes_of_declarations agrees with the map for declarations and groups in any order" {
  // Edges: no groups, no declarations; groups for ranges with no
  // declaration; two groups for one range (the first wins); two
  // declarations with one range; both lists in order, either out of order;
  // a module group among the declaration groups.
  let ranges : Array[@ast.Range] = [
    { start: { row: 1, column: 1, }, end: { row: 2, column: 1, }, },
    { start: { row: 1, column: 1, }, end: { row: 3, column: 1, }, },
    { start: { row: 4, column: 1, }, end: { row: 5, column: 1, }, },
  ]
  let declaration : @ast.Node[@ast.Declaration] = {
    range: ranges[0],
    value: Destructuring({ range: ranges[0], value: AllPattern, }, {
      range: ranges[0],
      value: UnitExpr,
    }),
  }
  let mut checked = 0
  for declaration_ranges in short_lists(ranges) {
    let declarations = declaration_ranges.map(r => { ..declaration, range: r, })
    for group_ranges in short_lists(ranges) {
      for module_first in [false, true] {
        // Group i's one attribute starts on row i, so the groups differ.
        let groups : Array[@parser.AttributeGroup] = group_ranges.mapi((i, r) => {
          target: Declaration(name="d", range=r),
          attributes: [
            Docs(names=[], range={ start: { row: i, column: 1, }, end: r.end, }),
          ],
        })
        if module_first {
          groups.insert(0, { target: Module, attributes: [], })
        }
        let by_range = declaration_attributes(groups)
        let expected = declarations.map(d => {
          by_range.get(range_key(d.range)).unwrap_or([]).to_owned()
        })
        let got = attributes_of_declarations(declarations, groups).map(a => {
          a.to_owned()
        })
        if got != expected {
          fail(
            "declarations \{declaration_ranges.length()}, groups \{group_ranges.length()}: differs from the map",
          )
        }
        checked += 1
      }
    }
  }
  inspect(checked, content="3200")
}
