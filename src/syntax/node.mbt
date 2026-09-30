///|
/// A read-only reference to one node of a parse result. Each case points into
/// the typed AST (nothing is copied). Generic code uses `category`, `kind`,
/// `range`, `children` and `field`; typed code matches the cases.
///
/// Kinds and field names follow the JSON that elm-syntax (and `@ast.encode_*`)
/// writes. elm-syntax reuses tags across node types (`record`, `list`, `unit`,
/// …), so `(category, kind)` identifies a node type.
pub(all) enum NodeRef {
  File(@ast.File, Array[@parser.AttributeGroup])
  Module(@ast.Node[@ast.Module])
  ModuleName(@ast.Node[Array[String]])
  Exposing(@ast.Node[@ast.Exposing])
  Expose(@ast.Node[@ast.TopLevelExpose])
  Import(@ast.Node[@ast.Import])
  Declaration(@ast.Node[@ast.Declaration], Array[@parser.DocAttribute])
  Documentation(@ast.Node[String])
  Signature(@ast.Node[@ast.Signature])
  Implementation(@ast.Node[@ast.FunctionImplementation])
  Constructor(@ast.Node[@ast.ValueConstructor])
  Expression(@ast.Node[@ast.Expression])
  LetDeclaration(@ast.Node[@ast.LetDeclaration])
  Case(@ast.Case)
  RecordSetter(@ast.Node[@ast.RecordSetter])
  Pattern(@ast.Node[@ast.Pattern])
  TypeAnnotation(@ast.Node[@ast.TypeAnnotation])
  RecordField(@ast.Node[@ast.RecordField])
  Name(@ast.Node[String])
  Comment(@ast.Node[String])
  Attribute(@parser.DocAttribute)
} derive(Eq, Debug)

///|
fn[T : Eq] same_value(x : T, y : T) -> Bool {
  physical_equal(x, y) || x == y
}

///|
/// `a == b`, but fast for nodes taken from the same tree: nodes wrap the AST
/// values themselves, so the same node is usually the same object and the
/// structural comparison of whole subtrees is not needed.
fn same(a : NodeRef, b : NodeRef) -> Bool {
  match (a, b) {
    (File(x, g), File(y, h)) => same_value(x, y) && same_value(g, h)
    (Module(x), Module(y)) => same_value(x, y)
    (ModuleName(x), ModuleName(y)) => same_value(x, y)
    (Exposing(x), Exposing(y)) => same_value(x, y)
    (Expose(x), Expose(y)) => same_value(x, y)
    (Import(x), Import(y)) => same_value(x, y)
    (Declaration(x, g), Declaration(y, h)) =>
      same_value(x, y) && same_value(g, h)
    (Documentation(x), Documentation(y)) => same_value(x, y)
    (Signature(x), Signature(y)) => same_value(x, y)
    (Implementation(x), Implementation(y)) => same_value(x, y)
    (Constructor(x), Constructor(y)) => same_value(x, y)
    (Expression(x), Expression(y)) => same_value(x, y)
    (LetDeclaration(x), LetDeclaration(y)) => same_value(x, y)
    (Case(x), Case(y)) => same_value(x, y)
    (RecordSetter(x), RecordSetter(y)) => same_value(x, y)
    (Pattern(x), Pattern(y)) => same_value(x, y)
    (TypeAnnotation(x), TypeAnnotation(y)) => same_value(x, y)
    (RecordField(x), RecordField(y)) => same_value(x, y)
    (Name(x), Name(y)) => same_value(x, y)
    (Comment(x), Comment(y)) => same_value(x, y)
    (Attribute(x), Attribute(y)) => same_value(x, y)
    _ => false
  }
}

///|
/// The root node of `result`: its file with the doc attributes, or `None`
/// when the parse produced no AST.
///
/// The attribute groups are copied; the AST is shared with `result`, so
/// neither may be changed while nodes are in use.
pub fn NodeRef::of_result(result : @parser.ParseResult) -> NodeRef? {
  result.ast.map(file => File(file, result.attributes.copy()))
}

///|
/// The node type: `"expression"`, `"pattern"`, `"type"`, `"declaration"`, …
pub fn NodeRef::category(self : NodeRef) -> String {
  match self {
    File(_, _) => "file"
    Module(_) => "module"
    ModuleName(_) => "module_name"
    Exposing(_) => "exposing"
    Expose(_) => "expose"
    Import(_) => "import"
    Declaration(_, _) => "declaration"
    Documentation(_) => "documentation"
    Signature(_) => "signature"
    Implementation(_) => "implementation"
    Constructor(_) => "constructor"
    Expression(_) => "expression"
    LetDeclaration(_) => "let_declaration"
    Case(_) => "case_branch"
    RecordSetter(_) => "record_setter"
    Pattern(_) => "pattern"
    TypeAnnotation(_) => "type"
    RecordField(_) => "record_field"
    Name(_) => "name"
    Comment(_) => "comment"
    Attribute(_) => "attribute"
  }
}

///|
/// The elm-syntax JSON tag of the node, or its category when elm-syntax has no
/// tag for it.
pub fn NodeRef::kind(self : NodeRef) -> String {
  match self {
    Module(m) =>
      match m.value {
        NormalModule(_) => "normal"
        PortModule(_) => "port"
        EffectModule(_) => "effect"
      }
    Exposing(x) =>
      match x.value {
        All(_) => "all"
        Explicit(_) => "explicit"
      }
    Expose(x) =>
      match x.value {
        InfixExpose(_) => "infix"
        FunctionExpose(_) => "function"
        TypeOrAliasExpose(_) => "typeOrAlias"
        TypeExpose(_) => "typeexpose"
      }
    Declaration(d, _) =>
      match d.value {
        FunctionDeclaration(_) => "function"
        AliasDeclaration(_) => "typeAlias"
        CustomTypeDeclaration(_) => "typedecl"
        PortDeclaration(_) => "port"
        InfixDeclaration(_) => "infix"
        Destructuring(_, _) => "destructuring"
      }
    LetDeclaration(d) =>
      match d.value {
        LetFunction(_) => "function"
        LetDestructuring(_, _) => "destructuring"
      }
    Expression(x) => expression_kind(x.value)
    Pattern(x) => pattern_kind(x.value)
    TypeAnnotation(x) => type_kind(x.value)
    Attribute(Attribute(..)) => "attribute"
    Attribute(Docs(..)) => "docs"
    other => other.category()
  }
}

///|
fn expression_kind(e : @ast.Expression) -> String {
  match e {
    UnitExpr => "unit"
    Application(_) => "application"
    OperatorApplication(_, _, _, _) => "operatorapplication"
    FunctionOrValue(_, _) => "functionOrValue"
    IfBlock(_, _, _) => "ifBlock"
    PrefixOperator(_) => "prefixoperator"
    Operator(_) => "operator"
    Hex(_) => "hex"
    Integer(_) => "integer"
    Floatable(_) => "float"
    Negation(_) => "negation"
    Literal(_) => "literal"
    CharLiteral(_) => "charLiteral"
    TupledExpression(_) => "tupled"
    ListExpr(_) => "list"
    ParenthesizedExpression(_) => "parenthesized"
    LetExpression(_) => "let"
    CaseExpression(_) => "case"
    LambdaExpression(_) => "lambda"
    RecordAccess(_, _) => "recordAccess"
    RecordAccessFunction(_) => "recordAccessFunction"
    RecordExpr(_) => "record"
    RecordUpdateExpression(_, _) => "recordUpdate"
    GLSLExpression(_) => "glsl"
  }
}

///|
fn pattern_kind(p : @ast.Pattern) -> String {
  match p {
    AllPattern => "all"
    UnitPattern => "unit"
    CharPattern(_) => "char"
    StringPattern(_) => "string"
    HexPattern(_) => "hex"
    IntPattern(_) => "int"
    FloatPattern(_) => "float"
    TuplePattern(_) => "tuple"
    RecordPattern(_) => "record"
    UnConsPattern(_, _) => "uncons"
    ListPattern(_) => "list"
    VarPattern(_) => "var"
    NamedPattern(_, _) => "named"
    AsPattern(_, _) => "as"
    // elm-syntax's own spelling.
    ParenthesizedPattern(_) => "parentisized"
  }
}

///|
fn type_kind(t : @ast.TypeAnnotation) -> String {
  match t {
    GenericType(_) => "generic"
    Typed(_, _) => "typed"
    Unit => "unit"
    Tupled(_) => "tupled"
    FunctionTypeAnnotation(_, _) => "function"
    Record(_) => "record"
    GenericRecord(_, _) => "genericRecord"
  }
}

///|
fn later(a : @ast.Location, b : @ast.Location) -> @ast.Location {
  if a.row > b.row || (a.row == b.row && a.column > b.column) {
    a
  } else {
    b
  }
}

///|
fn earlier(a : @ast.Location, b : @ast.Location) -> @ast.Location {
  if later(a, b) == a {
    b
  } else {
    a
  }
}

///|
/// The node's range. A case branch runs from its pattern to its expression;
/// the file from line 1, column 1 to the end of its last node. A declaration
/// with doc attributes starts no later than its first attribute (a port's doc
/// comment is not part of its elm-syntax range).
pub fn NodeRef::range(self : NodeRef) -> @ast.Range {
  match self {
    File(file, _) => {
      let mut end = file.module_definition.range.end
      for i in file.imports {
        end = later(end, i.range.end)
      }
      for d in file.declarations {
        end = later(end, d.range.end)
      }
      for c in file.comments {
        end = later(end, c.range.end)
      }
      { start: { row: 1, column: 1, }, end, }
    }
    Module(x) => x.range
    ModuleName(x) => x.range
    Exposing(x) => x.range
    Expose(x) => x.range
    Import(x) => x.range
    Declaration(x, attributes) => {
      let mut start = x.range.start
      for a in attributes {
        start = earlier(start, Attribute(a).range().start)
      }
      { start, end: x.range.end, }
    }
    Documentation(x) => x.range
    Signature(x) => x.range
    Implementation(x) => x.range
    Constructor(x) => x.range
    Expression(x) => x.range
    LetDeclaration(x) => x.range
    Case(c) => { start: c.pattern.range.start, end: c.expression.range.end, }
    RecordSetter(x) => x.range
    Pattern(x) => x.range
    TypeAnnotation(x) => x.range
    RecordField(x) => x.range
    Name(x) => x.range
    Comment(x) => x.range
    Attribute(Attribute(range~, ..)) => range
    Attribute(Docs(range~, ..)) => range
  }
}
