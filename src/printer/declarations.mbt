///|
/// The space before the node at `r`, with its leading comments. Block
/// comments that end on the node's line stay on the line: ` {- a -} x`.
/// Other comments go on lines of their own, indented by `indent`, and the
/// node starts the next line; then the result is true. `previous` is the
/// range of the node before it, if any.
fn Ctx::space_before(
  self : Ctx,
  previous : @ast.Range?,
  r : @ast.Range,
  indent : Int,
) -> (@pretty.Doc, Bool) {
  let cs = self.take(Leading, r)
  if cs.iter().any(c => ends_line(c, r.start)) {
    (@pretty.nest(indent, comment_block(cs, before=true, after=true)), true)
  } else {
    let space = match previous {
      Some(p) => self.after(p, " ")
      None => @pretty.text(" ")
    }
    (space + comments_before(cs, r.start), false)
  }
}

///|
/// `keyword Name a b` for a type declaration, with the comments of the
/// name and the generics (elm-format puts each one that has a comment on
/// its own line before it on lines of its own).
fn Ctx::type_head(
  self : Ctx,
  path : @syntax.NodePath,
  keyword : String,
  name : @ast.Node[String],
  names : ArrayView[@ast.Node[String]],
) -> @pretty.Doc raise PrintError {
  let (space, nested) = self.space_before(None, name.range, 4)
  let mut d = @pretty.text(keyword) +
    space +
    self.with_comments(
      name.range,
      upper_name(path.child("name", 0), name.value),
    )
  let indent = if nested { 8 } else { 4 }
  let mut previous = name.range
  for i, g in names {
    let (space, _) = self.space_before(Some(previous), g.range, indent)
    d = d +
      space +
      self.with_comments(
        g.range,
        self.lower_name(path.child("generics", i), g.value),
      )
    previous = g.range
  }
  d
}

///|
/// The range of the last part of a type declaration's head.
fn head_end(
  name : @ast.Node[String],
  names : ArrayView[@ast.Node[String]],
) -> @ast.Range {
  match names.last() {
    Some(g) => g.range
    None => name.range
  }
}

///|
/// The comments before the keyword of a type, type alias or port
/// declaration that has no documentation (`type {- a -} alias A`). They
/// are top-level body comments.
fn Ctx::before_keyword(
  self : Ctx,
  decl : @ast.Node[@ast.Declaration],
) -> Array[@ast.Node[String]] {
  let name = match decl.value {
    AliasDeclaration(a) if a.documentation is None => a.name.range
    CustomTypeDeclaration(t) if t.documentation is None => t.name.range
    PortDeclaration(s) => s.name.range
    _ => return []
  }
  let keyword = self.token_before(name.start)
  self.take_if(Leading, name, c => ends_before(c, keyword))
}

///|
/// The documentation of a declaration, then the comments before its
/// keyword (the leading comments of its name that come before the keyword):
/// with documentation, a block between blank lines, as elm-format makes
/// them body comments.
fn Ctx::declaration_start(
  self : Ctx,
  path : @syntax.NodePath,
  doc : @ast.Node[String]?,
  name : @ast.Range,
) -> @pretty.Doc raise PrintError {
  let docs = match doc {
    Some(x) =>
      documentation_doc(path.child("documentation", 0), x.value) +
      self.trailing(x.range)
    None => @pretty.empty()
  }
  let keyword = self.token_before(name.start)
  let cs = self.take_if(Leading, name, c => ends_before(c, keyword))
  match (doc, cs.is_empty()) {
    (None, true) => @pretty.empty()
    (Some(_), true) => docs + @pretty.hardline()
    (None, false) => comment_block(cs) + @pretty.hardline()
    (Some(_), false) =>
      docs + line_breaks(4) + comment_block(cs) + line_breaks(3)
  }
}

///|
fn Ctx::declaration_doc(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  d : @ast.Node[@ast.Declaration],
) -> @pretty.Doc raise PrintError {
  check_level(path, level)
  match d.value {
    FunctionDeclaration(f) => self.function_doc(path, level, f)
    AliasDeclaration(a) => {
      let last = head_end(a.name, a.generics)
      let moved = self.after_token(last)
      self.declaration_start(path, a.documentation, a.name.range) +
      self.type_head(path, "type alias", a.name, a.generics) +
      self.separator(last, " =", moved) +
      @pretty.nest(
        4,
        @pretty.hardline() +
        self.type_doc(
          path.child("typeAnnotation", 0),
          level + 1,
          a.type_annotation,
          AnyType,
        ),
      )
    }
    CustomTypeDeclaration(t) => {
      guard !t.constructors.is_empty() else {
        raise PrintError(path~, problem=NoConstructors)
      }
      let start = self.declaration_start(path, t.documentation, t.name.range)
      let head = self.type_head(path, "type", t.name, t.generics)
      let mut ctors = @pretty.empty()
      for i, c in t.constructors {
        let p = path.child("constructors", i)
        // The comments before the `=` or `|` of a constructor: before the
        // `=` on lines of their own; before a `|`, after the constructor
        // before it, indented by 2 (elm-format).
        let bar = self.token_before(c.range.start)
        let before = self.take_if(Leading, c.range, x => ends_before(x, bar))
        let lead = if i == 0 {
          @pretty.hardline() + comment_block(before, after=true)
        } else {
          let mut d = @pretty.empty()
          for x in before {
            d = d + @pretty.nest(2, @pretty.hardline() + comment_doc(x))
          }
          d + @pretty.hardline()
        }
        // The comments after the `=` or `|`: on the line, or each followed
        // by a line break to the column of the name.
        let after = self.take(Leading, c.range)
        let after_bar = if after.iter().any(x => ends_line(x, c.range.start)) {
          let mut d = @pretty.empty()
          for x in after {
            d = d + comment_doc(x) + @pretty.nest(2, @pretty.hardline())
          }
          d
        } else {
          comments_before(after, c.range.start)
        }
        let name = c.value.name
        let args = []
        for j, a in c.value.arguments {
          args.push(
            self.type_doc(p.child("arguments", j), level + 1, a, TypeArg),
          )
        }
        ctors = ctors +
          lead +
          @pretty.text(if i == 0 { "= " } else { "| " }) +
          after_bar +
          // elm-format Box.hs `Datatype`: the arguments go on their own
          // lines when one of them is multi-line.
          spaced(
            self.join(),
            self.with_comments(
              name.range,
              upper_name(p.child("name", 0), name.value),
            ),
            args,
          ) +
          self.trailing(c.range)
      }
      start + head + @pretty.nest(4, ctors)
    }
    // A port's `name` and `typeAnnotation` are fields of the declaration.
    PortDeclaration(s) =>
      self.declaration_start(path, None, s.name.range) +
      @pretty.text("port") +
      self.space_before(None, s.name.range, 4).0 +
      self.signature_doc(path, level, s)
    InfixDeclaration(i) => {
      // elm-format pads the direction to 5 columns: `infix left  0 (|>) = apR`.
      let direction = match i.direction.value {
        Left => "left "
        Right => "right"
        Non => "non  "
      }
      let precedence = i.precedence.value
      // The precedence is not a node of the syntax tree (`NodeRef`), so the
      // path is the declaration's.
      guard precedence >= 0 && precedence <= 9 else {
        raise PrintError(path~, problem=InvalidPrecedence(precedence))
      }
      let symbol = self.operator_symbol(
        path.child("operator", 0),
        i.operator.value,
      )
      let function = self.lower_name(
        path.child("function", 0),
        i.function.value,
      )
      let operator = i.operator.range
      let before_operator = self.take(Leading, operator)
      // The comments after the operator: before the `=` they follow the
      // operator, after it they go before the function.
      let (after_operator, after_equals) = self.trailing_split(operator)
      let equals = self.token_before(i.function.range.start)
      after_operator.append(
        self.take_if(Leading, i.function.range, c => ends_before(c, equals)),
      )
      let before_function = [
        ..after_equals,
        ..self.take(Leading, i.function.range),
      ]
      let breaks = before_operator.iter().any(c => ends_line(c, operator.start)) ||
        after_operator.iter().any(c => off_line(c, operator)) ||
        before_function.iter().any(c => ends_line(c, i.function.range.start))
      if !breaks {
        @pretty.text("infix " + direction + " " + precedence.to_string() + " ") +
        comments_before(before_operator, operator.start) +
        @pretty.text("(" + symbol + ")") +
        comments_after(after_operator) +
        @pretty.text(" = ") +
        comments_before(before_function, i.function.range.start) +
        function
      } else {
        // A comment that ends its line: elm-format puts each part on its
        // own line.
        @pretty.text("infix") +
        @pretty.nest(
          4,
          @pretty.hardline() +
          @pretty.text(direction.trim_end().to_owned()) +
          @pretty.hardline() +
          @pretty.text(precedence.to_string()) +
          @pretty.hardline() +
          comment_block(before_operator, after=true) +
          @pretty.text("(" + symbol + ")") +
          comment_block(after_operator, before=true) +
          @pretty.hardline() +
          @pretty.text("=") +
          @pretty.hardline() +
          comment_block(before_function, after=true) +
          function,
        )
      }
    }
    Destructuring(pattern, value) => {
      let moved = self.after_token(pattern.range)
      // As in a let: a destructuring pattern is a term.
      @pretty.nest(
        4,
        self.pattern_doc(
          path.child("pattern", 0),
          level + 1,
          pattern,
          PatternArg,
        ) +
        self.separator(pattern.range, " =", moved),
      ) +
      @pretty.nest(
        4,
        @pretty.hardline() +
        self.expr_doc(path.child("expression", 0), level + 1, value, AnyExpr),
      )
    }
  }
}

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
/// the comments before the `(`, which go after `exposing`, and whether
/// the list is one line that does not break in the `Width` layout.
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
) -> (@pretty.Doc, @pretty.Doc, Bool) raise PrintError {
  match e.value {
    All(_) => {
      // `(..)` has no children: its comments before the `(` are inner too.
      let paren = self.token_back_to(e.range.end, "(", 3)
      let before_paren = self.take_if(Inner, e.range, c => ends_before(c, paren))
      let gap = if before_paren.iter().any(is_line_comment) {
        @pretty.nest(4, @pretty.hardline())
      } else {
        @pretty.empty()
      }
      (
        comments_after(before_paren) + gap,
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
      (
        comments_after(comments.before_paren),
        list,
        fixed && flat && footer.is_empty(),
      )
    }
  }
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
  let (before_paren, items, one_line) = self.exposing_list(
    path, e, groups, comments, split,
  )
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
      let gap = if one_line &&
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
      let (before_paren, list, _) = self.exposing_list(
        path.child("exposingList", 0),
        e,
        groups,
        comments,
        self.join(),
      )
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

///|
/// A part of the module body: a block of regular comments or a
/// declaration (elm-format's `TopLevelStructure`).
priv enum BodyEntry {
  Comments(Array[@ast.Node[String]])
  Decl(Int, @ast.Node[@ast.Declaration])
}

///|
/// The number of blank lines between two body entries (elm-format 0.8.7
/// `formatTopLevelBody`, with 2 lines between declarations).
fn blank_lines_between(a : BodyEntry, b : BodyEntry) -> Int {
  match (a, b) {
    (Comments(_), Comments(_)) => 0
    (_, Comments(_)) => 3
    (Comments(_), Decl(_, _)) => 2
    (Decl(_, x), Decl(_, y)) =>
      if x.value is InfixDeclaration(_) && y.value is InfixDeclaration(_) {
        0
      } else {
        2
      }
  }
}

///|
/// Checks the parts of `file` that `normalize_file` moves (the items of the
/// module's exposing list and the imports), so that a `PrintError` names
/// their path in `file`, not in the normalized file.
fn Ctx::check_moved(self : Ctx, file : @ast.File) -> Unit raise PrintError {
  let check = Ctx::new(self.dialect, layout=self.layout)
  let root = @syntax.NodePath::root()
  let path = root.child("moduleDefinition", 0).child("exposingList", 0)
  if exposing_of(file.module_definition.value).value is Explicit(items) {
    guard !items.is_empty() else {
      raise PrintError(path~, problem=EmptyExposing)
    }
    for i, x in items {
      ignore(check.expose_doc(path.child("explicit", i), x))
    }
  }
  for i, imp in file.imports {
    ignore(
      check.import_doc(
        root.child("imports", i),
        imp,
        ExposeComments::new(),
        check.join(),
      ),
    )
  }
}

///|
/// The whole file in the elm-format layout. The `{-|` comments of
/// `File.comments` are printed: one that ends on the row before a port
/// declaration goes above that port, and the first other one is the
/// module documentation.
///
/// Regular comments at the top level go where elm-format 0.8.7 puts them
/// (`formatModule`, `formatImports`, `formatTopLevelBody`): comments
/// before the module header above it; comments in the header and between
/// imports above the imports (with no imports, also the comments before
/// the first declaration); other comments as blocks between declarations.
///
/// The file is printed in elm-format's order (see `normalize_file`); its
/// comments go with their nodes. A `PrintError` names a path in `source`.
fn Ctx::file_doc(
  self : Ctx,
  source : @ast.File,
) -> @pretty.Doc raise PrintError {
  let root = @syntax.NodePath::root()
  self.check_moved(source)
  let file = normalize_file(source)
  let port_docs : Array[@pretty.Doc?] = Array::make(
    file.declarations.length(),
    None,
  )
  let mut module_docs : @pretty.Doc? = None
  for i, c in file.comments {
    guard c.value.has_prefix("{-|") else { continue }
    let doc = documentation_doc(root.child("comments", i), c.value)
    match documented_port(file, c) {
      Some(port) => port_docs[port] = Some(doc)
      None => if module_docs is None { module_docs = Some(doc) }
    }
  }
  let header = file.module_definition
  let initial = self.take(Leading, header.range)
  let mut d = if initial.is_empty() {
    @pretty.empty()
  } else {
    comment_block(initial) + line_breaks(3)
  }
  let exposing = exposing_of(source.module_definition.value)
  let exposing_comments = ExposeComments::new()
  self.take_expose_comments(exposing, exposing_comments)
  d = d +
    self.module_doc(
      root.child("moduleDefinition", 0),
      header,
      exposing_groups(file, self.list_split(exposing)),
      exposing_comments,
    )
  if module_docs is Some(m) {
    d = d + line_breaks(2) + m
  }
  // The comments of the import section, and the imports. The comments
  // between imports are taken by the imports of the source; each import
  // of the file takes the comments of its exposing list from the source
  // imports that it merges.
  let import_comments = self.take(Trailing, header.range)
  let last_import = source.imports.length() - 1
  let merged : Map[String, Array[@ast.Node[@ast.Import]]] = Map([])
  for i, imp in source.imports {
    import_comments.append(self.take(Leading, imp.range))
    if i < last_import {
      import_comments.append(self.take(Trailing, imp.range))
    }
    let key = module_key(imp.value.module_name.value)
    match merged.get(key) {
      Some(list) => list.push(imp)
      None => merged[key] = [imp]
    }
  }
  let imports = []
  for i, imp in file.imports {
    let sources = merged
      .get(module_key(imp.value.module_name.value))
      .unwrap_or([imp])
    let comments = ExposeComments::new()
    let after_name = []
    for k in 1..<sources.length() {
      after_name.append(
        self.take_if(Trailing, sources[k].value.module_name.range, c => {
          !is_line_comment(c)
        }),
      )
    }
    // The comments after `as` of an alias that a later import replaces.
    // `Ctx::import_doc` would print them after the new alias.
    let replaced = match
      (sources[0].value.module_alias, imp.value.module_alias) {
      (Some(old), Some(new)) if old.range != new.range =>
        self.after_token(sources[0].value.module_name.range)
      _ => []
    }
    // When `(..)` replaces the lists, their comments stay for the sweep
    // below.
    let mut split = self.join()
    if imp.value.exposing_list is Some({ value: Explicit(_), .. }) {
      for s in sources {
        if s.value.exposing_list is Some(e) {
          self.take_expose_comments(e, comments)
          if self.list_split(e) is Split {
            split = Split
          }
        }
      }
    }
    imports.push(
      self.import_doc(
        root.child("imports", i),
        imp,
        comments,
        split,
        after_name~,
      ),
    )
    // The comments of the nodes that the merge removed (an alias, a
    // module name) go before the imports.
    import_comments.append(replaced)
    if sources.length() > 1 ||
      (
        sources[0].value.module_alias is Some(_) &&
        imp.value.module_alias is None
      ) {
      for s in sources {
        import_comments.append(self.take_within(s.range))
      }
    }
  }
  let file_range = @syntax.NodeRef::File(source, [][:]).range()
  if imports.is_empty() {
    // With no imports, the comments before the first declaration (or at the
    // end of a module with no declarations) are in the import section.
    match file.declarations.get(0) {
      Some(first) => {
        import_comments.append(self.take(Leading, first.range))
        import_comments.append(self.before_keyword(first))
      }
      None => import_comments.append(self.take(Inner, file_range))
    }
  }
  if !import_comments.is_empty() {
    d = d + line_breaks(2) + comment_block(import_comments)
  }
  if !imports.is_empty() {
    d = d + line_breaks(2) + @pretty.join(imports, @pretty.hardline())
  }
  // The module body.
  let entries = []
  if last_import >= 0 {
    let after_imports = self.take(Trailing, source.imports[last_import].range)
    if !after_imports.is_empty() {
      entries.push(Comments(after_imports))
    }
  }
  let docs = []
  for i, decl in file.declarations {
    let before = self.take(Leading, decl.range)
    before.append(self.before_keyword(decl))
    if !before.is_empty() {
      entries.push(Comments(before))
    }
    let mut doc = self.declaration_doc(root.child("declarations", i), 0, decl)
    if port_docs[i] is Some(pd) {
      doc = pd + @pretty.hardline() + doc
    }
    // elm-format keeps a comment after a custom type or a port on its line;
    // after other declarations it is a body comment.
    if decl.value is (CustomTypeDeclaration(_) | PortDeclaration(_)) {
      doc = doc + self.trailing(decl.range)
    }
    docs.push(doc)
    entries.push(Decl(i, decl))
    let after = self.take(Trailing, decl.range)
    if !after.is_empty() {
      entries.push(Comments(after))
    }
  }
  let last = self.take(Inner, file_range)
  if !last.is_empty() {
    entries.push(Comments(last))
  }
  for i, entry in entries {
    let blank = if i == 0 {
      if entry is Comments(_) {
        3
      } else {
        2
      }
    } else {
      blank_lines_between(entries[i - 1], entry)
    }
    d = d +
      line_breaks(blank + 1) +
      (match entry {
        Comments(cs) => comment_block(cs)
        Decl(k, _) => docs[k]
      })
  }
  d + @pretty.hardline()
}
