///|
fn Ctx::generics(
  self : Ctx,
  path : @syntax.NodePath,
  names : ArrayView[@ast.Node[String]],
) -> @pretty.Doc raise PrintError {
  let mut d = @pretty.empty()
  for i, g in names {
    d = d +
      @pretty.text(" ") +
      self.lower_name(path.child("generics", i), g.value)
  }
  d
}

///|
fn documentation_line(
  path : @syntax.NodePath,
  doc : @ast.Node[String]?,
) -> @pretty.Doc raise PrintError {
  match doc {
    Some(x) =>
      documentation_doc(path.child("documentation", 0), x.value) +
      @pretty.hardline()
    None => @pretty.empty()
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
      documentation_line(path, a.documentation) +
      @pretty.text("type alias ") +
      upper_name(path.child("name", 0), a.name.value) +
      self.generics(path, a.generics) +
      @pretty.text(" =") +
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
      let mut ctors = @pretty.empty()
      for i, c in t.constructors {
        let p = path.child("constructors", i)
        let args = []
        for j, a in c.value.arguments {
          args.push(
            self.type_doc(p.child("arguments", j), level + 1, a, TypeArg),
          )
        }
        ctors = ctors +
          @pretty.hardline() +
          @pretty.text(if i == 0 { "= " } else { "| " }) +
          spaced(upper_name(p.child("name", 0), c.value.name.value), args)
      }
      documentation_line(path, t.documentation) +
      @pretty.text("type ") +
      upper_name(path.child("name", 0), t.name.value) +
      self.generics(path, t.generics) +
      @pretty.nest(4, ctors)
    }
    // A port's `name` and `typeAnnotation` are fields of the declaration.
    PortDeclaration(s) =>
      @pretty.text("port ") + self.signature_doc(path, level, s)
    InfixDeclaration(i) => {
      // elm-format pads the direction to 5 columns: `infix left  0 (|>) = apR`.
      let direction = match i.direction.value {
        Left => "left "
        Right => "right"
        Non => "non  "
      }
      let symbol = operator_symbol(path.child("operator", 0), i.operator.value)
      @pretty.text(
        "infix " +
        direction +
        " " +
        i.precedence.value.to_string() +
        " (" +
        symbol +
        ") = ",
      ) +
      self.lower_name(path.child("function", 0), i.function.value)
    }
    Destructuring(pattern, value) =>
      // As in a let: a destructuring pattern is a term.
      self.pattern_doc(path.child("pattern", 0), level + 1, pattern, PatternArg) +
      @pretty.text(" =") +
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
  x : @ast.TopLevelExpose,
) -> @pretty.Doc raise PrintError {
  match x {
    InfixExpose(symbol) =>
      @pretty.text("(" + operator_symbol(path, symbol) + ")")
    FunctionExpose(name) => self.lower_name(path, name)
    TypeOrAliasExpose(name) => upper_name(path, name)
    TypeExpose(t) =>
      upper_name(path, t.name) +
      (if t.open is Some(_) { @pretty.text("(..)") } else { @pretty.empty() })
  }
}

///|
/// `exposing (a, b)`, or `exposing\n    ( a\n    , b\n    )` (elm-format).
fn Ctx::exposing_doc(
  self : Ctx,
  path : @syntax.NodePath,
  e : @ast.Node[@ast.Exposing],
) -> @pretty.Doc raise PrintError {
  match e.value {
    All(_) => @pretty.text("exposing (..)")
    Explicit(items) => {
      guard !items.is_empty() else {
        raise PrintError(path~, problem=EmptyExposing)
      }
      let docs = []
      for i, x in items {
        docs.push(self.expose_doc(path.child("explicit", i), x.value))
      }
      @pretty.group(
        @pretty.text("exposing") +
        @pretty.nest(
          4,
          @pretty.line() +
          @pretty.text("(") +
          @pretty.if_break(@pretty.text(" "), @pretty.empty()) +
          @pretty.join(docs, @pretty.softline() + @pretty.text(", ")) +
          @pretty.softline() +
          @pretty.text(")"),
        ),
      )
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
        "port module "
      } else {
        "module "
      }
      @pretty.text(
        keyword +
        module_name(path.child("moduleName", 0), d.module_name.value) +
        " ",
      ) +
      self.exposing_doc(path.child("exposingList", 0), d.exposing_list)
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
        fields.push("command = " + c.value)
      }
      if d.subscription is Some(s) {
        guard is_upper(s.value) else {
          raise PrintError(
            path=path.child("subscription", 0),
            problem=InvalidName(Upper, s.value),
          )
        }
        fields.push("subscription = " + s.value)
      }
      guard !fields.is_empty() else {
        raise PrintError(path~, problem=NoFields)
      }
      @pretty.text(
        "effect module " +
        module_name(path.child("moduleName", 0), d.module_name.value) +
        " where { " +
        fields.join(", ") +
        " } ",
      ) +
      self.exposing_doc(path.child("exposingList", 0), d.exposing_list)
    }
  }
}

///|
fn Ctx::import_doc(
  self : Ctx,
  path : @syntax.NodePath,
  i : @ast.Node[@ast.Import],
) -> @pretty.Doc raise PrintError {
  let mut d = @pretty.text(
    "import " +
    module_name(path.child("moduleName", 0), i.value.module_name.value),
  )
  if i.value.module_alias is Some(a) {
    d = d +
      @pretty.text(" as " + module_name(path.child("moduleAlias", 0), a.value))
  }
  if i.value.exposing_list is Some(x) {
    d = d +
      @pretty.text(" ") +
      self.exposing_doc(path.child("exposingList", 0), x)
  }
  d
}

///|
/// The whole file in the elm-format layout. The `{-|` comments of
/// `File.comments` are printed: one that ends on the row before a port
/// declaration goes above that port, and the first other one is the
/// module documentation. Other comments are not printed.
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
  let mut d = self.module_doc(
    root.child("moduleDefinition", 0),
    file.module_definition,
  )
  if module_docs is Some(m) {
    d = d + @pretty.hardline() + @pretty.hardline() + m
  }
  if !file.imports.is_empty() {
    d = d + @pretty.hardline() + @pretty.hardline()
    for i, imp in file.imports {
      if i > 0 {
        d = d + @pretty.hardline()
      }
      d = d + self.import_doc(root.child("imports", i), imp)
    }
  }
  for i, decl in file.declarations {
    let infix_pair = i > 0 &&
      decl.value is InfixDeclaration(_) &&
      file.declarations[i - 1].value is InfixDeclaration(_)
    d = d +
      (if infix_pair {
        @pretty.hardline()
      } else {
        @pretty.hardline() + @pretty.hardline() + @pretty.hardline()
      })
    if port_docs[i] is Some(pd) {
      d = d + pd + @pretty.hardline()
    }
    d = d + self.declaration_doc(root.child("declarations", i), 0, decl)
  }
  d + @pretty.hardline()
}
