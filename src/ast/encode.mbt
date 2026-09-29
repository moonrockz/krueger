// JSON encoders mirroring the `encode` functions of stil4m/elm-syntax 7.3.9.
// Object keys are inserted in the same order as elm-syntax writes them, so
// `Json::stringify` of the result has the same key order as the Elm output.

///|
/// Elm.Json.Util.encodeTyped: `{"type": tag, tag: value}`.
fn encode_typed(tag : String, value : Json) -> Json {
  Json::object(Map([("type", Json::string(tag)), (tag, value)]))
}

///|
fn obj(fields : Array[(String, Json)]) -> Json {
  Json::object(Map(fields))
}

///|
fn encode_int(i : Int) -> Json {
  Json::number(i.to_double())
}

///|
fn encode_int64(i : Int64) -> Json {
  Json::number(i.to_double())
}

///|
fn encode_string(s : String) -> Json {
  Json::string(s)
}

///|
/// Elm `String.fromChar c`.
fn encode_char(c : Char) -> Json {
  Json::string(c.to_string())
}

///|
fn[T] encode_list(xs : Array[T], f : (T) -> Json) -> Json {
  Json::array(xs.map(f))
}

///|
/// `Maybe.map f m |> Maybe.withDefault JE.null`.
fn[T] encode_maybe(m : T?, f : (T) -> Json) -> Json {
  match m {
    Some(x) => f(x)
    None => Json::null()
  }
}

///|
/// Elm.Syntax.Range.encode: `[startRow, startColumn, endRow, endColumn]`.
pub fn encode_range(r : Range) -> Json {
  Json::array([
    encode_int(r.start.row),
    encode_int(r.start.column),
    encode_int(r.end.row),
    encode_int(r.end.column),
  ])
}

///|
/// Elm.Syntax.Node.encode: `{"range": ..., "value": ...}`.
pub fn[T] encode_node(n : Node[T], f : (T) -> Json) -> Json {
  obj([("range", encode_range(n.range)), ("value", f(n.value))])
}

///|
/// Elm.Syntax.ModuleName.encode.
pub fn encode_module_name(m : ModuleName) -> Json {
  encode_list(m, encode_string)
}

///|
/// Elm.Syntax.File.encode.
pub fn encode_file(file : File) -> Json {
  obj([
    ("moduleDefinition", encode_node(file.module_definition, encode_module)),
    ("imports", encode_list(file.imports, n => encode_node(n, encode_import))),
    (
      "declarations",
      encode_list(file.declarations, n => encode_node(n, encode_declaration)),
    ),
    ("comments", encode_list(file.comments, n => encode_node(n, encode_string))),
  ])
}

///|
/// Elm.Syntax.Module.encode.
pub fn encode_module(m : Module) -> Json {
  match m {
    NormalModule(d) => encode_typed("normal", encode_default_module_data(d))
    PortModule(d) => encode_typed("port", encode_default_module_data(d))
    EffectModule(d) => encode_typed("effect", encode_effect_module_data(d))
  }
}

///|
fn encode_default_module_data(d : DefaultModuleData) -> Json {
  obj([
    ("moduleName", encode_node(d.module_name, encode_module_name)),
    ("exposingList", encode_node(d.exposing_list, encode_exposing)),
  ])
}

///|
fn encode_effect_module_data(d : EffectModuleData) -> Json {
  obj([
    ("moduleName", encode_node(d.module_name, encode_module_name)),
    ("exposingList", encode_node(d.exposing_list, encode_exposing)),
    ("command", encode_maybe(d.command, n => encode_node(n, encode_string))),
    (
      "subscription",
      encode_maybe(d.subscription, n => encode_node(n, encode_string)),
    ),
  ])
}

///|
/// Elm.Syntax.Exposing.encode.
pub fn encode_exposing(e : Exposing) -> Json {
  match e {
    All(r) => encode_typed("all", encode_range(r))
    Explicit(l) =>
      encode_typed(
        "explicit",
        encode_list(l, n => encode_node(n, encode_top_level_expose)),
      )
  }
}

///|
/// Elm.Syntax.Exposing.encodeTopLevelExpose (without the Node wrapper).
pub fn encode_top_level_expose(t : TopLevelExpose) -> Json {
  match t {
    InfixExpose(x) => encode_typed("infix", obj([("name", encode_string(x))]))
    FunctionExpose(x) =>
      encode_typed("function", obj([("name", encode_string(x))]))
    TypeOrAliasExpose(x) =>
      encode_typed("typeOrAlias", obj([("name", encode_string(x))]))
    TypeExpose(t) => encode_typed("typeexpose", encode_exposed_type(t))
  }
}

///|
fn encode_exposed_type(t : ExposedType) -> Json {
  obj([
    ("name", encode_string(t.name)),
    ("open", encode_maybe(t.open, encode_range)),
  ])
}

///|
/// Elm.Syntax.Import.encode.
pub fn encode_import(i : Import) -> Json {
  obj([
    ("moduleName", encode_node(i.module_name, encode_module_name)),
    (
      "moduleAlias",
      encode_maybe(i.module_alias, n => encode_node(n, encode_module_name)),
    ),
    (
      "exposingList",
      encode_maybe(i.exposing_list, n => encode_node(n, encode_exposing)),
    ),
  ])
}

///|
/// Elm.Syntax.Declaration.encode.
pub fn encode_declaration(d : Declaration) -> Json {
  match d {
    FunctionDeclaration(f) => encode_typed("function", encode_function(f))
    AliasDeclaration(a) => encode_typed("typeAlias", encode_type_alias(a))
    CustomTypeDeclaration(t) => encode_typed("typedecl", encode_type(t))
    PortDeclaration(s) => encode_typed("port", encode_signature(s))
    InfixDeclaration(i) => encode_typed("infix", encode_infix(i))
    Destructuring(p, e) =>
      encode_typed(
        "destructuring",
        obj([
          ("pattern", encode_node(p, encode_pattern)),
          ("expression", encode_node(e, encode_expression)),
        ]),
      )
  }
}

///|
/// Elm.Syntax.Infix.encode.
pub fn encode_infix(i : Infix) -> Json {
  obj([
    ("direction", encode_node(i.direction, encode_infix_direction)),
    ("precedence", encode_node(i.precedence, encode_int)),
    ("operator", encode_node(i.operator, encode_string)),
    ("function", encode_node(i.function, encode_string)),
  ])
}

///|
/// Elm.Syntax.Infix.encodeDirection.
pub fn encode_infix_direction(d : InfixDirection) -> Json {
  match d {
    Left => Json::string("left")
    Right => Json::string("right")
    Non => Json::string("non")
  }
}

///|
/// Elm.Syntax.Signature.encode.
pub fn encode_signature(s : Signature) -> Json {
  obj([
    ("name", encode_node(s.name, encode_string)),
    ("typeAnnotation", encode_node(s.type_annotation, encode_type_annotation)),
  ])
}

///|
/// Elm.Syntax.TypeAlias.encode.
pub fn encode_type_alias(a : TypeAlias) -> Json {
  obj([
    (
      "documentation",
      encode_maybe(a.documentation, n => encode_node(n, encode_string)),
    ),
    ("name", encode_node(a.name, encode_string)),
    ("generics", encode_list(a.generics, n => encode_node(n, encode_string))),
    ("typeAnnotation", encode_node(a.type_annotation, encode_type_annotation)),
  ])
}

///|
/// Elm.Syntax.Type.encode.
pub fn encode_type(t : Type) -> Json {
  obj([
    (
      "documentation",
      encode_maybe(t.documentation, n => encode_node(n, encode_string)),
    ),
    ("name", encode_node(t.name, encode_string)),
    ("generics", encode_list(t.generics, n => encode_node(n, encode_string))),
    (
      "constructors",
      encode_list(t.constructors, n => encode_node(n, encode_value_constructor)),
    ),
  ])
}

///|
/// Elm.Syntax.Type.encodeValueConstructor.
pub fn encode_value_constructor(c : ValueConstructor) -> Json {
  obj([
    ("name", encode_node(c.name, encode_string)),
    (
      "arguments",
      encode_list(c.arguments, n => encode_node(n, encode_type_annotation)),
    ),
  ])
}

///|
/// Elm.Syntax.TypeAnnotation.encode.
pub fn encode_type_annotation(t : TypeAnnotation) -> Json {
  match t {
    GenericType(name) =>
      encode_typed("generic", obj([("value", encode_string(name))]))
    Typed(module_name_and_name, args) =>
      encode_typed(
        "typed",
        obj([
          (
            "moduleNameAndName",
            encode_node(module_name_and_name, mn => {
              obj([
                ("moduleName", encode_module_name(mn.0)),
                ("name", encode_string(mn.1)),
              ])
            }),
          ),
          (
            "args",
            encode_list(args, n => encode_node(n, encode_type_annotation)),
          ),
        ]),
      )
    Unit => encode_typed("unit", obj([]))
    Tupled(values) =>
      encode_typed(
        "tupled",
        obj([
          (
            "values",
            encode_list(values, n => encode_node(n, encode_type_annotation)),
          ),
        ]),
      )
    FunctionTypeAnnotation(left, right) =>
      encode_typed(
        "function",
        obj([
          ("left", encode_node(left, encode_type_annotation)),
          ("right", encode_node(right, encode_type_annotation)),
        ]),
      )
    Record(fields) =>
      encode_typed("record", obj([("value", encode_record_definition(fields))]))
    GenericRecord(name, fields) =>
      encode_typed(
        "genericRecord",
        obj([
          ("name", encode_node(name, encode_string)),
          ("values", encode_node(fields, encode_record_definition)),
        ]),
      )
  }
}

///|
fn encode_record_definition(fields : RecordDefinition) -> Json {
  encode_list(fields, n => encode_node(n, encode_record_field))
}

///|
fn encode_record_field(f : RecordField) -> Json {
  obj([
    ("name", encode_node(f.name, encode_string)),
    ("typeAnnotation", encode_node(f.type_annotation, encode_type_annotation)),
  ])
}

///|
/// Elm.Syntax.Pattern.encode.
pub fn encode_pattern(p : Pattern) -> Json {
  match p {
    AllPattern => encode_typed("all", obj([]))
    UnitPattern => encode_typed("unit", obj([]))
    CharPattern(c) => encode_typed("char", obj([("value", encode_char(c))]))
    StringPattern(s) =>
      encode_typed("string", obj([("value", encode_string(s))]))
    HexPattern(h) => encode_typed("hex", obj([("value", encode_int64(h))]))
    IntPattern(i) => encode_typed("int", obj([("value", encode_int64(i))]))
    FloatPattern(f) => encode_typed("float", obj([("value", Json::number(f))]))
    TuplePattern(ps) =>
      encode_typed(
        "tuple",
        obj([("value", encode_list(ps, n => encode_node(n, encode_pattern)))]),
      )
    RecordPattern(names) =>
      encode_typed(
        "record",
        obj([("value", encode_list(names, n => encode_node(n, encode_string)))]),
      )
    UnConsPattern(left, right) =>
      encode_typed(
        "uncons",
        obj([
          ("left", encode_node(left, encode_pattern)),
          ("right", encode_node(right, encode_pattern)),
        ]),
      )
    ListPattern(ps) =>
      encode_typed(
        "list",
        obj([("value", encode_list(ps, n => encode_node(n, encode_pattern)))]),
      )
    VarPattern(name) =>
      encode_typed("var", obj([("value", encode_string(name))]))
    NamedPattern(qualified, ps) =>
      encode_typed(
        "named",
        obj([
          (
            "qualified",
            obj([
              ("moduleName", encode_module_name(qualified.module_name)),
              ("name", encode_string(qualified.name)),
            ]),
          ),
          ("patterns", encode_list(ps, n => encode_node(n, encode_pattern))),
        ]),
      )
    AsPattern(destructured, name) =>
      encode_typed(
        "as",
        obj([
          ("name", encode_node(name, encode_string)),
          ("pattern", encode_node(destructured, encode_pattern)),
        ]),
      )
    // Tag spelling "parentisized" is elm-syntax's own (sic).
    ParenthesizedPattern(inner) =>
      encode_typed(
        "parentisized",
        obj([("value", encode_node(inner, encode_pattern))]),
      )
  }
}

///|
fn encode_nested(n : Node[Expression]) -> Json {
  encode_node(n, encode_expression)
}

///|
/// Elm.Syntax.Expression.encode.
pub fn encode_expression(e : Expression) -> Json {
  match e {
    UnitExpr => encode_typed("unit", Json::null())
    Application(l) => encode_typed("application", encode_list(l, encode_nested))
    OperatorApplication(op, dir, left, right) =>
      encode_typed(
        "operatorapplication",
        obj([
          ("operator", encode_string(op)),
          ("direction", encode_infix_direction(dir)),
          ("left", encode_nested(left)),
          ("right", encode_nested(right)),
        ]),
      )
    FunctionOrValue(module_name, name) =>
      encode_typed(
        "functionOrValue",
        obj([
          ("moduleName", encode_module_name(module_name)),
          ("name", encode_string(name)),
        ]),
      )
    IfBlock(c, t, e) =>
      encode_typed(
        "ifBlock",
        obj([
          ("clause", encode_nested(c)),
          ("then", encode_nested(t)),
          ("else", encode_nested(e)),
        ]),
      )
    PrefixOperator(x) => encode_typed("prefixoperator", encode_string(x))
    Operator(x) => encode_typed("operator", encode_string(x))
    Hex(h) => encode_typed("hex", encode_int64(h))
    Integer(x) => encode_typed("integer", encode_int64(x))
    Floatable(x) => encode_typed("float", Json::number(x))
    Negation(x) => encode_typed("negation", encode_nested(x))
    Literal(x) => encode_typed("literal", encode_string(x))
    CharLiteral(c) => encode_typed("charLiteral", encode_char(c))
    TupledExpression(xs) =>
      encode_typed("tupled", encode_list(xs, encode_nested))
    ListExpr(xs) => encode_typed("list", encode_list(xs, encode_nested))
    ParenthesizedExpression(x) =>
      encode_typed("parenthesized", encode_nested(x))
    LetExpression(x) => encode_typed("let", encode_let_block(x))
    CaseExpression(x) => encode_typed("case", encode_case_block(x))
    LambdaExpression(x) => encode_typed("lambda", encode_lambda(x))
    RecordAccess(exp, name) =>
      encode_typed(
        "recordAccess",
        obj([
          ("expression", encode_nested(exp)),
          ("name", encode_node(name, encode_string)),
        ]),
      )
    RecordAccessFunction(x) =>
      encode_typed("recordAccessFunction", encode_string(x))
    RecordExpr(xs) =>
      encode_typed(
        "record",
        encode_list(xs, n => encode_node(n, encode_record_setter)),
      )
    RecordUpdateExpression(name, updates) =>
      encode_typed(
        "recordUpdate",
        obj([
          ("name", encode_node(name, encode_string)),
          (
            "updates",
            encode_list(updates, n => encode_node(n, encode_record_setter)),
          ),
        ]),
      )
    GLSLExpression(x) => encode_typed("glsl", encode_string(x))
  }
}

///|
fn encode_let_block(b : LetBlock) -> Json {
  obj([
    (
      "declarations",
      encode_list(b.declarations, n => encode_node(n, encode_let_declaration)),
    ),
    ("expression", encode_nested(b.expression)),
  ])
}

///|
fn encode_record_setter(s : RecordSetter) -> Json {
  obj([
    ("field", encode_node(s.field, encode_string)),
    ("expression", encode_nested(s.expression)),
  ])
}

///|
fn encode_let_declaration(d : LetDeclaration) -> Json {
  match d {
    LetFunction(f) => encode_typed("function", encode_function(f))
    LetDestructuring(p, e) =>
      encode_typed(
        "destructuring",
        obj([
          ("pattern", encode_node(p, encode_pattern)),
          ("expression", encode_nested(e)),
        ]),
      )
  }
}

///|
/// Elm.Syntax.Expression.encodeFunction.
pub fn encode_function(f : Function) -> Json {
  obj([
    (
      "documentation",
      encode_maybe(f.documentation, n => encode_node(n, encode_string)),
    ),
    (
      "signature",
      encode_maybe(f.signature, n => encode_node(n, encode_signature)),
    ),
    ("declaration", encode_node(f.declaration, encode_function_implementation)),
  ])
}

///|
fn encode_function_implementation(f : FunctionImplementation) -> Json {
  obj([
    ("name", encode_node(f.name, encode_string)),
    ("arguments", encode_list(f.arguments, n => encode_node(n, encode_pattern))),
    ("expression", encode_nested(f.expression)),
  ])
}

///|
/// elm-syntax writes "cases" before "expression" here.
fn encode_case_block(b : CaseBlock) -> Json {
  obj([
    (
      "cases",
      encode_list(b.cases, c => {
        obj([
          ("pattern", encode_node(c.pattern, encode_pattern)),
          ("expression", encode_nested(c.expression)),
        ])
      }),
    ),
    ("expression", encode_nested(b.expression)),
  ])
}

///|
/// The Lambda field `args` is written under the key "patterns".
fn encode_lambda(l : Lambda) -> Json {
  obj([
    ("patterns", encode_list(l.args, n => encode_node(n, encode_pattern))),
    ("expression", encode_nested(l.expression)),
  ])
}
