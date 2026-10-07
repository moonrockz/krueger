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
/// The comments before the keyword of a type, type alias or port
/// declaration that has no documentation (`type {- a -} alias A`). They
/// are top-level body comments.
fn Ctx::before_keyword(
  self : Ctx,
  decl : @ast.Node[@ast.Declaration],
) -> Array[@ast.Node[String]] {
  // A type alias with no documentation starts at its `type`: its comments
  // before `alias` are its own (see `Ctx::alias_doc`).
  let name = match decl.value {
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
/// them body comments. The keyword is the token `keyword_back` tokens
/// before the name (2 for the `type` of `type alias`).
fn Ctx::declaration_start(
  self : Ctx,
  path : @syntax.NodePath,
  doc : @ast.Node[String]?,
  name : @ast.Range,
  keyword_back? : Int = 1,
) -> @pretty.Doc raise PrintError {
  let docs = match doc {
    Some(x) =>
      self.documentation_doc(path.child("documentation", 0), x.value) +
      self.trailing(x.range)
    None => @pretty.empty()
  }
  let keyword = self.token_back(name.start, keyword_back)
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
    AliasDeclaration(a) => self.alias_doc(path, level, a)
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
/// A part of the module body: a block of regular comments or a
/// declaration (elm-format's `TopLevelStructure`).
priv enum BodyEntry {
  Comments(Array[@ast.Node[String]])
  /// `{--}`, the start of a comment trick.
  Opener(@ast.Node[String])
  /// `--}`, the end of a comment trick.
  Closer(@ast.Node[String])
  Decl(Int, @ast.Node[@ast.Declaration])
}

///|
/// Adds comments `cs` to the body `entries`: each comment trick opener
/// (`{--}`) and closer (`--}`) is an entry of its own (elm-format
/// Parse/Whitespace.hs `CommentTrickOpener`, `CommentTrickCloser`).
fn push_comments(
  entries : Array[BodyEntry],
  cs : Array[@ast.Node[String]],
) -> Unit {
  let run = []
  let flush = () => {
    if !run.is_empty() {
      entries.push(Comments(run.copy()))
      run.clear()
    }
  }
  for c in cs {
    if c.value == "{--}" {
      flush()
      entries.push(Opener(c))
    } else if is_line_comment(c) && comment_text(c.value) == "--}" {
      flush()
      entries.push(Closer(c))
    } else {
      run.push(c)
    }
  }
  flush()
}

///|
/// The number of blank lines between two body entries (elm-format 0.8.7
/// `formatTopLevelBody`, with 2 lines between declarations).
fn blank_lines_between(a : BodyEntry, b : BodyEntry) -> Int {
  // The cases in the order of elm-format's `spacer`: the first that
  // matches decides.
  match (a, b) {
    (Opener(_), _) | (_, Closer(_)) => 0
    (Comments(_), Comments(_)) => 0
    (_, Comments(_)) => 3
    (Decl(_, x), Decl(_, y)) =>
      if x.value is InfixDeclaration(_) && y.value is InfixDeclaration(_) {
        0
      } else {
        2
      }
    _ => 2
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
  let file = normalize_header(source)
  let port_docs : Array[@pretty.Doc?] = Array::make(
    file.declarations.length(),
    None,
  )
  let mut module_docs : @pretty.Doc? = None
  for i, c in file.comments {
    guard c.value.has_prefix("{-|") else { continue }
    let doc = self.documentation_doc(root.child("comments", i), c.value)
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
    push_comments(
      entries,
      self.take(Trailing, source.imports[last_import].range),
    )
  }
  let docs = []
  for i, decl in file.declarations {
    let before = self.take(Leading, decl.range)
    before.append(self.before_keyword(decl))
    push_comments(entries, before)
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
    push_comments(entries, self.take(Trailing, decl.range))
  }
  push_comments(entries, self.take(Inner, file_range))
  for i, entry in entries {
    let blank = if i == 0 {
      if entry is Decl(_, _) {
        2
      } else {
        3
      }
    } else {
      blank_lines_between(entries[i - 1], entry)
    }
    d = d +
      line_breaks(blank + 1) +
      (match entry {
        Comments(cs) => comment_block(cs)
        Opener(c) | Closer(c) => comment_doc(c)
        Decl(k, _) => docs[k]
      })
  }
  d + @pretty.hardline()
}

///|
/// The comments `cs` as elm-format joins them (`formatComments`), and
/// whether they are one line; `None` when there are none.
fn comments_part(cs : Array[@ast.Node[String]]) -> (@pretty.Doc, Bool)? {
  if cs.is_empty() {
    None
  } else {
    Some((comment_box(cs), cs.iter().all(one_line)))
  }
}

///|
/// Parts on one line, separated by spaces, when each is one line; else
/// each on its own line (elm-format `ElmStructure.spaceSepOrStack`). A
/// part is a doc and whether it is one line.
fn row_or_stack(parts : Array[(@pretty.Doc, Bool)]) -> (@pretty.Doc, Bool) {
  let single = parts.iter().all(p => p.1)
  let gap = if single { @pretty.text(" ") } else { @pretty.hardline() }
  (@pretty.join(parts.map(p => p.0), gap), single)
}

///|
/// `first` and `rest` on one line when each is one line, else `first`
/// with each part of `rest` on its own line, indented by 4. With `join`,
/// the first part of `rest` stays on the line of `first` when both are
/// one line (elm-format `ElmStructure.application (FAJoinFirst JoinAll)`).
fn row_or_indented(
  first : (@pretty.Doc, Bool),
  rest : Array[(@pretty.Doc, Bool)],
  join? : Bool = false,
) -> (@pretty.Doc, Bool) {
  if first.1 && rest.iter().all(p => p.1) {
    let parts = [first]
    parts.append(rest)
    return row_or_stack(parts)
  }
  let mut d = first.0
  for i, p in rest {
    d = if i == 0 && join && first.1 && p.1 {
      d + @pretty.text(" ") + p.0
    } else {
      d + @pretty.nest(4, @pretty.hardline() + p.0)
    }
  }
  (d, false)
}

///|
/// A type alias, as elm-format 0.8.7 writes it (Box.hs `TypeAlias`):
/// `type`, the comments before `alias` and `alias`, then the name with its
/// arguments and their comments (`formatNameWithArgs`), then ` =` on the
/// line when that head is one line, else `=` on a line of its own, and the
/// type on the next line after the comments before it, each on its own
/// line (`formatPreCommentedStack`).
fn Ctx::alias_doc(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  a : @ast.TypeAlias,
) -> @pretty.Doc raise PrintError {
  let start = self.declaration_start(
    path,
    a.documentation,
    a.name.range,
    keyword_back=2,
  )
  let name = a.name
  let alias_at = self.token_before(name.range.start)
  let pre_alias = self.take_if(Leading, name.range, c => {
    ends_before(c, alias_at)
  })
  let pre_name = self.take(Leading, name.range)
  // The comments before each argument: those after the part before it,
  // then its own.
  let args = []
  let mut previous = name.range
  let name_doc = upper_name(path.child("name", 0), name.value)
  for i, g in a.generics {
    let pre = self.take(Trailing, previous)
    pre.append(self.take(Leading, g.range))
    let d = self.lower_name(path.child("generics", i), g.value)
    args.push(
      match comments_part(pre) {
        Some(c) => row_or_stack([c, (d, true)])
        None => (d, true)
      },
    )
    previous = g.range
  }
  let t = a.type_annotation
  let equals = self.token_after(previous.end)
  let post = self.take_if(Trailing, previous, c => ends_before(c, equals))
  post.append(self.take_if(Leading, t.range, c => ends_before(c, equals)))
  let body_pre = self.take(Trailing, previous)
  body_pre.append(self.take(Leading, t.range))
  // `formatNameWithArgs`, then `formatCommented` with the comments before
  // the name and before the `=`.
  let name_args = row_or_indented((name_doc, true), args)
  let parts = []
  if comments_part(pre_name) is Some(c) {
    parts.push(c)
  }
  parts.push(name_args)
  if comments_part(post) is Some(c) {
    parts.push(c)
  }
  let alias_part = match comments_part(pre_alias) {
    Some(c) => row_or_stack([c, (@pretty.text("alias"), true)])
    None => (@pretty.text("alias"), true)
  }
  let (head, one_line) = row_or_indented(
    (@pretty.text("type"), true),
    [alias_part, row_or_stack(parts)],
    join=true,
  )
  let body = comment_block(body_pre, after=true) +
    self.type_doc(path.child("typeAnnotation", 0), level + 1, t, AnyType)
  start +
  head +
  (if one_line {
    @pretty.text(" =")
  } else {
    @pretty.nest(4, @pretty.hardline() + @pretty.text("="))
  }) +
  @pretty.nest(4, @pretty.hardline() + body)
}
