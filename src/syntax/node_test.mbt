///|
fn parse_root(text : String) -> @syntax.NodeRef raise {
  let source = @scanner.SourceText::{ module_name: Some("M"), text, }
  guard @scanner.DefaultScanner::new().tokenize(source) is Ok(tokens) else {
    fail("scan error")
  }
  guard @syntax.NodeRef::of_result(@parser.parse_tokens(tokens)) is Some(root) else {
    fail("no AST")
  }
  root
}

///|
let r0 : @ast.Range = {
  start: { row: 1, column: 1, },
  end: { row: 1, column: 2, },
}

///|
fn[T] n(value : T) -> @ast.Node[T] {
  { range: r0, value, }
}

///|
fn e(value : @ast.Expression) -> @syntax.NodeRef {
  Expression(n(value))
}

///|
fn p(value : @ast.Pattern) -> @syntax.NodeRef {
  Pattern(n(value))
}

///|
fn t(value : @ast.TypeAnnotation) -> @syntax.NodeRef {
  TypeAnnotation(n(value))
}

///|
test "every kind has its category and elm-syntax tag" {
  let x : @ast.Node[@ast.Expression] = n(UnitExpr)
  let px : @ast.Node[@ast.Pattern] = n(AllPattern)
  let tx : @ast.Node[@ast.TypeAnnotation] = n(Unit)
  let name : @ast.Node[String] = n("a")
  let exposing : @ast.Exposing = All(r0)
  let module_data : @ast.DefaultModuleData = {
    module_name: n(["M"]),
    exposing_list: n(exposing),
  }
  let implementation : @ast.FunctionImplementation = {
    name,
    arguments: [],
    expression: x,
  }
  let function : @ast.Function = {
    documentation: None,
    signature: None,
    declaration: n(implementation),
  }
  let signature : @ast.Signature = { name, type_annotation: tx, }
  let cases : Array[(@syntax.NodeRef, String, String)] = [
    (Module(n(NormalModule(module_data))), "module", "normal"),
    (Module(n(PortModule(module_data))), "module", "port"),
    (
      Module(
        n(
          EffectModule({
            module_name: n(["M"]),
            exposing_list: n(exposing),
            command: None,
            subscription: None,
          }),
        ),
      ),
      "module",
      "effect",
    ),
    (ModuleName(n(["M"])), "module_name", "module_name"),
    (Exposing(n(exposing)), "exposing", "all"),
    (Exposing(n(Explicit([]))), "exposing", "explicit"),
    (Expose(n(InfixExpose("+"))), "expose", "infix"),
    (Expose(n(FunctionExpose("f"))), "expose", "function"),
    (Expose(n(TypeOrAliasExpose("T"))), "expose", "typeOrAlias"),
    (Expose(n(TypeExpose({ name: "T", open: None, }))), "expose", "typeexpose"),
    (
      Import(
        n({ module_name: n(["M"]), module_alias: None, exposing_list: None, }),
      ),
      "import",
      "import",
    ),
    (
      Declaration(n(FunctionDeclaration(function)), []),
      "declaration",
      "function",
    ),
    (
      Declaration(
        n(
          AliasDeclaration({
            documentation: None,
            name,
            generics: [],
            type_annotation: tx,
          }),
        ),
        [],
      ),
      "declaration",
      "typeAlias",
    ),
    (
      Declaration(
        n(
          CustomTypeDeclaration({
            documentation: None,
            name,
            generics: [],
            constructors: [],
          }),
        ),
        [],
      ),
      "declaration",
      "typedecl",
    ),
    (Declaration(n(PortDeclaration(signature)), []), "declaration", "port"),
    (
      Declaration(
        n(
          InfixDeclaration({
            direction: n(Left),
            precedence: n(6),
            operator: n("+"),
            function: name,
          }),
        ),
        [],
      ),
      "declaration",
      "infix",
    ),
    (Declaration(n(Destructuring(px, x)), []), "declaration", "destructuring"),
    (Documentation(n("{-| d -}")), "documentation", "documentation"),
    (Signature(n(signature)), "signature", "signature"),
    (Implementation(n(implementation)), "implementation", "implementation"),
    (Constructor(n({ name, arguments: [], })), "constructor", "constructor"),
    (LetDeclaration(n(LetFunction(function))), "let_declaration", "function"),
    (
      LetDeclaration(n(LetDestructuring(px, x))),
      "let_declaration",
      "destructuring",
    ),
    (Case({ pattern: px, expression: x, }), "case_branch", "case_branch"),
    (
      RecordSetter(n({ field: name, expression: x, })),
      "record_setter",
      "record_setter",
    ),
    (
      RecordField(n({ name, type_annotation: tx, })),
      "record_field",
      "record_field",
    ),
    (Name(name), "name", "name"),
    (Comment(n("-- c")), "comment", "comment"),
    (
      Attribute(Attribute(name~, arguments=[], range=r0)),
      "attribute",
      "attribute",
    ),
    (Attribute(Docs(names=[], range=r0)), "attribute", "docs"),
    (e(UnitExpr), "expression", "unit"),
    (e(Application([])), "expression", "application"),
    (
      e(OperatorApplication("+", Left, x, x)),
      "expression",
      "operatorapplication",
    ),
    (e(FunctionOrValue([], "f")), "expression", "functionOrValue"),
    (e(IfBlock(x, x, x)), "expression", "ifBlock"),
    (e(PrefixOperator("+")), "expression", "prefixoperator"),
    (e(Operator("+")), "expression", "operator"),
    (e(Hex(1L)), "expression", "hex"),
    (e(Integer(1L)), "expression", "integer"),
    (e(Floatable(1.5)), "expression", "float"),
    (e(Negation(x)), "expression", "negation"),
    (e(Literal("s")), "expression", "literal"),
    (e(CharLiteral('c')), "expression", "charLiteral"),
    (e(TupledExpression([])), "expression", "tupled"),
    (e(ListExpr([])), "expression", "list"),
    (e(ParenthesizedExpression(x)), "expression", "parenthesized"),
    (
      e(LetExpression({ declarations: [], expression: x, })),
      "expression",
      "let",
    ),
    (e(CaseExpression({ expression: x, cases: [], })), "expression", "case"),
    (e(LambdaExpression({ args: [], expression: x, })), "expression", "lambda"),
    (e(RecordAccess(x, name)), "expression", "recordAccess"),
    (e(RecordAccessFunction(".a")), "expression", "recordAccessFunction"),
    (e(RecordExpr([])), "expression", "record"),
    (e(RecordUpdateExpression(name, [])), "expression", "recordUpdate"),
    (e(GLSLExpression("")), "expression", "glsl"),
    (p(AllPattern), "pattern", "all"),
    (p(UnitPattern), "pattern", "unit"),
    (p(CharPattern('c')), "pattern", "char"),
    (p(StringPattern("s")), "pattern", "string"),
    (p(HexPattern(1L)), "pattern", "hex"),
    (p(IntPattern(1L)), "pattern", "int"),
    (p(FloatPattern(1.5)), "pattern", "float"),
    (p(TuplePattern([])), "pattern", "tuple"),
    (p(RecordPattern([])), "pattern", "record"),
    (p(UnConsPattern(px, px)), "pattern", "uncons"),
    (p(ListPattern([])), "pattern", "list"),
    (p(VarPattern("v")), "pattern", "var"),
    (
      p(NamedPattern({ module_name: [], name: "Just", }, [])),
      "pattern",
      "named",
    ),
    (p(AsPattern(px, name)), "pattern", "as"),
    (p(ParenthesizedPattern(px)), "pattern", "parentisized"),
    (t(GenericType("a")), "type", "generic"),
    (t(Typed(n(([], "Int")), [])), "type", "typed"),
    (t(Unit), "type", "unit"),
    (t(Tupled([])), "type", "tupled"),
    (t(FunctionTypeAnnotation(tx, tx)), "type", "function"),
    (t(Record([])), "type", "record"),
    (t(GenericRecord(name, n([]))), "type", "genericRecord"),
  ]
  for c in cases {
    let (node, category, kind) = c
    @expect.expect((node.category(), node.kind())).to_equal((category, kind))
  }
}

///|
test "the root is the file" {
  let root = parse_root("module M exposing (..)\n\n\nf =\n    1\n")
  @expect.expect((root.category(), root.kind())).to_equal(("file", "file"))
  @expect.expect(root.range()).to_equal({
    start: { row: 1, column: 1, },
    end: { row: 5, column: 6, },
  })
}

///|
test "a case branch spans its pattern and expression" {
  let branch : @syntax.NodeRef = Case({
    pattern: {
      range: { start: { row: 3, column: 9, }, end: { row: 3, column: 10, }, },
      value: AllPattern,
    },
    expression: {
      range: { start: { row: 4, column: 13, }, end: { row: 4, column: 14, }, },
      value: UnitExpr,
    },
  })
  @expect.expect(branch.range()).to_equal({
    start: { row: 3, column: 9, },
    end: { row: 4, column: 14, },
  })
}

///|
test "no AST, no root" {
  let source = @scanner.SourceText::{ module_name: Some("M"), text: "x = 1\n", }
  guard @scanner.DefaultScanner::new().tokenize(source) is Ok(tokens) else {
    fail("scan error")
  }
  @expect.expect(
    @syntax.NodeRef::of_result(@parser.parse_tokens(tokens)) is None,
  ).to_equal(true)
}
