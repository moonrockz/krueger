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
  let own_line = cs
    .iter()
    .any(c => is_line_comment(c) || c.range.end.row < r.start.row)
  if own_line {
    (@pretty.nest(indent, @pretty.hardline() + comment_lines(cs)), true)
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
    AliasDeclaration(a) =>
      self.declaration_start(path, a.documentation, a.name.range) +
      self.type_head(path, "type alias", a.name, a.generics) +
      self.after(head_end(a.name, a.generics), " =") +
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
          @pretty.hardline() + comment_lines(before)
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
        let own_line = after
          .iter()
          .any(x => is_line_comment(x) || x.range.end.row < c.range.start.row)
        let after_bar = if own_line {
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
          spaced(
            Fit,
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
      @pretty.text("infix " + direction + " " + precedence.to_string() + " ") +
      self.with_comments(i.operator.range, @pretty.text("(" + symbol + ")")) +
      self.after(i.operator.range, " = ") +
      self.with_comments(
        i.function.range,
        self.lower_name(path.child("function", 0), i.function.value),
      )
    }
    Destructuring(pattern, value) =>
      // As in a let: a destructuring pattern is a term.
      @pretty.nest(
        4,
        self.pattern_doc(
          path.child("pattern", 0),
          level + 1,
          pattern,
          PatternArg,
        ) +
        self.after(pattern.range, " ="),
      ) +
      @pretty.nest(
        4,
        @pretty.hardline() +
        self.expr_doc(path.child("expression", 0), level + 1, value, AnyExpr),
      )
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
/// ` exposing (a, b)`, or ` exposing\n    ( a\n    , b\n    )` after a
/// module header. After an import (`import_ = true`), the broken form puts
/// `exposing` on its own line, as elm-format 0.8.7 does:
/// `\n    exposing\n        ( a\n        , b\n        )`. `previous` is
/// the range of the name before it.
fn Ctx::exposing_doc(
  self : Ctx,
  path : @syntax.NodePath,
  e : @ast.Node[@ast.Exposing],
  previous : @ast.Range,
  import_? : Bool = false,
) -> @pretty.Doc raise PrintError {
  // The comments before `exposing` go on lines of their own.
  let cs = self.take(Leading, e.range)
  let lead = if cs.is_empty() {
    None
  } else {
    Some(@pretty.nest(4, @pretty.hardline() + comment_lines(cs)))
  }
  match e.value {
    All(_) =>
      lead.unwrap_or(self.after(previous, " ")) +
      @pretty.text("exposing (") +
      self.inner_alone(e.range) +
      @pretty.text("..)")
    Explicit(items) => {
      guard !items.is_empty() else {
        raise PrintError(path~, problem=EmptyExposing)
      }
      // The comments before the `(` go after `exposing`.
      let paren = self.token_before(items[0].range.start)
      let before_paren = comments_after(
        self.take_if(Leading, items[0].range, c => ends_before(c, paren)),
      )
      let mut docs = @pretty.empty()
      for i, x in items {
        let previous = if i > 0 { Some(items[i - 1].range) } else { None }
        if i > 0 {
          docs = docs +
            @pretty.softline() +
            self.before_item(None, x.range) +
            @pretty.text(", ")
        }
        docs = docs +
          self.after_comma(previous, x.range) +
          self.expose_doc(path.child("explicit", i), x) +
          self.trailing_before_comma(
            x.range,
            items.get(i + 1).map(n => n.range),
          )
      }
      let list = @pretty.text("exposing") +
        before_paren +
        @pretty.nest(
          4,
          @pretty.line() +
          @pretty.text("(") +
          @pretty.if_break(@pretty.text(" "), @pretty.empty()) +
          docs +
          self.inner(e.range) +
          @pretty.softline() +
          @pretty.text(")"),
        )
      match (lead, import_) {
        (Some(l), true) => l + @pretty.group(@pretty.nest(4, list))
        (Some(l), false) => l + @pretty.group(list)
        (None, true) => @pretty.group(@pretty.nest(4, @pretty.line() + list))
        (None, false) => @pretty.group(self.after(previous, " ") + list)
      }
    }
  }
}

///|
fn Ctx::module_doc(
  self : Ctx,
  path : @syntax.NodePath,
  m : @ast.Node[@ast.Module],
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
      )
    }
    EffectModule(d) => {
      let fields = []
      if d.command is Some(c) {
        guard is_upper(c.value) else {
          raise PrintError(
            path=path.child("command", 0),
            problem=InvalidName(Upper, c.value),
          )
        }
        fields.push(
          @pretty.text("command = ") +
          self.with_comments(c.range, @pretty.text(c.value)),
        )
      }
      if d.subscription is Some(s) {
        guard is_upper(s.value) else {
          raise PrintError(
            path=path.child("subscription", 0),
            problem=InvalidName(Upper, s.value),
          )
        }
        fields.push(
          @pretty.text("subscription = ") +
          self.with_comments(s.range, @pretty.text(s.value)),
        )
      }
      guard !fields.is_empty() else {
        raise PrintError(path~, problem=NoFields)
      }
      let name = d.module_name
      @pretty.text("effect module") +
      self.space_before(None, name.range, 4).0 +
      self.with_comments(
        name.range,
        @pretty.text(module_name(path.child("moduleName", 0), name.value)),
      ) +
      @pretty.text(" where { ") +
      @pretty.join(fields, @pretty.text(", ")) +
      @pretty.text(" }") +
      self.exposing_doc(
        path.child("exposingList", 0),
        d.exposing_list,
        // `}` comes before `exposing`, not a name. No comment trails the
        // exposing list inside the header, so this gives a space.
        d.exposing_list.range,
      )
    }
  }
}

///|
fn Ctx::import_doc(
  self : Ctx,
  path : @syntax.NodePath,
  i : @ast.Node[@ast.Import],
) -> @pretty.Doc raise PrintError {
  let name = i.value.module_name
  let mut d = @pretty.text("import") +
    self.space_before(None, name.range, 4).0 +
    self.with_comments(
      name.range,
      @pretty.text(module_name(path.child("moduleName", 0), name.value)),
    )
  let mut previous = name.range
  if i.value.module_alias is Some(a) {
    // An alias is one upper-case name: `import Html.Events as E`.
    let p = path.child("moduleAlias", 0)
    let alias_name = module_name(p, a.value)
    guard a.value.length() == 1 else {
      raise PrintError(path=p, problem=InvalidName(Upper, alias_name))
    }
    d = d +
      self.after(previous, " as") +
      self.space_before(None, a.range, 4).0 +
      self.with_comments(a.range, @pretty.text(alias_name))
    previous = a.range
  }
  if i.value.exposing_list is Some(x) {
    d = d +
      self.exposing_doc(
        path.child("exposingList", 0),
        x,
        previous,
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
fn line_breaks(n : Int) -> @pretty.Doc {
  let mut d = @pretty.empty()
  for _ in 0..<n {
    d = d + @pretty.hardline()
  }
  d
}

///|
/// Comments each on its own line, joined by line breaks.
fn comment_block(cs : Array[@ast.Node[String]]) -> @pretty.Doc {
  @pretty.join(cs.map(comment_doc), @pretty.hardline())
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
fn Ctx::file_doc(self : Ctx, file : @ast.File) -> @pretty.Doc raise PrintError {
  let root = @syntax.NodePath::root()
  let port_docs : Array[@pretty.Doc?] = Array::make(
    file.declarations.length(),
    None,
  )
  let mut module_docs : @pretty.Doc? = None
  for i, c in file.comments {
    guard c.value.has_prefix("{-|") else { continue }
    let doc = documentation_doc(root.child("comments", i), c.value)
    let mut port = -1
    for j, decl in file.declarations {
      if decl.value is PortDeclaration(_) &&
        decl.range.start.row == c.range.end.row + 1 {
        port = j
        break
      }
    }
    if port >= 0 {
      port_docs[port] = Some(doc)
    } else if module_docs is None {
      module_docs = Some(doc)
    }
  }
  let header = file.module_definition
  let initial = self.take(Leading, header.range)
  let mut d = if initial.is_empty() {
    @pretty.empty()
  } else {
    comment_block(initial) + line_breaks(3)
  }
  d = d + self.module_doc(root.child("moduleDefinition", 0), header)
  if module_docs is Some(m) {
    d = d + line_breaks(2) + m
  }
  // The comments of the import section, and the imports.
  let import_comments = self.take(Trailing, header.range)
  let imports = []
  let last_import = file.imports.length() - 1
  for i, imp in file.imports {
    import_comments.append(self.take(Leading, imp.range))
    imports.push(self.import_doc(root.child("imports", i), imp))
    if i < last_import {
      import_comments.append(self.take(Trailing, imp.range))
    }
  }
  let file_range = @syntax.NodeRef::File(file, [][:]).range()
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
    let after_imports = self.take(Trailing, file.imports[last_import].range)
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
