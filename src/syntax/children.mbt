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
/// The doc attributes of the declaration at `range`.
fn declaration_attributes(
  groups : ArrayView[@parser.AttributeGroup],
  range : @ast.Range,
) -> ArrayView[@parser.DocAttribute] {
  for g in groups {
    if g.target is Declaration(range=r, ..) && r == range {
      return g.attributes
    }
  }
  []
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
      [
        ("moduleDefinition", [Module(file.module_definition)]),
        ("imports", file.imports.map(i => Import(i))),
        (
          "declarations",
          file.declarations.map(d => {
            Declaration(d, declaration_attributes(groups, d.range))
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
/// The names of this node's fields, in elm-syntax JSON order.
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
/// All child nodes in source order (a new array).
pub fn NodeRef::children(self : NodeRef) -> Array[NodeRef] {
  let all = []
  for e in self.entries() {
    all.append(e.1)
  }
  // Array::sort_by is stable, so children with the same start keep their
  // field order.
  all.sort_by(start_before)
  all
}

///|
/// The field of this node that holds `child`, if any.
pub fn NodeRef::field_of(self : NodeRef, child : NodeRef) -> String? {
  for e in self.entries() {
    if e.1.any(c => same(c, child)) {
      return Some(e.0)
    }
  }
  None
}

///|
/// Every node type: (category, kind, fields), one row per kind. AGENTS.md
/// lists the same table.
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
