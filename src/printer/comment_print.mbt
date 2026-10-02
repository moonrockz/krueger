///|
/// The text of a comment as elm-format writes it: line ends as `\n`, no
/// trailing spaces.
fn comment_text(c : String) -> String {
  c.replace_all(old="\r\n", new="\n").trim_end().to_owned()
}

///|
fn comment_doc(c : @ast.Node[String]) -> @pretty.Doc {
  @pretty.verbatim(comment_text(c.value))
}

///|
fn is_line_comment(c : @ast.Node[String]) -> Bool {
  c.value.has_prefix("--")
}

///|
/// The not yet printed comments with this role at this range for which
/// `keep` is true, in source order. They are marked printed.
fn Ctx::take_if(
  self : Ctx,
  role : Role,
  r : @ast.Range,
  keep : (@ast.Node[String]) -> Bool,
) -> Array[@ast.Node[String]] {
  guard self.comments is Some(t) else { return [] }
  let out = []
  for i in t.matching(role, r) {
    let c = t.placed[i].comment
    if keep(c) {
      t.printed[i] = true
      out.push(c)
    }
  }
  out
}

///|
fn Ctx::take(
  self : Ctx,
  role : Role,
  r : @ast.Range,
) -> Array[@ast.Node[String]] {
  self.take_if(role, r, _ => true)
}

///|
/// Comments before the text that starts at `next`. A line comment ends its
/// line. A block comment ends its line when the source has a line break
/// after it; else one space follows it.
fn comments_before(
  cs : Array[@ast.Node[String]],
  next : @ast.Location,
) -> @pretty.Doc {
  let mut d = @pretty.empty()
  for i, c in cs {
    let after = if i + 1 < cs.length() { cs[i + 1].range.start } else { next }
    let own_line = is_line_comment(c) || after.row > c.range.end.row
    d = d +
      comment_doc(c) +
      (if own_line { @pretty.hardline() } else { @pretty.text(" ") })
  }
  d
}

///|
/// Comments each on its own line, each followed by a line break.
fn comment_lines(cs : Array[@ast.Node[String]]) -> @pretty.Doc {
  let mut d = @pretty.empty()
  for c in cs {
    d = d + comment_doc(c) + @pretty.hardline()
  }
  d
}

///|
/// Comments after a node on its last line: ` {- a -} -- b`.
fn comments_after(cs : Array[@ast.Node[String]]) -> @pretty.Doc {
  let mut d = @pretty.empty()
  for c in cs {
    d = d + @pretty.text(" ") + comment_doc(c)
    if is_line_comment(c) {
      // Nothing may follow a line comment on its line. `if_break(b, f)`
      // has a hard line when `f` has one, so this forces the enclosing
      // group to break and prints nothing in the broken form.
      d = d + @pretty.if_break(@pretty.empty(), @pretty.hardline())
    }
  }
  d
}

///|
/// The leading comments of the node with range `r`; marks them printed.
fn Ctx::leading(self : Ctx, r : @ast.Range) -> @pretty.Doc {
  comments_before(self.take(Leading, r), r.start)
}

///|
/// The trailing comments of the node with range `r`; marks them printed.
fn Ctx::trailing(self : Ctx, r : @ast.Range) -> @pretty.Doc {
  comments_after(self.take(Trailing, r))
}

///|
/// The inner comments of the node with range `owner`, for the place after
/// its last child and before its closing token: a blank line, then each
/// comment on its own line (elm-format, for a list). The container breaks
/// the line before its closing token. Empty when there are none.
///
/// `last` is the range of the last child when elm-syntax's range of that
/// child runs to the closing token (a record field or setter): its inner
/// comments come first.
fn Ctx::inner(
  self : Ctx,
  owner : @ast.Range,
  last? : @ast.Range? = None,
) -> @pretty.Doc {
  let cs = match last {
    Some(r) => self.take(Inner, r)
    None => []
  }
  cs.append(self.take(Inner, owner))
  guard !cs.is_empty() else { return @pretty.empty() }
  @pretty.hardline() +
  @pretty.hardline() +
  @pretty.join(cs.map(comment_doc), @pretty.hardline())
}

///|
/// The inner comments of the node with range `owner` when it has no
/// children, between its opening and closing tokens: `[{- a -}]`,
/// `[-- a\n]`. After a `{` (`brace = true`), a line comment gets a space
/// first: `{--` would start a block comment.
fn Ctx::inner_alone(
  self : Ctx,
  owner : @ast.Range,
  brace? : Bool = false,
) -> @pretty.Doc {
  let cs = self.take(Inner, owner)
  let mut d = match cs.get(0) {
    Some(c) if brace && is_line_comment(c) => @pretty.text(" ")
    _ => @pretty.empty()
  }
  for i, c in cs {
    d = d + comment_doc(c)
    let last = i + 1 == cs.length()
    if is_line_comment(c) ||
      (!last && cs[i + 1].range.start.row > c.range.end.row) {
      d = d + @pretty.hardline()
    } else if !last {
      d = d + @pretty.text(" ")
    }
  }
  d
}

///|
/// `d` with the leading and trailing comments of its node.
fn Ctx::with_comments(
  self : Ctx,
  r : @ast.Range,
  d : @pretty.Doc,
) -> @pretty.Doc {
  self.leading(r) + d + self.trailing(r)
}

///|
/// The range of the first regular comment that is not printed.
fn CommentTable::unprinted(self : CommentTable) -> @ast.Range? {
  for i, p in self.placed {
    if !self.printed[i] {
      return Some(p.comment.range)
    }
  }
  None
}

///|
/// Whether a line comment trails the node at `r`, printed or not.
fn Ctx::line_comment_after(self : Ctx, r : @ast.Range) -> Bool {
  guard self.comments is Some(t) else { return false }
  match t.index.get(index_key(Trailing, r)) {
    Some(list) => list.iter().any(i => is_line_comment(t.placed[i].comment))
    None => false
  }
}

///|
/// `text(s)` after the node at `r`. When a line comment trails that node,
/// nothing may follow on its line, so the leading spaces of `s` become a
/// line break, indented by 4 (a continuation line).
fn Ctx::after(self : Ctx, r : @ast.Range, s : String) -> @pretty.Doc {
  if self.line_comment_after(r) {
    @pretty.nest(4, @pretty.hardline()) +
    @pretty.text(s.trim_start().to_owned())
  } else {
    @pretty.text(s)
  }
}

///|
/// `Ctx::inner` for a container with `count` children, `Ctx::inner_alone`
/// for one with none.
fn Ctx::inner_for(self : Ctx, owner : @ast.Range, count : Int) -> @pretty.Doc {
  if count == 0 {
    self.inner_alone(owner)
  } else {
    self.inner(owner)
  }
}

///|
/// The start of the token before the token at `loc`, when there is source.
fn Ctx::token_before(self : Ctx, loc : @ast.Location) -> @ast.Location? {
  guard self.source is Some(facts) else { return None }
  let i = facts.first_at_or_after(loc)
  if i > 0 {
    Some(facts.starts[i - 1])
  } else {
    None
  }
}

///|
/// Whether comment `c` ends before the token at `loc` (none when there is
/// no source).
fn ends_before(c : @ast.Node[String], loc : @ast.Location?) -> Bool {
  match loc {
    Some(l) => at_or_before(c.range.end, l)
    None => false
  }
}

///|
/// The comments before item `r` of a sequence that has items before it, for
/// the place before its `,`: a blank line, then each comment on its own
/// line (elm-format). Comments after the `,` stay with the item.
/// `previous` is the range of the item before it when elm-syntax's range of
/// that item runs to the `,` (a record field or setter): its inner comments
/// come first. Empty when there are none.
fn Ctx::before_item(
  self : Ctx,
  previous : @ast.Range?,
  r : @ast.Range,
) -> @pretty.Doc {
  let comma = self.token_before(r.start)
  let cs = match previous {
    Some(p) => self.take(Inner, p)
    None => []
  }
  cs.append(self.take_if(Leading, r, c => ends_before(c, comma)))
  guard !cs.is_empty() else { return @pretty.empty() }
  @pretty.hardline() + comment_lines(cs)
}

///|
/// The trailing comments of record field or setter `r` that come before the
/// `,` of the next item `next`. elm-syntax's range of a field can run to
/// that `,`; then the comments after the `,` trail the field, and
/// `Ctx::after_comma` takes them.
fn Ctx::trailing_before_comma(
  self : Ctx,
  r : @ast.Range,
  next : @ast.Range?,
) -> @pretty.Doc {
  match next {
    None => self.trailing(r)
    Some(n) => {
      let comma = self.token_before(n.start)
      comments_after(
        self.take_if(Trailing, r, c => {
          match comma {
            Some(l) => compare_location(c.range.start, l) < 0
            None => true
          }
        }),
      )
    }
  }
}

///|
/// The comments after the `,` before record field or setter `r`: the rest
/// of the trailing comments of the field before it (see
/// `Ctx::trailing_before_comma`), then the leading comments of `r`.
fn Ctx::after_comma(
  self : Ctx,
  previous : @ast.Range?,
  r : @ast.Range,
) -> @pretty.Doc {
  let cs = match previous {
    Some(p) => self.take(Trailing, p)
    None => []
  }
  cs.append(self.take(Leading, r))
  comments_before(cs, r.start)
}

///|
/// Whether a not yet printed comment with this role at this range makes
/// `keep` true.
fn Ctx::has_comment(
  self : Ctx,
  role : Role,
  r : @ast.Range,
  keep : (@ast.Node[String]) -> Bool,
) -> Bool {
  guard self.comments is Some(t) else { return false }
  t.matching(role, r).iter().any(i => keep(t.placed[i].comment))
}
