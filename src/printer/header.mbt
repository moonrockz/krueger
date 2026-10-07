///|
fn Ctx::expose_doc(
  self : Ctx,
  path : @syntax.NodePath,
  x : @ast.Node[@ast.TopLevelExpose],
) -> @pretty.Doc raise PrintError {
  match x.value {
    InfixExpose(symbol) =>
      @pretty.text("(" + self.operator_symbol(path, symbol) + ")")
    FunctionExpose(name) => self.lower_name(path, name)
    TypeOrAliasExpose(name) => upper_name(path, name)
    TypeExpose(t) =>
      upper_name(path, t.name) +
      (if t.open is Some(_) {
        @pretty.text("(") + self.inner_alone(x.range) + @pretty.text("..)")
      } else {
        @pretty.empty()
      })
  }
}

///|
/// The comments of an explicit exposing list as elm-format keeps them:
/// before and after each item (`C2`), by the `expose_order` key of the
/// item. The comments of items with the same key (duplicates, or the same
/// item in two imports of one module) are joined.
priv struct ExposeComments {
  /// The comments between `exposing` and `(`.
  before_paren : Array[@ast.Node[String]]
  items : Map[
    (Int, String),
    (Array[@ast.Node[String]], Array[@ast.Node[String]]),
  ]
}

///|
fn ExposeComments::new() -> ExposeComments {
  { before_paren: [], items: Map([]), }
}

///|
/// Takes the comments of the items of exposing list `e` into `into`: for
/// each item, the comments after the `(` or `,` before it, and the
/// comments after it up to the next `,` or the `)`. Call it with the list
/// of the source, before normalization, so that a comment goes with the
/// item it is next to.
fn Ctx::take_expose_comments(
  self : Ctx,
  e : @ast.Node[@ast.Exposing],
  into : ExposeComments,
) -> Unit {
  guard e.value is Explicit(items) && items.length() > 0 else { return }
  let paren = self.token_before(items[0].range.start)
  into.before_paren.append(
    self.take_if(Leading, items[0].range, c => ends_before(c, paren)),
  )
  for i, x in items {
    // The comments after the `,` that trail the item before it.
    let pre = if i > 0 { self.take(Trailing, items[i - 1].range) } else { [] }
    pre.append(self.take(Leading, x.range))
    let post = match items.get(i + 1) {
      Some(next) => {
        let comma = self.token_before(next.range.start)
        let p = self.take_if(Trailing, x.range, c => ends_before(c, comma))
        p.append(self.take_if(Leading, next.range, c => ends_before(c, comma)))
        p
      }
      None => [..self.take(Trailing, x.range), ..self.take(Inner, e.range)]
    }
    let key = expose_order(x.value)
    match into.items.get(key) {
      Some((a, b)) => {
        a.append(pre)
        b.append(post)
      }
      None => into.items[key] = (pre, post)
    }
  }
}

///|
/// `Split` when the source list `e` has a line break inside its
/// parentheses (elm-format Parse/Module.hs `listing`, `trackNewline`).
fn Ctx::list_split(self : Ctx, e : @ast.Node[@ast.Exposing]) -> Split {
  match e.value {
    Explicit(items) =>
      match items.get(0).bind(x => self.token_before(x.range.start)) {
        Some(paren) => self.split_within({ start: paren, end: e.range.end, })
        None => self.join()
      }
    All(_) => self.join()
  }
}

///|
/// `( a\n, b\n)`: the parts each on its own line, then the comments
/// `footer` (elm-format `group'` with its `extraFooter`).
fn stacked_list(
  parts : Array[@pretty.Doc],
  footer : Array[@ast.Node[String]],
) -> @pretty.Doc {
  let mut d = @pretty.text("( ") + @pretty.nest(2, parts[0])
  for i in 1..<parts.length() {
    d = d + @pretty.hardline() + @pretty.text(", ") + @pretty.nest(2, parts[i])
  }
  if !footer.is_empty() {
    d = d + @pretty.hardline() + comment_box(footer)
  }
  d + @pretty.hardline() + @pretty.text(")")
}

///|
/// The list of an exposing list without a group: `(..)`, or the items in
/// `groups` with their `comments` (see `exposing_groups`). One group is
/// `(a, b)`, or each item on its own line when `split` is `Split` or an
/// item has a comment that needs its own line; several groups are always
/// one group per line (elm-format `formatModuleLine`, `formatListing`).
/// A group from a `@docs` line is one line in every layout. Also gives
/// the comments before the `(`, which go after `exposing` (see
/// `before_paren_doc`), and whether the list is one line that does not
/// break in the `Width` layout.
///
/// The comments of the items in `@docs` groups go after the last group, on
/// lines of their own (elm-format `commentsFromReorderedVars`).
fn Ctx::exposing_list(
  self : Ctx,
  path : @syntax.NodePath,
  e : @ast.Node[@ast.Exposing],
  groups : ExposingGroups,
  comments : ExposeComments,
  split : Split,
) -> (Array[@ast.Node[String]], @pretty.Doc, Bool) raise PrintError {
  match e.value {
    All(_) => {
      // `(..)` has no children: its comments before the `(` are inner too.
      let paren = self.token_back_to(e.range.end, "(", 3)
      let before_paren = self.take_if(Inner, e.range, c => ends_before(c, paren))
      (
        before_paren,
        @pretty.text("(") + self.inner_alone(e.range) + @pretty.text("..)"),
        false,
      )
    }
    Explicit(items) => {
      guard !items.is_empty() else {
        raise PrintError(path~, problem=EmptyExposing)
      }
      let position : Map[(Int, String), Int] = Map([])
      for i, x in items {
        position[expose_order(x.value)] = i
      }
      let item_doc = (x : @ast.Node[@ast.TopLevelExpose]) => {
        let key = expose_order(x.value)
        self.expose_doc(
          path.child("explicit", position.get(key).unwrap_or(0)),
          x,
        )
      }
      let none = ([], [])
      let documented : Map[(Int, String), Unit] = Map([])
      for k in 0..<groups.documented {
        for x in groups.groups[k] {
          documented[expose_order(x.value)] = ()
        }
      }
      let footer = []
      for x in items {
        let key = expose_order(x.value)
        if documented.contains(key) {
          let (pre, post) = comments.items.get(key).unwrap_or(none)
          footer.append(pre)
          footer.append(post)
        }
      }
      let parts = []
      let mut flat = true
      if groups.groups.length() == 1 {
        for x in groups.groups[0] {
          let key = expose_order(x.value)
          let (pre, post) = if documented.contains(key) {
            none
          } else {
            comments.items.get(key).unwrap_or(none)
          }
          let (d, one) = commented(pre, item_doc(x), post)
          parts.push(d)
          flat = flat && one
        }
      } else {
        flat = false
        for k, g in groups.groups {
          let pre = []
          let post = []
          let names = []
          for x in g {
            names.push(item_doc(x))
            if k >= groups.documented {
              let (a, b) = comments.items
                .get(expose_order(x.value))
                .unwrap_or(none)
              pre.append(a)
              post.append(b)
            }
          }
          parts.push(
            commented(pre, @pretty.join(names, @pretty.text(", ")), post).0,
          )
        }
      }
      // The comments of items that normalization removed.
      footer.append(self.take_within(e.range))
      let fixed = groups.documented > 0 && split is Fit
      let split = if fixed { Join } else { split }
      let list = match split {
        _ if !flat || !footer.is_empty() => stacked_list(parts, footer)
        // The enclosing group breaks the list.
        Fit => {
          let mut body = @pretty.nest(2, parts[0])
          for i in 1..<parts.length() {
            body = body +
              @pretty.softline() +
              @pretty.text(", ") +
              @pretty.nest(2, parts[i])
          }
          @pretty.text("(") +
          @pretty.if_break(@pretty.text(" "), @pretty.empty()) +
          body +
          @pretty.softline() +
          @pretty.text(")")
        }
        Join =>
          @pretty.text("(") +
          @pretty.join(parts, @pretty.text(", ")) +
          @pretty.text(")")
        Split => stacked_list(parts, footer)
      }
      (comments.before_paren, list, fixed && flat && footer.is_empty())
    }
  }
}

///|
/// The comments before the `(` of exposing list `e`, after `exposing` on
/// its line. After a line comment, the list of `(..)` goes on the next
/// line.
fn before_paren_doc(
  e : @ast.Node[@ast.Exposing],
  cs : Array[@ast.Node[String]],
) -> @pretty.Doc {
  let gap = if e.value is All(_) && cs.iter().any(is_line_comment) {
    @pretty.nest(4, @pretty.hardline())
  } else {
    @pretty.empty()
  }
  comments_after(cs) + gap
}

///|
/// ` exposing (a, b)`, or ` exposing\n    ( a\n    , b\n    )` after a
/// module header. After an import (`import_ = true`), the broken form puts
/// `exposing` on its own line, as elm-format 0.8.7 does:
/// `\n    exposing\n        ( a\n        , b\n        )`. `previous` is
/// the range of the name before it. `groups`, `comments` and `split` are
/// as for `Ctx::exposing_list`.
fn Ctx::exposing_doc(
  self : Ctx,
  path : @syntax.NodePath,
  e : @ast.Node[@ast.Exposing],
  previous : @ast.Range,
  groups : ExposingGroups,
  comments : ExposeComments,
  split : Split,
  import_? : Bool = false,
) -> @pretty.Doc raise PrintError {
  // The comments before `exposing` go on lines of their own.
  let cs = self.take(Leading, e.range)
  let lead = if cs.is_empty() {
    None
  } else {
    Some(@pretty.nest(4, comment_block(cs, before=true, after=true)))
  }
  let (paren_comments, items, list_one_line) = self.exposing_list(
    path, e, groups, comments, split,
  )
  // elm-format Box.hs formatModuleLine and formatImport: `exposing` with
  // the comments after it (`formatCommented`) is multi-line when a comment
  // is, and then the list goes on the next line (`spaceSepOrIndented`):
  // in the column of `exposing` after a module header, one tab stop right
  // of it after an import.
  if !paren_comments.iter().all(one_line) {
    let rest = @pretty.hardline() +
      comment_block(paren_comments) +
      @pretty.hardline() +
      items
    return lead.unwrap_or(@pretty.nest(4, @pretty.hardline())) +
      @pretty.nest(
        4,
        @pretty.text("exposing") +
        (if import_ { @pretty.nest(4, rest) } else { rest }),
      )
  }
  let before_paren = before_paren_doc(e, paren_comments)
  match e.value {
    All(_) =>
      lead.unwrap_or(self.after(previous, " ")) +
      @pretty.text("exposing") +
      before_paren +
      @pretty.text(" ") +
      items
    Explicit(_) => {
      // A list that is one line follows `exposing` on its line, unless a
      // line comment breaks the header.
      let gap = if list_one_line &&
        lead is None &&
        !self.line_comment_after(previous) &&
        !comments.before_paren.iter().any(is_line_comment) {
        @pretty.text(" ")
      } else {
        @pretty.line()
      }
      let list = @pretty.text("exposing") +
        before_paren +
        @pretty.nest(4, gap + items)
      match (lead, import_) {
        (Some(l), true) => l + @pretty.group(@pretty.nest(4, list))
        (Some(l), false) => l + @pretty.group(list)
        (None, true) =>
          if self.line_comment_after(previous) {
            // Nothing may follow the line comment on its line.
            @pretty.nest(4, @pretty.hardline()) +
            @pretty.group(@pretty.nest(4, list))
          } else {
            @pretty.group(@pretty.nest(4, @pretty.line() + list))
          }
        (None, false) => @pretty.group(self.after(previous, " ") + list)
      }
    }
  }
}

///|
/// `command = MyCmd` in the `where` record of an effect module, with the
/// comments `before` it (after its `{` or `,`) and `after` its name (before
/// the next `,` or `}`). A comment after the name that needs its own line
/// puts the name and its comments on lines of their own (elm-format). Also
/// gives whether a comment of the field ends its line. `label_at` is the
/// start of the label (`command`), the text after the comments before it.
fn effect_field(
  path : @syntax.NodePath,
  label : String,
  label_at : @ast.Location,
  name : @ast.Node[String],
  before : Array[@ast.Node[String]],
  after : Array[@ast.Node[String]],
) -> (@pretty.Doc, Bool) raise PrintError {
  guard is_upper(name.value) else {
    raise PrintError(path~, problem=InvalidName(Upper, name.value))
  }
  let own_lines = after.iter().any(c => off_line(c, name.range))
  let value = if own_lines {
    @pretty.tab(
      4,
      @pretty.hardline() +
      @pretty.text(name.value) +
      comment_block(after, before=true),
    )
  } else {
    @pretty.text(" " + name.value) + comments_after(after)
  }
  (
    comments_before(before, label_at) + @pretty.text(label + " =") + value,
    own_lines || comments_break(before, label_at),
  )
}

///|
/// The module header. `groups` and `comments` are the groups and the
/// comments of its exposing list (see `Ctx::exposing_list`).
fn Ctx::module_doc(
  self : Ctx,
  path : @syntax.NodePath,
  m : @ast.Node[@ast.Module],
  groups : ExposingGroups,
  comments : ExposeComments,
) -> @pretty.Doc raise PrintError {
  match m.value {
    NormalModule(d) | PortModule(d) => {
      let keyword = if m.value is PortModule(_) {
        "port module"
      } else {
        "module"
      }
      let name = d.module_name
      @pretty.text(keyword) +
      self.space_before(None, name.range, 4).0 +
      self.with_comments(
        name.range,
        @pretty.text(module_name(path.child("moduleName", 0), name.value)),
      ) +
      self.exposing_doc(
        path.child("exposingList", 0),
        d.exposing_list,
        name.range,
        groups,
        comments,
        self.join(),
      )
    }
    // `effect module A where { command = C } exposing (a)` on one line. A
    // comment that ends its line in the header puts `where`, the record and
    // `exposing` with its list each on lines of their own, indented by 4
    // (elm-format).
    EffectModule(d) => {
      let name = d.module_name
      let head = @pretty.text("effect module") +
        self.space_before(None, name.range, 4).0 +
        @pretty.text(module_name(path.child("moduleName", 0), name.value))
      let names = []
      if d.command is Some(c) {
        names.push(("command", c))
      }
      if d.subscription is Some(s) {
        names.push(("subscription", s))
      }
      guard names.get(0) is Some((_, first)) else {
        raise PrintError(path~, problem=NoFields)
      }
      // The comments after the name: before `where` they stay with the
      // name; between `where` and `{` they go before `where`; after `{`
      // they go before the first field.
      let where_at = self.token_after(name.range.end)
      let brace = self.token_back_to(first.range.start, "{", 3)
      let after_name = []
      let before_where = []
      let carried = []
      for c in self.take(Trailing, name.range) {
        if ends_before(c, where_at) {
          after_name.push(c)
        } else if ends_before(c, brace) {
          before_where.push(c)
        } else {
          carried.push(c)
        }
      }
      before_where.append(
        self.take_if(Leading, first.range, c => ends_before(c, brace)),
      )
      // Each field gets the comments after its `{` or `,`, and the comments
      // after its name up to the next `,` or `}`; the comments after the
      // `}` go before `exposing`.
      let e = d.exposing_list
      let fields = []
      let mut breaks = false
      let mut before = [..carried, ..self.take(Leading, first.range)]
      let mut before_exposing = []
      for k, x in names {
        let (label, n) = x
        let (after, moved) = self.trailing_split(n.range)
        let next_before = match names.get(k + 1) {
          Some((_, m)) => {
            let comma = self.token_back_to(m.range.start, ",", 3)
            after.append(
              self.take_if(Leading, m.range, c => ends_before(c, comma)),
            )
            [..moved, ..self.take(Leading, m.range)]
          }
          None => {
            let close = self.token_before(e.range.start)
            after.append(
              self.take_if(Leading, e.range, c => ends_before(c, close)),
            )
            before_exposing = [..moved, ..self.take(Leading, e.range)]
            []
          }
        }
        let label_at = self
          .token_back_to(n.range.start, label, 2)
          .unwrap_or(n.range.start)
        let (field, field_breaks) = effect_field(
          path.child(label, 0),
          label,
          label_at,
          n,
          before,
          after,
        )
        fields.push(field)
        breaks = breaks || field_breaks
        before = next_before
      }
      let name_breaks = after_name.iter().any(is_line_comment)
      if !name_breaks &&
        before_where.is_empty() &&
        !breaks &&
        before_exposing.is_empty() {
        let (_, last) = names[names.length() - 1]
        return head +
          comments_after(after_name) +
          @pretty.text(" where { ") +
          @pretty.join(fields, @pretty.text(", ")) +
          @pretty.text(" }") +
          self.exposing_doc(
            path.child("exposingList", 0),
            e,
            last.range,
            groups,
            comments,
            self.join(),
          )
      }
      let name_comments = if name_breaks {
        comment_block(after_name, before=true)
      } else {
        comments_after(after_name)
      }
      // The record follows `where` on its line unless it breaks, or a
      // comment comes before `where`.
      let record = sequence(self.join(), "{", "}", fields)
      let where_clause = if name_breaks || !before_where.is_empty() {
        @pretty.text("where") + @pretty.nest(4, @pretty.hardline() + record)
      } else {
        @pretty.text("where") +
        @pretty.group(@pretty.nest(4, @pretty.line() + record))
      }
      let (paren_comments, list, _) = self.exposing_list(
        path.child("exposingList", 0),
        e,
        groups,
        comments,
        self.join(),
      )
      let before_paren = before_paren_doc(e, paren_comments)
      // elm-format `spaceSepOrIndented`: the list goes on the next line when
      // the header up to `exposing` or the list is multi-line.
      head +
      @pretty.group(
        @pretty.group(
          @pretty.nest(
            4,
            name_comments +
            comment_block(before_where, before=true) +
            @pretty.line() +
            where_clause +
            comment_block(before_exposing, before=true) +
            @pretty.line() +
            @pretty.text("exposing") +
            before_paren,
          ),
        ) +
        @pretty.nest(4, @pretty.line() + @pretty.group(list)),
      )
    }
  }
}

///|
/// An import. `comments` and `split` are as for `Ctx::exposing_list`.
/// `after_name` are comments to print after the module name: those after
/// the names of the imports that this one merges (elm-format keeps them
/// with the clause after them).
fn Ctx::import_doc(
  self : Ctx,
  path : @syntax.NodePath,
  i : @ast.Node[@ast.Import],
  comments : ExposeComments,
  split : Split,
  after_name? : Array[@ast.Node[String]] = [],
) -> @pretty.Doc raise PrintError {
  let name = i.value.module_name
  // The comments after `as` (taken before the name's own comments).
  let moved = if i.value.module_alias is Some(_) {
    self.after_token(name.range)
  } else {
    []
  }
  let mut d = @pretty.text("import") +
    self.space_before(None, name.range, 4).0 +
    self.with_comments(
      name.range,
      @pretty.text(module_name(path.child("moduleName", 0), name.value)),
    ) +
    comments_after(after_name)
  let mut previous = name.range
  if i.value.module_alias is Some(a) {
    // An alias is one upper-case name: `import Html.Events as E`.
    let p = path.child("moduleAlias", 0)
    let alias_name = module_name(p, a.value)
    guard a.value.length() == 1 else {
      raise PrintError(path=p, problem=InvalidName(Upper, alias_name))
    }
    d = d +
      self.separator(previous, " as", moved) +
      self.space_before(None, a.range, 4).0 +
      self.with_comments(a.range, @pretty.text(alias_name))
    previous = a.range
  }
  if i.value.exposing_list is Some(x) {
    let groups = match x.value {
      Explicit(items) => ExposingGroups::single(items)
      All(_) => { groups: [], documented: 0, }
    }
    d = d +
      self.exposing_doc(
        path.child("exposingList", 0),
        x,
        previous,
        groups,
        comments,
        split,
        import_=true,
      )
  }
  d
}
