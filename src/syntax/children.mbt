///|
fn names(xs : ArrayView[@ast.Node[String]]) -> Array[NodeRef] {
  xs.map(x => Name(x))
}

///|
fn expressions(xs : ArrayView[@ast.Node[@ast.Expression]]) -> Array[NodeRef] {
  xs.map(x => Expression(x))
}

///|
fn patterns(xs : ArrayView[@ast.Node[@ast.Pattern]]) -> Array[NodeRef] {
  xs.map(x => Pattern(x))
}

///|
fn types(xs : ArrayView[@ast.Node[@ast.TypeAnnotation]]) -> Array[NodeRef] {
  xs.map(x => TypeAnnotation(x))
}

///|
fn record_fields(xs : ArrayView[@ast.Node[@ast.RecordField]]) -> Array[NodeRef] {
  xs.map(x => RecordField(x))
}

///|
fn setters(xs : ArrayView[@ast.Node[@ast.RecordSetter]]) -> Array[NodeRef] {
  xs.map(x => RecordSetter(x))
}

///|
fn[T] optional(x : T?, f : (T) -> NodeRef) -> Array[NodeRef] {
  match x {
    Some(v) => [f(v)]
    None => []
  }
}

///|
fn function_entries(f : @ast.Function) -> Array[(String, Array[NodeRef])] {
  [
    ("documentation", optional(f.documentation, d => Documentation(d))),
    ("signature", optional(f.signature, s => Signature(s))),
    ("declaration", [Implementation(f.declaration)]),
  ]
}

///|
/// The key of a declaration range in `declaration_attributes`.
fn range_key(r : @ast.Range) -> (Int, Int, Int, Int) {
  (r.start.row, r.start.column, r.end.row, r.end.column)
}

///|
/// The doc attributes of each declaration, by range: the first group for a
/// range wins. One pass over the groups, so that the file's entries stay
/// linear in the number of declarations.
fn declaration_attributes(
  groups : ArrayView[@parser.AttributeGroup],
) -> Map[(Int, Int, Int, Int), ArrayView[@parser.DocAttribute]] {
  let by_range = Map([])
  for g in groups {
    if g.target is Declaration(range~, ..) {
      let key = range_key(range)
      if !by_range.contains(key) {
        by_range[key] = g.attributes
      }
    }
  }
  by_range
}

///|
/// The node's fields in elm-syntax JSON order, each with its child nodes.
fn NodeRef::entries(self : NodeRef) -> Array[(String, Array[NodeRef])] {
  match self {
    File(file, groups) => {
      let module_attributes = []
      for g in groups {
        if g.target is Module {
          module_attributes.append(g.attributes.map(a => Attribute(a)))
        }
      }
      let attributes = declaration_attributes(groups)
      [
        ("moduleDefinition", [Module(file.module_definition)]),
        ("imports", file.imports.map(i => Import(i))),
        (
          "declarations",
          file.declarations.map(d => {
            Declaration(d, attributes.get(range_key(d.range)).unwrap_or([]))
          }),
        ),
        ("comments", file.comments.map(c => Comment(c))),
        ("attributes", module_attributes),
      ]
    }
    Module(m) =>
      match m.value {
        NormalModule(d) | PortModule(d) =>
          [
            ("moduleName", [ModuleName(d.module_name)]),
            ("exposingList", [Exposing(d.exposing_list)]),
          ]
        EffectModule(d) =>
          [
            ("moduleName", [ModuleName(d.module_name)]),
            ("exposingList", [Exposing(d.exposing_list)]),
            ("command", optional(d.command, n => Name(n))),
            ("subscription", optional(d.subscription, n => Name(n))),
          ]
      }
    Exposing(x) =>
      match x.value {
        All(_) => []
        Explicit(items) => [("explicit", items.map(i => Expose(i)))]
      }
    Import(i) =>
      [
        ("moduleName", [ModuleName(i.value.module_name)]),
        ("moduleAlias", optional(i.value.module_alias, n => ModuleName(n))),
        ("exposingList", optional(i.value.exposing_list, e => Exposing(e))),
      ]
    Declaration(d, attributes) => {
      let attribute_nodes = attributes.map(a => Attribute(a))
      match d.value {
        FunctionDeclaration(f) =>
          [..function_entries(f), ("attributes", attribute_nodes)]
        AliasDeclaration(a) =>
          [
            ("documentation", optional(a.documentation, x => Documentation(x))),
            ("name", [Name(a.name)]),
            ("generics", names(a.generics)),
            ("typeAnnotation", [TypeAnnotation(a.type_annotation)]),
            ("attributes", attribute_nodes),
          ]
        CustomTypeDeclaration(t) =>
          [
            ("documentation", optional(t.documentation, x => Documentation(x))),
            ("name", [Name(t.name)]),
            ("generics", names(t.generics)),
            ("constructors", t.constructors.map(c => Constructor(c))),
            ("attributes", attribute_nodes),
          ]
        PortDeclaration(s) =>
          [
            ("name", [Name(s.name)]),
            ("typeAnnotation", [TypeAnnotation(s.type_annotation)]),
            ("attributes", attribute_nodes),
          ]
        InfixDeclaration(i) =>
          [("operator", [Name(i.operator)]), ("function", [Name(i.function)])]
        Destructuring(p, e) =>
          [("pattern", [Pattern(p)]), ("expression", [Expression(e)])]
      }
    }
    LetDeclaration(d) =>
      match d.value {
        LetFunction(f) => function_entries(f)
        LetDestructuring(p, e) =>
          [("pattern", [Pattern(p)]), ("expression", [Expression(e)])]
      }
    Signature(s) =>
      [
        ("name", [Name(s.value.name)]),
        ("typeAnnotation", [TypeAnnotation(s.value.type_annotation)]),
      ]
    Implementation(i) =>
      [
        ("name", [Name(i.value.name)]),
        ("arguments", patterns(i.value.arguments)),
        ("expression", [Expression(i.value.expression)]),
      ]
    Constructor(c) =>
      [("name", [Name(c.value.name)]), ("arguments", types(c.value.arguments))]
    Expression(x) => expression_entries(x.value)
    Case(c) =>
      [
        ("pattern", [Pattern(c.pattern)]),
        ("expression", [Expression(c.expression)]),
      ]
    RecordSetter(s) =>
      [
        ("field", [Name(s.value.field)]),
        ("expression", [Expression(s.value.expression)]),
      ]
    Pattern(x) => pattern_entries(x.value)
    TypeAnnotation(x) => type_entries(x.value)
    RecordField(f) =>
      [
        ("name", [Name(f.value.name)]),
        ("typeAnnotation", [TypeAnnotation(f.value.type_annotation)]),
      ]
    Attribute(Attribute(name~, arguments~, ..)) =>
      [("name", [Name(name)]), ("arguments", expressions(arguments))]
    Attribute(Docs(names=ns, ..)) => [("names", names(ns))]
    ModuleName(_) | Expose(_) | Documentation(_) | Name(_) | Comment(_) => []
  }
}

///|
fn expression_entries(e : @ast.Expression) -> Array[(String, Array[NodeRef])] {
  match e {
    Application(xs) => [("application", expressions(xs))]
    OperatorApplication(_, _, l, r) =>
      [("left", [Expression(l)]), ("right", [Expression(r)])]
    IfBlock(c, t, e) =>
      [
        ("clause", [Expression(c)]),
        ("then", [Expression(t)]),
        ("else", [Expression(e)]),
      ]
    Negation(x) => [("negation", [Expression(x)])]
    TupledExpression(xs) => [("tupled", expressions(xs))]
    ListExpr(xs) => [("list", expressions(xs))]
    ParenthesizedExpression(x) => [("parenthesized", [Expression(x)])]
    LetExpression(b) =>
      [
        ("declarations", b.declarations.map(d => LetDeclaration(d))),
        ("expression", [Expression(b.expression)]),
      ]
    CaseExpression(b) =>
      [
        ("cases", b.cases.map(c => Case(c))),
        ("expression", [Expression(b.expression)]),
      ]
    LambdaExpression(l) =>
      [
        ("patterns", patterns(l.args)),
        ("expression", [Expression(l.expression)]),
      ]
    RecordAccess(x, name) =>
      [("expression", [Expression(x)]), ("name", [Name(name)])]
    RecordExpr(xs) => [("record", setters(xs))]
    RecordUpdateExpression(name, xs) =>
      [("name", [Name(name)]), ("updates", setters(xs))]
    UnitExpr
    | FunctionOrValue(_, _)
    | PrefixOperator(_)
    | Operator(_)
    | Hex(_)
    | Integer(_)
    | Floatable(_)
    | Literal(_)
    | CharLiteral(_)
    | RecordAccessFunction(_)
    | GLSLExpression(_) => []
  }
}

///|
fn pattern_entries(p : @ast.Pattern) -> Array[(String, Array[NodeRef])] {
  match p {
    TuplePattern(xs) | ListPattern(xs) => [("value", patterns(xs))]
    RecordPattern(xs) => [("value", names(xs))]
    UnConsPattern(l, r) => [("left", [Pattern(l)]), ("right", [Pattern(r)])]
    NamedPattern(_, xs) => [("patterns", patterns(xs))]
    AsPattern(x, name) => [("name", [Name(name)]), ("pattern", [Pattern(x)])]
    ParenthesizedPattern(x) => [("value", [Pattern(x)])]
    AllPattern
    | UnitPattern
    | CharPattern(_)
    | StringPattern(_)
    | HexPattern(_)
    | IntPattern(_)
    | FloatPattern(_)
    | VarPattern(_) => []
  }
}

///|
fn type_entries(t : @ast.TypeAnnotation) -> Array[(String, Array[NodeRef])] {
  match t {
    Typed(_, args) => [("args", types(args))]
    Tupled(xs) => [("values", types(xs))]
    FunctionTypeAnnotation(l, r) =>
      [("left", [TypeAnnotation(l)]), ("right", [TypeAnnotation(r)])]
    Record(fields) => [("value", record_fields(fields))]
    GenericRecord(name, fields) =>
      [("name", [Name(name)]), ("values", record_fields(fields.value))]
    GenericType(_) | Unit => []
  }
}

///|
/// The names of this node's fields, in elm-syntax JSON order. A field is
/// listed also when it holds no node (a function with no signature has an
/// empty `signature` field).
///
/// ```mbt check
/// test {
///   let src = "module Main exposing (..)\n\nadd x y =\n    x + y\n"
///   let result = @parser.parse_module(
///     @scanner.SourceText::new(src),
///     @scanner.DefaultScanner::new(),
///   )
///   let root = @syntax.NodeRef::of_result(result).unwrap()
///   let decl = root.field("declarations")[0]
///   inspect(
///     decl.fields().join(" "),
///     content="documentation signature declaration attributes",
///   )
///   inspect(decl.field("signature").length(), content="0")
///   inspect(decl.field("no-such-field").length(), content="0")
///   let arguments = decl.field("declaration")[0].field("arguments")
///   debug_inspect(arguments.map(a => a.kind()), content="[\"var\", \"var\"]")
/// }
/// ```
pub fn NodeRef::fields(self : NodeRef) -> Array[String] {
  self.entries().map(e => e.0)
}

///|
/// The nodes in field `name` (a new array; empty for an absent or unknown
/// field).
pub fn NodeRef::field(self : NodeRef, name : String) -> Array[NodeRef] {
  for e in self.entries() {
    if e.0 == name {
      return e.1
    }
  }
  []
}

///|
fn start_before(a : NodeRef, b : NodeRef) -> Int {
  let x = a.range().start
  let y = b.range().start
  if x.row != y.row {
    x.row.compare(y.row)
  } else {
    x.column.compare(y.column)
  }
}

///|
/// `xs` in the start order of `node(x)`; among equal starts, in their order
/// in `xs`. Most nodes list their fields in source order, so `xs` comes back
/// as it is when it is in order already, and is sorted only otherwise.
fn[T] in_source_order(xs : Array[T], node : (T) -> NodeRef) -> Array[T] {
  let mut sorted = true
  for i in 1..<xs.length() {
    if start_before(node(xs[i - 1]), node(xs[i])) > 0 {
      sorted = false
      break
    }
  }
  if sorted {
    return xs
  }
  // Array::sort_by is not stable, so the original position breaks ties.
  let keyed = xs.mapi((i, x) => (i, x))
  keyed.sort_by((a, b) => {
    let c = start_before(node(a.1), node(b.1))
    if c != 0 {
      c
    } else {
      a.0.compare(b.0)
    }
  })
  keyed.map(x => x.1)
}

///|
/// All child nodes in source order (a new array), each with its step: its
/// field and its index in that field. Children that start at the same place
/// keep their field order. The nodes are the ones that `children` gives.
///
/// Use it to get the field of every child in one call. `field_of` looks
/// through all the fields on each call, so calling it for each child of a
/// wide node (a file with many declarations) is quadratic.
///
/// ```mbt check
/// test {
///   let src = "module Main exposing (..)\n\nadd x y =\n    x + y\n"
///   let result = @parser.parse_module(
///     @scanner.SourceText::new(src),
///     @scanner.DefaultScanner::new(),
///   )
///   let root = @syntax.NodeRef::of_result(result).unwrap()
///   let implementation = root.field("declarations")[0].field("declaration")[0]
///   let labels = implementation
///     .children_with_fields()
///     .map(x => "\{x.0.field}[\{x.0.index}]:\{x.1.kind()}")
///   inspect(
///     labels.join(" "),
///     content="name[0]:name arguments[0]:var arguments[1]:var expression[0]:operatorapplication",
///   )
/// }
/// ```
pub fn NodeRef::children_with_fields(
  self : NodeRef,
) -> Array[(PathStep, NodeRef)] {
  let all : Array[(PathStep, NodeRef)] = []
  for e in self.entries() {
    for i, c in e.1 {
      all.push(({ field: e.0, index: i, }, c))
    }
  }
  in_source_order(all, x => x.1)
}

///|
/// All child nodes in source order (a new array). Use `field_of` to get the
/// field of one child, and `children_with_fields` (or `Tree::field_of`) to
/// get the field of each child.
///
/// ```mbt check
/// test {
///   let src = "module Main exposing (..)\n\nadd x y =\n    x + y\n"
///   let result = @parser.parse_module(
///     @scanner.SourceText::new(src),
///     @scanner.DefaultScanner::new(),
///   )
///   let root = @syntax.NodeRef::of_result(result).unwrap()
///   let implementation = root.field("declarations")[0].field("declaration")[0]
///   let labels = implementation
///     .children()
///     .map(c => "\{implementation.field_of(c).unwrap()}:\{c.kind()}")
///   inspect(
///     labels.join(" "),
///     content="name:name arguments:var arguments:var expression:operatorapplication",
///   )
/// }
/// ```
pub fn NodeRef::children(self : NodeRef) -> Array[NodeRef] {
  let all = []
  for e in self.entries() {
    all.append(e.1)
  }
  in_source_order(all, x => x)
}

///|
/// The field of this node that holds `child`, or `None` when `child` is not a
/// child of this node. See `children` for an example.
///
/// It looks through all the fields on each call (linear in the number of
/// children). To get the field of every child, use `children_with_fields`,
/// or `Tree::field_of`, which reads the tree's index.
pub fn NodeRef::field_of(self : NodeRef, child : NodeRef) -> String? {
  for e in self.entries() {
    if e.1.any(c => same(c, child)) {
      return Some(e.0)
    }
  }
  None
}

///|
/// Every node type: (category, kind, fields), one row per kind. The kinds
/// and field names are the elm-syntax JSON vocabulary.
///
/// ```mbt check
/// test {
///   let rows = @syntax.kind_table()
///   let row = rows.filter(r => r.0 == "expression" && r.1 == "ifBlock")[0]
///   debug_inspect(row.2, content="[\"clause\", \"then\", \"else\"]")
///   // `list` is a kind of both expressions and patterns.
///   let lists = rows.filter(r => r.1 == "list").map(r => r.0)
///   debug_inspect(lists, content="[\"expression\", \"pattern\"]")
/// }
/// ```
pub fn kind_table() -> Array[(String, String, Array[String])] {
  let function_fields = ["documentation", "signature", "declaration"]
  let rows : Array[(String, String, Array[String])] = [
    (
      "file",
      "file",
      ["moduleDefinition", "imports", "declarations", "comments", "attributes"],
    ),
    ("module", "normal", ["moduleName", "exposingList"]),
    ("module", "port", ["moduleName", "exposingList"]),
    (
      "module",
      "effect",
      ["moduleName", "exposingList", "command", "subscription"],
    ),
    ("module_name", "module_name", []),
    ("exposing", "all", []),
    ("exposing", "explicit", ["explicit"]),
    ("expose", "infix", []),
    ("expose", "function", []),
    ("expose", "typeOrAlias", []),
    ("expose", "typeexpose", []),
    ("import", "import", ["moduleName", "moduleAlias", "exposingList"]),
    ("declaration", "function", [..function_fields, "attributes"]),
    (
      "declaration",
      "typeAlias",
      ["documentation", "name", "generics", "typeAnnotation", "attributes"],
    ),
    (
      "declaration",
      "typedecl",
      ["documentation", "name", "generics", "constructors", "attributes"],
    ),
    ("declaration", "port", ["name", "typeAnnotation", "attributes"]),
    ("declaration", "infix", ["operator", "function"]),
    ("declaration", "destructuring", ["pattern", "expression"]),
    ("documentation", "documentation", []),
    ("signature", "signature", ["name", "typeAnnotation"]),
    ("implementation", "implementation", ["name", "arguments", "expression"]),
    ("constructor", "constructor", ["name", "arguments"]),
    ("let_declaration", "function", function_fields),
    ("let_declaration", "destructuring", ["pattern", "expression"]),
    ("case_branch", "case_branch", ["pattern", "expression"]),
    ("record_setter", "record_setter", ["field", "expression"]),
    ("record_field", "record_field", ["name", "typeAnnotation"]),
    ("name", "name", []),
    ("comment", "comment", []),
    ("attribute", "attribute", ["name", "arguments"]),
    ("attribute", "docs", ["names"]),
    ("expression", "unit", []),
    ("expression", "application", ["application"]),
    ("expression", "operatorapplication", ["left", "right"]),
    ("expression", "functionOrValue", []),
    ("expression", "ifBlock", ["clause", "then", "else"]),
    ("expression", "prefixoperator", []),
    ("expression", "operator", []),
    ("expression", "hex", []),
    ("expression", "integer", []),
    ("expression", "float", []),
    ("expression", "negation", ["negation"]),
    ("expression", "literal", []),
    ("expression", "charLiteral", []),
    ("expression", "tupled", ["tupled"]),
    ("expression", "list", ["list"]),
    ("expression", "parenthesized", ["parenthesized"]),
    ("expression", "let", ["declarations", "expression"]),
    ("expression", "case", ["cases", "expression"]),
    ("expression", "lambda", ["patterns", "expression"]),
    ("expression", "recordAccess", ["expression", "name"]),
    ("expression", "recordAccessFunction", []),
    ("expression", "record", ["record"]),
    ("expression", "recordUpdate", ["name", "updates"]),
    ("expression", "glsl", []),
    ("pattern", "all", []),
    ("pattern", "unit", []),
    ("pattern", "char", []),
    ("pattern", "string", []),
    ("pattern", "hex", []),
    ("pattern", "int", []),
    ("pattern", "float", []),
    ("pattern", "tuple", ["value"]),
    ("pattern", "record", ["value"]),
    ("pattern", "uncons", ["left", "right"]),
    ("pattern", "list", ["value"]),
    ("pattern", "var", []),
    ("pattern", "named", ["patterns"]),
    ("pattern", "as", ["name", "pattern"]),
    ("pattern", "parentisized", ["value"]),
    ("type", "generic", []),
    ("type", "typed", ["args"]),
    ("type", "unit", []),
    ("type", "tupled", ["values"]),
    ("type", "function", ["left", "right"]),
    ("type", "record", ["value"]),
    ("type", "genericRecord", ["name", "values"]),
  ]
  rows
}
