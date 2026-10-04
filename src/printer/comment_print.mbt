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
/// Whether comment `c` ends its line: it is a line comment, or the text
/// after it starts at `next` on a later row.
fn ends_line(c : @ast.Node[String], next : @ast.Location) -> Bool {
  is_line_comment(c) || next.row > c.range.end.row
}

///|
/// Whether comment `c`, after the node at `r`, needs a line before it or
/// after it: it is a line comment, or it starts on a later row than the
/// node ends.
fn off_line(c : @ast.Node[String], r : @ast.Range) -> Bool {
  is_line_comment(c) || c.range.start.row > r.end.row
}

///|
/// Comments each on its own line, joined by line breaks. With `before`, a
/// line break comes first; with `after`, one comes last. Nothing when there
/// are no comments.
fn comment_block(
  cs : Array[@ast.Node[String]],
  before? : Bool = false,
  after? : Bool = false,
) -> @pretty.Doc {
  guard !cs.is_empty() else { return @pretty.empty() }
  (if before { @pretty.hardline() } else { @pretty.empty() }) +
  @pretty.join(cs.map(comment_doc), @pretty.hardline()) +
  (if after { @pretty.hardline() } else { @pretty.empty() })
}

///|
/// Whether `comments_before(cs, next)` has a line break.
fn comments_break(cs : Array[@ast.Node[String]], next : @ast.Location) -> Bool {
  for i, c in cs {
    let after = if i + 1 < cs.length() { cs[i + 1].range.start } else { next }
    if ends_line(c, after) {
      return true
    }
  }
  false
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
    d = d +
      comment_doc(c) +
      (if ends_line(c, after) { @pretty.hardline() } else { @pretty.text(" ") })
  }
  d
}

///|
/// Comments before the text after them, joined as elm-format joins them
/// (`spaceSepOrStack`): a block comment is followed by `gap`, a line
/// comment by a line break. With `gap = line()` in a group that holds the
/// text, the block comments go on lines of their own when the text is
/// multi-line.
fn comments_joined(
  cs : Array[@ast.Node[String]],
  gap : @pretty.Doc,
) -> @pretty.Doc {
  let mut d = @pretty.empty()
  for c in cs {
    d = d +
      comment_doc(c) +
      (if is_line_comment(c) { @pretty.hardline() } else { gap })
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
  @pretty.hardline() + comment_block(cs, before=true)
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
    match cs.get(i + 1) {
      Some(next) =>
        d = d +
          (if ends_line(c, next.range.start) {
            @pretty.hardline()
          } else {
            @pretty.text(" ")
          })
      None => if is_line_comment(c) { d = d + @pretty.hardline() }
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
/// The start of the token `n` tokens before the token at `loc`, when there
/// is source.
fn Ctx::token_back(self : Ctx, loc : @ast.Location, n : Int) -> @ast.Location? {
  guard self.source is Some(facts) else { return None }
  let i = facts.first_at_or_after(loc)
  if i >= n {
    Some(facts.starts[i - n])
  } else {
    None
  }
}

///|
/// The start of the token before the token at `loc`, when there is source.
fn Ctx::token_before(self : Ctx, loc : @ast.Location) -> @ast.Location? {
  self.token_back(loc, 1)
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
  comment_block(cs, before=true, after=true)
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

///|
/// The comments before item `r` of a `let` or `case`: the trailing comments
/// of the item before it (at `previous`), which elm-format moves here, on
/// lines of their own, then the leading comments of `r`.
fn Ctx::moved_then_leading(
  self : Ctx,
  previous : @ast.Range?,
  r : @ast.Range,
) -> @pretty.Doc {
  let moved = match previous {
    Some(p) => self.take(Trailing, p)
    None => []
  }
  comment_block(moved, after=true) + self.leading(r)
}

///|
/// The start of the nearest token `lexeme` at most `n` tokens before the
/// token at `loc`, when there is source.
fn Ctx::token_back_to(
  self : Ctx,
  loc : @ast.Location,
  lexeme : String,
  n : Int,
) -> @ast.Location? {
  guard self.source is Some(facts) else { return None }
  let i = facts.first_at_or_after(loc)
  for k in 1..<=n {
    if i - k >= 0 && facts.lexeme_at(facts.starts[i - k]) == Some(lexeme) {
      return Some(facts.starts[i - k])
    }
  }
  None
}

///|
/// The start of the first token at or after `loc`, when there is source.
fn Ctx::token_after(self : Ctx, loc : @ast.Location) -> @ast.Location? {
  guard self.source is Some(facts) else { return None }
  facts.starts.get(facts.first_at_or_after(loc))
}

///|
/// The trailing comments of the node at `r` that come before the next
/// token, then those after it (marks both printed).
fn Ctx::trailing_split(
  self : Ctx,
  r : @ast.Range,
) -> (Array[@ast.Node[String]], Array[@ast.Node[String]]) {
  let next = self.token_after(r.end)
  let before = self.take_if(Trailing, r, c => {
    next is None || ends_before(c, next)
  })
  (before, self.take(Trailing, r))
}

///|
/// The block comments that trail the node at `r` but come after the next
/// token, a separator such as `:`, `=`, `->` or `as` (elm-format keeps
/// them after it: `x {- a -} : {- b -} Int`). Take them before the node's
/// own trailing comments, and print them after the separator with
/// `Ctx::separator`. Line comments stay before the separator (see
/// `Ctx::after`).
fn Ctx::after_token(self : Ctx, r : @ast.Range) -> Array[@ast.Node[String]] {
  guard self.token_after(r.end) is Some(next) else { return [] }
  self.take_if(Trailing, r, c => {
    !is_line_comment(c) && !ends_before(c, Some(next))
  })
}

///|
/// The separator `s` (such as ` :`) after the node at `r` (see
/// `Ctx::after`), then the comments `moved` after it (see
/// `Ctx::after_token`).
fn Ctx::separator(
  self : Ctx,
  r : @ast.Range,
  s : String,
  moved : Array[@ast.Node[String]],
) -> @pretty.Doc {
  self.after(r, s) + comments_after(moved)
}

///|
/// The not yet printed comments inside `r`, in source order; marks them
/// printed. For the comments of nodes that `normalize_file` removes (a
/// duplicate exposed item, the alias of a merged import).
fn Ctx::take_within(self : Ctx, r : @ast.Range) -> Array[@ast.Node[String]] {
  guard self.comments is Some(t) else { return [] }
  let out = []
  for i, p in t.placed {
    let c = p.comment
    if !t.printed[i] &&
      at_or_before(r.start, c.range.start) &&
      at_or_before(c.range.end, r.end) {
      t.printed[i] = true
      out.push(c)
    }
  }
  out
}

///|
/// Whether comment `c` prints on one line (a block comment with no line
/// break).
fn one_line(c : @ast.Node[String]) -> Bool {
  !is_line_comment(c) && !comment_text(c.value).contains("\n")
}

///|
/// Comments as elm-format joins them (`formatComments`): on one line when
/// each of them is one line, else each on its own line.
fn comment_box(cs : Array[@ast.Node[String]]) -> @pretty.Doc {
  let gap = if cs.iter().all(one_line) {
    @pretty.text(" ")
  } else {
    @pretty.hardline()
  }
  @pretty.join(cs.map(comment_doc), gap)
}

///|
/// `d` with the comments `pre` before it and `post` after it (elm-format
/// `formatCommented`): on one line when each comment is one line, else the
/// comments before, `d` and the comments after on lines of their own. Also
/// gives whether it is one line.
fn commented(
  pre : Array[@ast.Node[String]],
  d : @pretty.Doc,
  post : Array[@ast.Node[String]],
) -> (@pretty.Doc, Bool) {
  let flat = pre.iter().all(one_line) && post.iter().all(one_line)
  let parts = []
  if !pre.is_empty() {
    parts.push(comment_box(pre))
  }
  parts.push(d)
  if !post.is_empty() {
    parts.push(comment_box(post))
  }
  let gap = if flat { @pretty.text(" ") } else { @pretty.hardline() }
  (@pretty.join(parts, gap), flat)
}

///|
/// Whether a comment is inside the parentheses at `parens` but outside the
/// expression at `inner` in them. elm-format keeps such parentheses.
fn Ctx::comment_in_parens(
  self : Ctx,
  parens : @ast.Range,
  inner : @ast.Range,
) -> Bool {
  guard self.comments is Some(t) else { return false }
  t.has_between(parens.start, inner.start) ||
  t.has_between(inner.end, parens.end)
}
