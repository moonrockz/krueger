///|
/// A step of an operator chain, in source order.
priv enum ChainStep {
  Expand(@syntax.NodePath, @ast.Node[@ast.Expression]) // flatten this operator application
  Operand(@syntax.NodePath, @ast.Node[@ast.Expression], Bool) // true: an operator application in parentheses
  Symbol(String)
  Open(@ast.Range) // a flattened operator application inside the chain starts
  Close(@ast.Range) // and ends: its comments go around its operands
}

///|
/// Whether a child operator application can stay in its parent's chain
/// without parentheses and parse back to the same tree.
fn joins(
  parent : @dialect.OperatorDef,
  child : @dialect.OperatorDef,
  on_left : Bool,
) -> Bool {
  if child.precedence != parent.precedence {
    child.precedence > parent.precedence
  } else if on_left {
    parent.direction is Left && child.direction is Left
  } else {
    parent.direction is Right && child.direction is Right
  }
}

///|
fn Ctx::chain_step(
  self : Ctx,
  parent : @dialect.OperatorDef,
  path : @syntax.NodePath,
  child : @ast.Node[@ast.Expression],
  on_left : Bool,
) -> ChainStep raise PrintError {
  match child.value {
    OperatorApplication(symbol, _, _, _) =>
      if joins(parent, self.operator_def(path, symbol), on_left) {
        Expand(path, child)
      } else {
        Operand(path, child, true)
      }
    _ => Operand(path, child, false)
  }
}

///|
/// `a + b * c`: the first operand, then each operator and its operand on a
/// new line indented by 4 when the chain breaks. elm-format treats the
/// whole binary-operator expression as one chain. Flattened with an
/// explicit stack; every operator is checked before any operand.
///
/// Four docs per operand: the comments before its operator, the comments
/// after its operator, the operand, the comments after it. elm-format puts
/// a comment before an operator on its own line (`a\n    -- c\n    + b`),
/// and aligns the operand after the operator when a comment follows the
/// operator.
fn Ctx::chain_plan(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  e : @ast.Node[@ast.Expression],
) -> (Array[Work], (Array[@pretty.Doc]) -> @pretty.Doc) raise PrintError {
  let steps : Array[ChainStep] = []
  let stack : Array[ChainStep] = [Expand(path, e)]
  while stack.pop() is Some(step) {
    match step {
      Expand(p, node) =>
        if node.value is OperatorApplication(symbol, _, left, right) {
          let def = self.operator_def(p, symbol)
          // The chain's own comments are the expression's (`Ctx::run`).
          let inside = node.range != e.range
          if inside {
            stack.push(Close(node.range))
          }
          stack.push(self.chain_step(def, p.child("right", 0), right, false))
          stack.push(Symbol(symbol))
          stack.push(self.chain_step(def, p.child("left", 0), left, true))
          if inside {
            stack.push(Open(node.range))
          }
        }
      _ => steps.push(step)
    }
  }
  let operands : Array[(@syntax.NodePath, @ast.Node[@ast.Expression], Bool)] = []
  let opens : Array[Array[@ast.Range]] = []
  let closes : Array[Array[@ast.Range]] = []
  let symbols = []
  let mut pending = []
  for step in steps {
    match step {
      Symbol(s) => symbols.push(s)
      Open(r) => pending.push(r)
      Close(r) => closes[closes.length() - 1].push(r)
      Operand(p, node, wrapped) => {
        operands.push((p, node, wrapped))
        opens.push(pending)
        pending = []
        closes.push([])
      }
      Expand(_, _) => ()
    }
  }
  let last = operands.length() - 1
  // elm-format Parse/Binop.hs binops (`trackNewline`): a line break
  // anywhere in the chain puts every operator on its own line.
  let split = self.split_within(e.range)
  // `format_binary` groups the comments around an operator with it.
  let gap = if split is Fit { @pretty.text(" ") } else { @pretty.line() }
  let parts = []
  let line_after = []
  // An operand with comments after its operator: elm-format aligns it
  // after the operator (`|| -- a\n   b`).
  let aligned = Array::make(operands.length(), false)
  // The comments that trail an operand on its row go with the next
  // operator: before it or after it, as elm-format parses them
  // (`BinopsClause`). Taken before the operand prints its own.
  let moved_before : Array[Array[@ast.Node[String]]] = Array::makei(
    operands.length(),
    _ => [],
  )
  let moved_after : Array[Array[@ast.Node[String]]] = Array::makei(
    operands.length(),
    _ => [],
  )
  for k, operand in operands {
    let (p, node, wrapped) = operand
    let before = opens[k]
    let after = closes[k]
    // The comments of the operand and of the flattened applications that
    // start with it: before its operator, or after it.
    let ranges = [..before, node.range]
    let operator = if k > 0 {
      self.token_before(node.range.start)
    } else {
      None
    }
    let before_operator = (c : @ast.Node[String]) => {
      k == 0 || ends_before(c, operator)
    }
    let trails = [node.range, ..after]
    let next_operator = match operands.get(k + 1) {
      Some((_, n, _)) => self.token_before(n.range.start)
      None => None
    }
    if ranges
      .iter()
      .any(r => self.has_comment(Leading, r, c => !before_operator(c))) {
      aligned[k] = true
    }
    if k < last &&
      trails
      .iter()
      .any(r => {
        self.has_comment(Trailing, r, c => !ends_before(c, next_operator))
      }) {
      aligned[k + 1] = true
    }
    parts.push(
      Leaf(() => {
        if k < last {
          for r in trails {
            for c in self.take(Trailing, r) {
              if ends_before(c, next_operator) {
                moved_before[k + 1].push(c)
              } else {
                moved_after[k + 1].push(c)
              }
            }
          }
        }
        let cs = [..moved_before[k]]
        for r in ranges {
          cs.append(self.take_if(Leading, r, before_operator))
        }
        if k == 0 {
          comments_before(cs, node.range.start)
        } else {
          comments_joined(cs, gap)
        }
      }),
    )
    parts.push(
      Leaf(() => {
        let cs = [..moved_after[k]]
        for r in ranges {
          cs.append(self.take(Leading, r))
        }
        comments_joined(cs, gap)
      }),
    )
    parts.push(
      if wrapped {
        Plan([Expr(p, level + 1, node, AnyExpr)], docs => parens(Fit, docs[0]))
      } else {
        Expr(p, level + 1, node, if k == last { AnyExpr } else { Operand })
      },
    )
    parts.push(
      Leaf(() => {
        let mut d = @pretty.empty()
        for r in after {
          d = d + self.trailing(r)
        }
        d
      }),
    )
    line_after.push(
      self.line_comment_after(node.range) ||
      after.iter().any(r => self.line_comment_after(r)),
    )
  }
  (
    parts,
    docs => {
      let leads = []
      let operand_docs = []
      for i = 0; i + 3 < docs.length(); i = i + 4 {
        leads.push(docs[i])
        let d = docs[i + 1] + docs[i + 2]
        let d = match (aligned[i / 4], split) {
          (false, _) => d
          (true, Fit) => @pretty.align(d)
          (true, _) => @pretty.align(@pretty.group(d))
        }
        operand_docs.push(d + docs[i + 3])
      }
      match split {
        Fit =>
          @pretty.group(binary_doc(operand_docs, leads, symbols, line_after))
        Join | Split => format_binary(split, operand_docs, leads, symbols)
      }
    },
  )
}

///|
/// The operands and operators of a chain in the elm-format 0.8.7 layout
/// (its `formatBinary`), without the group. Each operator other than `<|`
/// starts a line at the next tab stop. A `<|` ends its line (`f x <|`), or
/// goes on its own line when operators come before it in its segment; the
/// rest of the chain is a new chain at the next tab stop:
/// `f x <|\n    g y <|\n        h z`. Built from the last segment back,
/// without recursion. `leads[i]` (comments) goes before the operator of
/// operand `i`, or before the operand at the start of a segment;
/// `line_after[i]` is true when a line comment ends operand `i`.
fn binary_doc(
  docs : Array[@pretty.Doc],
  leads : Array[@pretty.Doc],
  symbols : Array[String],
  line_after : Array[Bool],
) -> @pretty.Doc {
  // A segment starts at the first operand and after each `<|`.
  let starts = [0]
  for i, s in symbols {
    if s == "<|" {
      starts.push(i + 1)
    }
  }
  let mut result = @pretty.empty()
  for k = starts.length() - 1; k >= 0; k = k - 1 {
    let start = starts[k]
    let end = if k + 1 < starts.length() {
      starts[k + 1] - 1
    } else {
      symbols.length()
    }
    let mut rest = @pretty.empty()
    for i in start..<end {
      rest = rest +
        @pretty.line() +
        leads[i + 1] +
        @pretty.text(symbols[i] + " ") +
        docs[i + 1]
    }
    let segment = leads[start] + docs[start] + @pretty.tab(4, rest)
    result = if k + 1 == starts.length() {
      segment
    } else {
      let pipe = if end > start || line_after[end] {
        @pretty.line() + @pretty.text("<|")
      } else {
        @pretty.text(" <|")
      }
      segment + pipe + @pretty.tab(4, @pretty.line() + result)
    }
  }
  result
}

///|
/// A chain in the elm-format 0.8.7 layout of its `formatBinary` for the
/// `ElmFormat` layout. elm-format folds the chain from the left: with
/// `Join`, an operator goes on a new line (at the next tab stop) when its
/// operand or an operand before it in its segment is multi-line; with
/// `Split`, every operator does. An operand that follows its operator on
/// the line keeps its later lines right of the operator (elm-format
/// `spaceSepOrPrefix`). A `<|` ends its segment: it goes on the line of the
/// segment, or on its own line when the segment is multi-line
/// (`spaceSepOrStack`); the rest of the chain is a new chain, on the line
/// or at the next tab stop (`forceableSpaceSepOrIndented`). `leads` are as
/// for `binary_doc`.
fn format_binary(
  split : Split,
  docs : Array[@pretty.Doc],
  leads : Array[@pretty.Doc],
  symbols : Array[String],
) -> @pretty.Doc {
  // The segments ended by `<|`, each with its `<|`.
  let piped = []
  let mut acc = leads[0] + docs[0]
  for i, s in symbols {
    if s == "<|" {
      piped.push(@pretty.group(acc + @pretty.line() + @pretty.text("<|")))
      acc = @pretty.group(leads[i + 1] + docs[i + 1])
    } else {
      acc = @pretty.group(
        acc +
        @pretty.tab(
          4,
          split_line(split) +
          @pretty.group(
            leads[i + 1] + @pretty.text(s + " ") + @pretty.align(docs[i + 1]),
          ),
        ),
      )
    }
  }
  for k = piped.length() - 1; k >= 0; k = k - 1 {
    acc = @pretty.group(piped[k] + @pretty.tab(4, split_line(split) + acc))
  }
  acc
}
