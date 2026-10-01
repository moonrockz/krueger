///|
/// A generated module's tree, text, parse result and every node (pre-order).
/// Fails the law on any parse diagnostic.
fn module_tree(
  m : ElmModule,
) -> (@syntax.Tree, String, @parser.ParseResult, Array[@syntax.NodeRef]) raise {
  ignore(elm_root(m))
  let text = m.text()
  let result = parse_result(text)
  guard @syntax.Tree::new(result) is Some(tree) else { fail("no tree") }
  let nodes = []
  @syntax.walk(tree.root(), n => {
    nodes.push(n)
    Continue
  })
  (tree, text, result, nodes)
}

///|
test "law: node_at is a smallest node that contains the position: deepest among equals, first among partial overlaps" {
  // Edges: every node's start and end and one column before each; every
  // line's start, end and one past its end; the end of the file; the row
  // after the last; (1,1). Overlapping siblings: comments inside expressions
  // and declarations, a port's doc comment and its attributes.
  @quickcheck.check(
    (m : ElmModule) => {
      let (tree, text, _, nodes) = module_tree(m)
      let depth = nodes.map(n => tree.ancestors(n).length())
      @lawkit.edge_positions(text, nodes.map(n => n.range()))
      .iter()
      .all(p => {
        let holders = []
        for i, n in nodes {
          if range_contains(n.range(), p) {
            holders.push(i)
          }
        }
        match tree.node_at(p) {
          None => holders.is_empty()
          Some(found) => {
            guard nodes.search_by(n => n == found) is Some(fi) else {
              return false
            }
            let f = found.range()
            // No containing node lies strictly inside the result; among equal
            // ranges the result is the deepest; a containing node that only
            // partly overlaps it (a port's doc comment and the port) comes
            // later in pre-order.
            holders.contains(fi) &&
            holders
            .iter()
            .all(i => {
              let r = nodes[i].range()
              !(range_within(r, f) && r != f) &&
              (r != f || depth[i] <= depth[fi]) &&
              (range_within(f, r) || range_within(r, f) || fi < i)
            })
          }
        }
      })
    },
    count=100,
    max_size=24,
    seed=227,
  )
}

///|
/// A token's span as a range of rows and columns.
fn token_range(t : @scanner.Token) -> @ast.Range {
  {
    start: { row: t.span.start.line, column: t.span.start.column, },
    end: { row: t.span.end.line, column: t.span.end.column, },
  }
}

///|
fn shift(p : @ast.Location, d : Int) -> @ast.Location {
  { row: p.row, column: p.column + d, }
}

///|
test "law: tokens_in keeps exactly the whole tokens inside the range" {
  // Edges: every node's range; each token's span; an empty range at a token's
  // start; ranges that cut a token at its start or its end; a token start to
  // the next token's start or end; from one column before a token's end to
  // one column after the next token's start (cuts both).
  @quickcheck.check(
    (m : ElmModule) => {
      let (tree, _, result, nodes) = module_tree(m)
      guard result.cst is Some(cst) else { return false }
      let all = cst.tokens.map(token_range)
      let candidates : Array[@ast.Range] = nodes.map(n => n.range())
      for i, r in all {
        candidates.push(r)
        candidates.push({ start: r.start, end: r.start, })
        if r.end.row == r.start.row && r.end.column - r.start.column >= 2 {
          candidates.push({ start: shift(r.start, 1), end: r.end, })
          candidates.push({ start: r.start, end: shift(r.end, -1), })
        }
        if all.get(i + 1) is Some(next) {
          candidates.push({ start: r.start, end: next.end, })
          candidates.push({ start: r.start, end: next.start, })
          candidates.push({
            start: shift(r.end, -1),
            end: shift(next.start, 1),
          })
        }
      }
      candidates
      .iter()
      .all(r => {
        tree.tokens_in(r) ==
        cst.tokens.filter(t => range_within(token_range(t), r))
      })
    },
    count=50,
    max_size=24,
    seed=233,
  )
}

///|
test "law: the text at a node's range starts with its first token and ends with its last" {
  // Edges: non-ASCII text and surrogate pairs before tokens on the same line,
  // multi-line strings and comments, CRLF, no final newline. Excluded: the
  // file, comments, documentation and attributes (their text is not made of
  // tokens), nodes with no tokens, a declaration's leading `{-|`, and the end
  // of record setters and fields (elm-syntax ends them after trailing layout).
  @quickcheck.check(
    (m : ElmModule) => {
      let (tree, text, _, nodes) = module_tree(m)
      nodes
      .iter()
      .all(n => {
        let r = n.range()
        let cat = n.category()
        if cat == "comment" ||
          cat == "attribute" ||
          cat == "documentation" ||
          cat == "file" {
          return true
        }
        guard @lawkit.offset_of(text, r.start) is Some(a) &&
          @lawkit.offset_of(text, r.end) is Some(b) else {
          return false
        }
        let tokens = tree.tokens_in(r)
        if tokens.is_empty() {
          return true
        }
        let s = text.view(start_offset=a, end_offset=b)
        // A declaration with doc attributes starts at its first attribute
        // (a port's doc comment is not part of its elm-syntax range).
        let starts_at_attribute = cat == "declaration" &&
          !n.field("attributes").is_empty() &&
          s.has_prefix("@")
        (
          s.has_prefix("{-|") ||
          starts_at_attribute ||
          s.has_prefix(tokens[0].lexeme)
        ) &&
        (
          cat == "record_setter" ||
          cat == "record_field" ||
          s.has_suffix(tokens[tokens.length() - 1].lexeme)
        )
      })
    },
    count=100,
    max_size=24,
    seed=241,
  )
}

///|
/// Every node's tag (category, kind, range), in pre-order.
fn shape(text : String) -> Array[String] raise {
  guard @syntax.Tree::new(parse_result(text)) is Some(tree) else {
    fail("no tree")
  }
  let out = []
  @syntax.walk(tree.root(), n => {
    out.push(tag(n))
    Continue
  })
  out
}

///|
test "law: LF, CRLF and a missing final newline give the same node ranges" {
  // Edges: all four combinations of CRLF and no final newline.
  @quickcheck.check(
    (m : ElmModule) => {
      ignore(elm_root(m))
      let lf = m.text().replace_all(old="\r\n", new="\n")
      let base = if lf.has_suffix("\n") { lf } else { lf + "\n" }
      let bare = base.trim_end(chars="\n").to_owned()
      let expected = shape(base)
      let mut same = true
      for
        text in [
          base.replace_all(old="\n", new="\r\n"),
          bare,
          bare.replace_all(old="\n", new="\r\n"),
        ] {
        same = same &&
          parse_result(text).diagnostics.is_empty() &&
          shape(text) == expected
      }
      same
    },
    count=100,
    max_size=24,
    seed=257,
  )
}

///|
test "law: among children with equal ranges goto_first_child_for picks the first" {
  // Edges: equal, nested, adjacent and empty ranges on a small grid.
  @quickcheck.check(
    (input : @lawkit.Ranges) => {
      let ranges = input.ranges()
      let elements : Array[@ast.Node[@ast.Expression]] = ranges.mapi((i, r) => {
        range: r,
        value: Integer(i.to_int64()),
      })
      let list = e(ListExpr(elements))
      let kids = list.children()
      let c = @syntax.TreeCursor::new(list)
      @lawkit.edge_positions("      \n      \n", ranges)
      .iter()
      .all(p => {
        c.reset(list)
        let moved = c.goto_first_child_for(p)
        match child_for(kids, p) {
          None => !moved
          Some(i) => moved && c.node() == kids[i]
        }
      })
    },
    count=200,
    max_size=12,
    seed=239,
  )
}

///|
test "among children with equal ranges goto_first_child_for picks the first" {
  let r : @ast.Range = {
    start: { row: 1, column: 2, },
    end: { row: 2, column: 1, },
  }
  let first : @ast.Node[@ast.Expression] = { range: r, value: Integer(0L), }
  let second : @ast.Node[@ast.Expression] = { range: r, value: Integer(1L), }
  let c = @syntax.TreeCursor::new(e(ListExpr([first, second])))
  @expect.expect_all(s => {
    s.expect(c.goto_first_child_for(r.start)).to_be_true()
    s.expect(c.node()).to_equal(Expression(first))
  })
}

///|
test "a descent stops at a port's doc comment, which holds the attribute node_at finds" {
  // The port's doc comment (10:1-13:3) is a file comment; its attribute
  // (12:1) belongs to the port, whose range starts there.
  let tree = tree_of(port_with_attributes)
  let p : @ast.Location = { row: 12, column: 1, }
  let c = @syntax.TreeCursor::new(tree.root())
  while c.goto_first_child_for(p) {
    if !range_contains(c.node().range(), p) {
      ignore(c.goto_parent())
      break
    }
  }
  @expect.expect_all(s => {
    s.expect(c.node().category()).to_equal("comment")
    s.expect(tree.node_at(p).map(n => n.category())).to_equal(Some("attribute"))
  })
}

///|
test "an empty source has no tree" {
  @expect.expect(@syntax.Tree::new(parse_result("")) is None).to_be_true()
}

///|
test "law: for any text with an AST, every node lies inside the source and inside its parent" {
  // Edges: any ElmText (fragments, cut or changed modules, edge characters);
  // parses with errors included when they still give an AST.
  @quickcheck.check(
    (t : @lawkit.ElmText) => {
      let text = t.text()
      let result = @parser.parse_module(
        @scanner.SourceText::{ module_name: None, text, },
        @scanner.DefaultScanner::new(),
      )
      match @syntax.NodeRef::of_result(result) {
        None => true
        Some(root) => {
          let mut ok = true
          let open : Array[@syntax.NodeRef] = []
          @syntax.walk(
            root,
            n => {
              let r = n.range()
              ok = ok &&
                @lawkit.offset_of(text, r.start) is Some(_) &&
                @lawkit.offset_of(text, r.end) is Some(_) &&
                @lawkit.at_or_before(r.start, r.end) &&
                (match open.last() {
                  Some(parent) => @lawkit.within(r, parent.range())
                  None => true
                })
              open.push(n)
              Continue
            },
            leave=_ => ignore(open.pop()),
          )
          ok
        }
      }
    },
    count=200,
    max_size=24,
    seed=283,
  )
}
