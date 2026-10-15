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
fn encode_int(i : Int32) -> Json {
  Json::number(i.to_double())
}

///|
fn encode_int64(i : Int64, exact_ints~ : Bool) -> Json {
  if exact_ints {
    Json::number(i.to_double(), repr=i.to_string())
  } else {
    Json::number(i.to_double())
  }
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
fn[T] encode_list(xs : ArrayView[T], f : (T) -> Json) -> Json {
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
/// A place in a JSON object that a nested node fills later. `Map` in `Json`
/// is mutable and keeps its insertion order, so the slot is filled in place
/// and the key order stays elm-syntax's.
priv enum Slot {
  Key(Map[String, Json], String)
}

///|
fn Slot::fill(self : Slot, value : Json) -> Unit {
  match self {
    Key(m, key) => m[key] = value
  }
}

///|
/// A nested node whose JSON is still to be written into its slot.
priv enum Pending {
  E(Slot, Expression)
  P(Slot, Pattern)
  T(Slot, TypeAnnotation)
  F(Slot, Function)
}

///|
/// The encoder state. The encoder does not recurse per AST level: each
/// encoder writes its own object with `null` in the slot of every nested
/// expression, pattern, type or function and queues the node; `run` pops
/// the queue until it is empty. Deep trees (long chains, many nested
/// parentheses) encode on every target without a stack limit.
priv struct Enc {
  exact_ints : Bool
  pending : Array[Pending]
}

///|
fn Enc::new(exact_ints : Bool) -> Enc {
  { exact_ints, pending: [], }
}

///|
/// Encode every pending node (and the nodes they queue) into its slot.
fn Enc::run(self : Enc) -> Unit {
  while self.pending.pop() is Some(item) {
    match item {
      E(slot, e) => slot.fill(self.expression(e))
      P(slot, p) => slot.fill(self.pattern(p))
      T(slot, t) => slot.fill(self.type_annotation(t))
      F(slot, f) => slot.fill(self.function(f))
    }
  }
}

///|
/// `encode_node` for a nested expression: the node's object, with its
/// `value` queued.
fn Enc::expr_node(self : Enc, node : Node[Expression]) -> Json {
  let m : Map[String, Json] = Map([
    ("range", encode_range(node.range)),
    ("value", Json::null()),
  ])
  self.pending.push(E(Key(m, "value"), node.value))
  Json::object(m)
}

///|
fn Enc::pattern_node(self : Enc, node : Node[Pattern]) -> Json {
  let m : Map[String, Json] = Map([
    ("range", encode_range(node.range)),
    ("value", Json::null()),
  ])
  self.pending.push(P(Key(m, "value"), node.value))
  Json::object(m)
}

///|
fn Enc::type_node(self : Enc, node : Node[TypeAnnotation]) -> Json {
  let m : Map[String, Json] = Map([
    ("range", encode_range(node.range)),
    ("value", Json::null()),
  ])
  self.pending.push(T(Key(m, "value"), node.value))
  Json::object(m)
}

///|
fn Enc::expr_list(self : Enc, xs : ArrayView[Node[Expression]]) -> Json {
  let arr : Array[Json] = Array::make(xs.length(), Json::null())
  for i, x in xs {
    arr[i] = self.expr_node(x)
  }
  Json::array(arr)
}

///|
fn Enc::pattern_list(self : Enc, xs : ArrayView[Node[Pattern]]) -> Json {
  let arr : Array[Json] = Array::make(xs.length(), Json::null())
  for i, x in xs {
    arr[i] = self.pattern_node(x)
  }
  Json::array(arr)
}

///|
fn Enc::type_list(self : Enc, xs : ArrayView[Node[TypeAnnotation]]) -> Json {
  let arr : Array[Json] = Array::make(xs.length(), Json::null())
  for i, x in xs {
    arr[i] = self.type_node(x)
  }
  Json::array(arr)
}

///|
/// Elm.Syntax.ModuleName.encode.
pub fn encode_module_name(m : ModuleName) -> Json {
  encode_list(m, encode_string)
}

///|
/// Elm.Syntax.File.encode.
/// With `exact_ints`, Int literals are written with their exact digits
/// (elm-syntax writes the nearest Double, which differs above 2^53).
/// With `exact_ints=false` the result is the same as `encode_file`.
///
/// ```mbt check
/// test {
///   let source = @scanner.SourceText::new(
///     "module Main exposing (..)\n\nbig =\n    9007199254740993\n",
///   )
///   let result = @parser.parse_module(source, @scanner.DefaultScanner::new())
///   guard result.ast is Some(file) else { fail("no AST") }
///   // elm-syntax writes the nearest Double.
///   let nearest = @ast.encode_file(file).stringify()
///   inspect(nearest.contains("9007199254740992"), content="true")
///   // exact_ints keeps the digits of the literal.
///   let exact = @ast.encode_file_with(file, exact_ints=true).stringify()
///   inspect(exact.contains("9007199254740993"), content="true")
///   // The decoder reads both forms; the exact form gives the literal back.
///   inspect(@ast.decode_file(@json.parse(exact)) == file, content="true")
/// }
/// ```
pub fn encode_file_with(file : File, exact_ints~ : Bool) -> Json {
  let enc = Enc::new(exact_ints)
  let json = obj([
    ("moduleDefinition", encode_node(file.module_definition, encode_module)),
    ("imports", encode_list(file.imports, n => encode_node(n, encode_import))),
    (
      "declarations",
      encode_list(file.declarations, n => {
        encode_node(n, v => enc.declaration(v))
      }),
    ),
    ("comments", encode_list(file.comments, n => encode_node(n, encode_string))),
  ])
  enc.run()
  json
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
/// With `exact_ints`, Int literals are written with their exact digits
/// (elm-syntax writes the nearest Double, which differs above 2^53).
pub fn encode_declaration_with(d : Declaration, exact_ints~ : Bool) -> Json {
  let enc = Enc::new(exact_ints)
  let json = enc.declaration(d)
  enc.run()
  json
}

///|
fn Enc::declaration(self : Enc, d : Declaration) -> Json {
  match d {
    FunctionDeclaration(f) => {
      let m : Map[String, Json] = Map([
        ("type", Json::string("function")),
        ("function", Json::null()),
      ])
      self.pending.push(F(Key(m, "function"), f))
      Json::object(m)
    }
    AliasDeclaration(a) => encode_typed("typeAlias", self.type_alias(a))
    CustomTypeDeclaration(t) => encode_typed("typedecl", self.custom_type(t))
    PortDeclaration(s) => encode_typed("port", self.signature(s))
    InfixDeclaration(i) => encode_typed("infix", encode_infix(i))
    Destructuring(p, e) =>
      encode_typed(
        "destructuring",
        obj([
          ("pattern", self.pattern_node(p)),
          ("expression", self.expr_node(e)),
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
  let enc = Enc::new(false)
  let json = enc.signature(s)
  enc.run()
  json
}

///|
fn Enc::signature(self : Enc, s : Signature) -> Json {
  obj([
    ("name", encode_node(s.name, encode_string)),
    ("typeAnnotation", self.type_node(s.type_annotation)),
  ])
}

///|
/// Elm.Syntax.TypeAlias.encode.
pub fn encode_type_alias(a : TypeAlias) -> Json {
  let enc = Enc::new(false)
  let json = enc.type_alias(a)
  enc.run()
  json
}

///|
fn Enc::type_alias(self : Enc, a : TypeAlias) -> Json {
  obj([
    (
      "documentation",
      encode_maybe(a.documentation, n => encode_node(n, encode_string)),
    ),
    ("name", encode_node(a.name, encode_string)),
    ("generics", encode_list(a.generics, n => encode_node(n, encode_string))),
    ("typeAnnotation", self.type_node(a.type_annotation)),
  ])
}

///|
/// Elm.Syntax.Type.encode.
pub fn encode_type(t : Type) -> Json {
  let enc = Enc::new(false)
  let json = enc.custom_type(t)
  enc.run()
  json
}

///|
fn Enc::custom_type(self : Enc, t : Type) -> Json {
  obj([
    (
      "documentation",
      encode_maybe(t.documentation, n => encode_node(n, encode_string)),
    ),
    ("name", encode_node(t.name, encode_string)),
    ("generics", encode_list(t.generics, n => encode_node(n, encode_string))),
    (
      "constructors",
      encode_list(t.constructors, n => {
        encode_node(n, v => self.value_constructor(v))
      }),
    ),
  ])
}

///|
/// Elm.Syntax.Type.encodeValueConstructor.
pub fn encode_value_constructor(c : ValueConstructor) -> Json {
  let enc = Enc::new(false)
  let json = enc.value_constructor(c)
  enc.run()
  json
}

///|
fn Enc::value_constructor(self : Enc, c : ValueConstructor) -> Json {
  obj([
    ("name", encode_node(c.name, encode_string)),
    ("arguments", self.type_list(c.arguments)),
  ])
}

///|
/// Elm.Syntax.TypeAnnotation.encode.
pub fn encode_type_annotation(t : TypeAnnotation) -> Json {
  let enc = Enc::new(false)
  let json = enc.type_annotation(t)
  enc.run()
  json
}

///|
/// The type's own object; its nested types are queued.
fn Enc::type_annotation(self : Enc, t : TypeAnnotation) -> Json {
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
          ("args", self.type_list(args)),
        ]),
      )
    Unit => encode_typed("unit", obj([]))
    Tupled(values) =>
      encode_typed("tupled", obj([("values", self.type_list(values))]))
    FunctionTypeAnnotation(left, right) =>
      encode_typed(
        "function",
        obj([("left", self.type_node(left)), ("right", self.type_node(right))]),
      )
    Record(fields) =>
      encode_typed("record", obj([("value", self.record_definition(fields))]))
    GenericRecord(name, fields) =>
      encode_typed(
        "genericRecord",
        obj([
          ("name", encode_node(name, encode_string)),
          ("values", encode_node(fields, v => self.record_definition(v))),
        ]),
      )
  }
}

///|
fn Enc::record_definition(self : Enc, fields : RecordDefinition) -> Json {
  encode_list(fields, n => encode_node(n, v => self.record_field(v)))
}

///|
fn Enc::record_field(self : Enc, f : RecordField) -> Json {
  obj([
    ("name", encode_node(f.name, encode_string)),
    ("typeAnnotation", self.type_node(f.type_annotation)),
  ])
}

///|
/// Elm.Syntax.Pattern.encode.
/// With `exact_ints`, Int literals are written with their exact digits
/// (elm-syntax writes the nearest Double, which differs above 2^53).
pub fn encode_pattern_with(p : Pattern, exact_ints~ : Bool) -> Json {
  let enc = Enc::new(exact_ints)
  let json = enc.pattern(p)
  enc.run()
  json
}

///|
/// The pattern's own object; its nested patterns are queued.
fn Enc::pattern(self : Enc, p : Pattern) -> Json {
  let exact_ints = self.exact_ints
  match p {
    AllPattern => encode_typed("all", obj([]))
    UnitPattern => encode_typed("unit", obj([]))
    CharPattern(c) => encode_typed("char", obj([("value", encode_char(c))]))
    StringPattern(s) =>
      encode_typed("string", obj([("value", encode_string(s))]))
    HexPattern(h) =>
      encode_typed("hex", obj([("value", encode_int64(h, exact_ints~))]))
    IntPattern(i) =>
      encode_typed("int", obj([("value", encode_int64(i, exact_ints~))]))
    FloatPattern(f) => encode_typed("float", obj([("value", Json::number(f))]))
    TuplePattern(ps) =>
      encode_typed("tuple", obj([("value", self.pattern_list(ps))]))
    RecordPattern(names) =>
      encode_typed(
        "record",
        obj([("value", encode_list(names, n => encode_node(n, encode_string)))]),
      )
    UnConsPattern(left, right) =>
      encode_typed(
        "uncons",
        obj([
          ("left", self.pattern_node(left)),
          ("right", self.pattern_node(right)),
        ]),
      )
    ListPattern(ps) =>
      encode_typed("list", obj([("value", self.pattern_list(ps))]))
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
          ("patterns", self.pattern_list(ps)),
        ]),
      )
    AsPattern(destructured, name) =>
      encode_typed(
        "as",
        obj([
          ("name", encode_node(name, encode_string)),
          ("pattern", self.pattern_node(destructured)),
        ]),
      )
    // Tag spelling "parentisized" is elm-syntax's own (sic).
    ParenthesizedPattern(inner) =>
      encode_typed("parentisized", obj([("value", self.pattern_node(inner))]))
  }
}

///|
/// Elm.Syntax.Expression.encode.
/// With `exact_ints`, Int literals are written with their exact digits
/// (elm-syntax writes the nearest Double, which differs above 2^53).
pub fn encode_expression_with(e : Expression, exact_ints~ : Bool) -> Json {
  let enc = Enc::new(exact_ints)
  let json = enc.expression(e)
  enc.run()
  json
}

///|
/// The expression's own object; its nested nodes are queued.
fn Enc::expression(self : Enc, e : Expression) -> Json {
  let exact_ints = self.exact_ints
  match e {
    UnitExpr => encode_typed("unit", Json::null())
    Application(l) => encode_typed("application", self.expr_list(l))
    OperatorApplication(op, dir, left, right) =>
      encode_typed(
        "operatorapplication",
        obj([
          ("operator", encode_string(op)),
          ("direction", encode_infix_direction(dir)),
          ("left", self.expr_node(left)),
          ("right", self.expr_node(right)),
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
          ("clause", self.expr_node(c)),
          ("then", self.expr_node(t)),
          ("else", self.expr_node(e)),
        ]),
      )
    PrefixOperator(x) => encode_typed("prefixoperator", encode_string(x))
    Operator(x) => encode_typed("operator", encode_string(x))
    Hex(h) => encode_typed("hex", encode_int64(h, exact_ints~))
    Integer(x) => encode_typed("integer", encode_int64(x, exact_ints~))
    // JSON has no infinity or NaN; elm-syntax writes null.
    Floatable(x) =>
      encode_typed(
        "float",
        if x.is_inf() || x.is_nan() {
          Json::null()
        } else {
          Json::number(x)
        },
      )
    Negation(x) => encode_typed("negation", self.expr_node(x))
    Literal(x) => encode_typed("literal", encode_string(x))
    CharLiteral(c) => encode_typed("charLiteral", encode_char(c))
    TupledExpression(xs) => encode_typed("tupled", self.expr_list(xs))
    ListExpr(xs) => encode_typed("list", self.expr_list(xs))
    ParenthesizedExpression(x) =>
      encode_typed("parenthesized", self.expr_node(x))
    LetExpression(x) => encode_typed("let", self.let_block(x))
    CaseExpression(x) => encode_typed("case", self.case_block(x))
    LambdaExpression(x) => encode_typed("lambda", self.lambda(x))
    RecordAccess(exp, name) =>
      encode_typed(
        "recordAccess",
        obj([
          ("expression", self.expr_node(exp)),
          ("name", encode_node(name, encode_string)),
        ]),
      )
    RecordAccessFunction(x) =>
      encode_typed("recordAccessFunction", encode_string(x))
    RecordExpr(xs) =>
      encode_typed(
        "record",
        encode_list(xs, n => encode_node(n, v => self.record_setter(v))),
      )
    RecordUpdateExpression(name, updates) =>
      encode_typed(
        "recordUpdate",
        obj([
          ("name", encode_node(name, encode_string)),
          (
            "updates",
            encode_list(updates, n => encode_node(n, v => self.record_setter(v))),
          ),
        ]),
      )
    GLSLExpression(x) => encode_typed("glsl", encode_string(x))
  }
}

///|
fn Enc::let_block(self : Enc, b : LetBlock) -> Json {
  obj([
    (
      "declarations",
      encode_list(b.declarations, n => {
        encode_node(n, v => self.let_declaration(v))
      }),
    ),
    ("expression", self.expr_node(b.expression)),
  ])
}

///|
fn Enc::record_setter(self : Enc, s : RecordSetter) -> Json {
  obj([
    ("field", encode_node(s.field, encode_string)),
    ("expression", self.expr_node(s.expression)),
  ])
}

///|
fn Enc::let_declaration(self : Enc, d : LetDeclaration) -> Json {
  match d {
    LetFunction(f) => {
      let m : Map[String, Json] = Map([
        ("type", Json::string("function")),
        ("function", Json::null()),
      ])
      self.pending.push(F(Key(m, "function"), f))
      Json::object(m)
    }
    LetDestructuring(p, e) =>
      encode_typed(
        "destructuring",
        obj([
          ("pattern", self.pattern_node(p)),
          ("expression", self.expr_node(e)),
        ]),
      )
  }
}

///|
/// Elm.Syntax.Expression.encodeFunction.
/// With `exact_ints`, Int literals are written with their exact digits
/// (elm-syntax writes the nearest Double, which differs above 2^53).
pub fn encode_function_with(f : Function, exact_ints~ : Bool) -> Json {
  let enc = Enc::new(exact_ints)
  let json = enc.function(f)
  enc.run()
  json
}

///|
fn Enc::function(self : Enc, f : Function) -> Json {
  obj([
    (
      "documentation",
      encode_maybe(f.documentation, n => encode_node(n, encode_string)),
    ),
    (
      "signature",
      encode_maybe(f.signature, n => encode_node(n, v => self.signature(v))),
    ),
    (
      "declaration",
      encode_node(f.declaration, v => self.function_implementation(v)),
    ),
  ])
}

///|
fn Enc::function_implementation(self : Enc, f : FunctionImplementation) -> Json {
  obj([
    ("name", encode_node(f.name, encode_string)),
    ("arguments", self.pattern_list(f.arguments)),
    ("expression", self.expr_node(f.expression)),
  ])
}

///|
/// elm-syntax writes "cases" before "expression" here.
fn Enc::case_block(self : Enc, b : CaseBlock) -> Json {
  obj([
    (
      "cases",
      encode_list(b.cases, c => {
        obj([
          ("pattern", self.pattern_node(c.pattern)),
          ("expression", self.expr_node(c.expression)),
        ])
      }),
    ),
    ("expression", self.expr_node(b.expression)),
  ])
}

///|
/// The Lambda field `args` is written under the key "patterns".
fn Enc::lambda(self : Enc, l : Lambda) -> Json {
  obj([
    ("patterns", self.pattern_list(l.args)),
    ("expression", self.expr_node(l.expression)),
  ])
}

///|
/// Elm.Syntax.File.encode.
///
/// The JSON is the JSON that elm-syntax 7.3.9 writes for the same file, with
/// the object keys in elm-syntax's order. The parity check compares the two
/// on a corpus of real packages. An Int literal
/// above 2^53 becomes the nearest Double, as in elm-syntax; use
/// `encode_file_with(file, exact_ints=true)` to keep its digits.
///
/// ```mbt check
/// test {
///   let source = @scanner.SourceText::new("module Main exposing (x)\n\nx = 1\n")
///   let result = @parser.parse_module(source, @scanner.DefaultScanner::new())
///   guard result.ast is Some(file) else { fail("no AST") }
///   let json = @ast.encode_file(file)
///   guard json is { "declarations": [declaration], .. } else {
///     fail("unexpected shape")
///   }
///   inspect(
///     declaration.stringify(),
///     content=(
///       #|{"range":[3,1,3,6],"value":{"type":"function","function":{"documentation":null,"signature":null,"declaration":{"range":[3,1,3,6],"value":{"name":{"range":[3,1,3,2],"value":"x"},"arguments":[],"expression":{"range":[3,5,3,6],"value":{"type":"integer","integer":1}}}}}}}
///     ),
///   )
/// }
/// ```
pub fn encode_file(file : File) -> Json {
  encode_file_with(file, exact_ints=false)
}

///|
/// Elm.Syntax.Declaration.encode.
pub fn encode_declaration(d : Declaration) -> Json {
  encode_declaration_with(d, exact_ints=false)
}

///|
/// Elm.Syntax.Pattern.encode.
pub fn encode_pattern(p : Pattern) -> Json {
  encode_pattern_with(p, exact_ints=false)
}

///|
/// Elm.Syntax.Expression.encode.
pub fn encode_expression(e : Expression) -> Json {
  encode_expression_with(e, exact_ints=false)
}

///|
/// Elm.Syntax.Expression.encodeFunction.
pub fn encode_function(f : Function) -> Json {
  encode_function_with(f, exact_ints=false)
}
