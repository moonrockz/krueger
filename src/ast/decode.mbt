// JSON decoders mirroring the `decoder` functions of stil4m/elm-syntax 7.3.9.
// Every decoder takes the JSON path of its input so that errors name the
// exact location (for example `$.declarations[3].value.function.signature`).

///|
/// Error raised on malformed input. `path` is a JSONPath-like location
/// (`$` is the value given to the public decoder).
pub(all) suberror DecodeError {
  DecodeError(path~ : String, message~ : String)
} derive(Eq, Debug)

///|
pub impl Show for DecodeError with fn output(self, logger) {
  let DecodeError(path~, message~) = self
  logger.write_string(path)
  logger.write_string(": ")
  logger.write_string(message)
}

///|
/// Location in the input. It is only rendered to a string on failure.
priv enum Path {
  Root
  Key(Path, String)
  Index(Path, Int)
}

///|
fn Path::render(self : Path) -> String {
  let sb = StringBuilder()
  self.write_to(sb)
  sb.to_string()
}

///|
fn Path::write_to(self : Path, sb : StringBuilder) -> Unit {
  match self {
    Root => sb.write_string("$")
    Key(parent, key) => {
      parent.write_to(sb)
      sb.write_string(".")
      sb.write_string(key)
    }
    Index(parent, i) => {
      parent.write_to(sb)
      sb.write_string("[")
      sb.write_string(i.to_string())
      sb.write_string("]")
    }
  }
}

///|
fn[T] fail(path : Path, message : String) -> T raise DecodeError {
  raise DecodeError(path=path.render(), message~)
}

///|
fn kind(j : Json) -> String {
  match j {
    Null => "null"
    True | False => "a BOOL"
    Number(_, ..) => "a NUMBER"
    String(_) => "a STRING"
    Array(_) => "an ARRAY"
    Object(_) => "an OBJECT"
  }
}

///|
/// Elm `JD.field key f`: the key must be present.
fn[T] field(
  j : Json,
  path : Path,
  key : String,
  f : (Json, Path) -> T raise DecodeError,
) -> T raise DecodeError {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(v) => f(v, Key(path, key))
        None => fail(path, "Expecting an OBJECT with a field named `\{key}`")
      }
    _ =>
      fail(
        path,
        "Expecting an OBJECT with a field named `\{key}` but got \{kind(j)}",
      )
  }
}

///|
fn string_at(j : Json, path : Path) -> String raise DecodeError {
  match j {
    String(s) => s
    _ => fail(path, "Expecting a STRING but got \{kind(j)}")
  }
}

///|
/// Elm `JD.int` for values that are 32-bit in practice (ranges, precedence).
fn int_at(j : Json, path : Path) -> Int raise DecodeError {
  match j {
    Number(d, ..) => {
      let i = d.to_int()
      if i.to_double() == d {
        i
      } else {
        fail(path, "Expecting a 32-bit INT but got \{d}")
      }
    }
    _ => fail(path, "Expecting an INT but got \{kind(j)}")
  }
}

///|
/// Elm `JD.int` for literal values. Elm ints on JS are doubles, so literals
/// such as `0xFFFFFFFF` or `31536000000` do not fit a 32-bit Int.
fn int64_at(j : Json, path : Path) -> Int64 raise DecodeError {
  match j {
    Number(d, ..) => {
      let i = d.to_int64()
      if i.to_double() == d {
        i
      } else {
        fail(path, "Expecting an INT but got \{d}")
      }
    }
    _ => fail(path, "Expecting an INT but got \{kind(j)}")
  }
}

///|
/// Elm `JD.float`.
fn double_at(j : Json, path : Path) -> Double raise DecodeError {
  match j {
    Number(d, ..) => d
    _ => fail(path, "Expecting a FLOAT but got \{kind(j)}")
  }
}

///|
/// elm-syntax `decodeChar`: the first character of a string.
fn char_at(j : Json, path : Path) -> Char raise DecodeError {
  let s = string_at(j, path)
  for c in s {
    return c
  }
  fail(path, "Not a char")
}

///|
/// Elm `JD.list f`.
fn[T] list_at(
  j : Json,
  path : Path,
  f : (Json, Path) -> T raise DecodeError,
) -> Array[T] raise DecodeError {
  match j {
    Array(xs) => {
      let out = Array(capacity=xs.length())
      for i, x in xs {
        out.push(f(x, Index(path, i)))
      }
      out
    }
    _ => fail(path, "Expecting a LIST but got \{kind(j)}")
  }
}

///|
/// Elm `JD.nullable f`.
fn[T] nullable_at(
  j : Json,
  path : Path,
  f : (Json, Path) -> T raise DecodeError,
) -> T? raise DecodeError {
  match j {
    Null => None
    _ => Some(f(j, path))
  }
}

///|
/// Elm.Json.Util.decodeTyped, step one: read the "type" tag. The caller
/// matches the tag and then reads the payload with `payload`.
fn typed(
  j : Json,
  path : Path,
) -> (String, Map[String, Json]) raise DecodeError {
  match j {
    Object(m) =>
      match m.get("type") {
        Some(String(t)) => (t, m)
        Some(other) =>
          fail(Key(path, "type"), "Expecting a STRING but got \{kind(other)}")
        None => fail(path, "Expecting an OBJECT with a field named `type`")
      }
    _ =>
      fail(
        path,
        "Expecting an OBJECT with a field named `type` but got \{kind(j)}",
      )
  }
}

///|
/// Elm.Json.Util.decodeTyped, step two: `JD.field tag decoder`.
fn[T] payload(
  m : Map[String, Json],
  tag : String,
  path : Path,
  f : (Json, Path) -> T raise DecodeError,
) -> T raise DecodeError {
  match m.get(tag) {
    Some(v) => f(v, Key(path, tag))
    None => fail(path, "Expecting an OBJECT with a field named `\{tag}`")
  }
}

///|
fn[T] unknown_tag(path : Path, tag : String) -> T raise DecodeError {
  fail(Key(path, "type"), "No decoder for type: \{tag}")
}

///|
fn range_at(j : Json, path : Path) -> Range raise DecodeError {
  match j {
    Array([a, b, c, d]) =>
      {
        start: {
          row: int_at(a, Index(path, 0)),
          column: int_at(b, Index(path, 1)),
        },
        end: {
          row: int_at(c, Index(path, 2)),
          column: int_at(d, Index(path, 3)),
        },
      }
    Array(_) => fail(path, "Invalid input list")
    _ => fail(path, "Expecting a LIST but got \{kind(j)}")
  }
}

///|
fn[T] node_at(
  j : Json,
  path : Path,
  f : (Json, Path) -> T raise DecodeError,
) -> Node[T] raise DecodeError {
  {
    range: field(j, path, "range", range_at),
    value: field(j, path, "value", f),
  }
}

///|
fn string_node_at(j : Json, path : Path) -> Node[String] raise DecodeError {
  node_at(j, path, string_at)
}

///|
fn module_name_at(j : Json, path : Path) -> ModuleName raise DecodeError {
  list_at(j, path, string_at)
}

///|
fn file_at(j : Json, path : Path) -> File raise DecodeError {
  {
    module_definition: field(j, path, "moduleDefinition", (v, p) => {
      node_at(v, p, module_at)
    }),
    imports: field(j, path, "imports", (v, p) => {
      list_at(v, p, (v, p) => node_at(v, p, import_at))
    }),
    declarations: field(j, path, "declarations", (v, p) => {
      list_at(v, p, (v, p) => node_at(v, p, declaration_at))
    }),
    comments: field(j, path, "comments", (v, p) => list_at(v, p, string_node_at)),
  }
}

///|
fn module_at(j : Json, path : Path) -> Module raise DecodeError {
  let (tag, m) = typed(j, path)
  match tag {
    "normal" => NormalModule(payload(m, tag, path, default_module_data_at))
    "port" => PortModule(payload(m, tag, path, default_module_data_at))
    "effect" => EffectModule(payload(m, tag, path, effect_module_data_at))
    _ => unknown_tag(path, tag)
  }
}

///|
fn default_module_data_at(
  j : Json,
  path : Path,
) -> DefaultModuleData raise DecodeError {
  {
    module_name: field(j, path, "moduleName", (v, p) => {
      node_at(v, p, module_name_at)
    }),
    exposing_list: field(j, path, "exposingList", (v, p) => {
      node_at(v, p, exposing_at)
    }),
  }
}

///|
fn effect_module_data_at(
  j : Json,
  path : Path,
) -> EffectModuleData raise DecodeError {
  {
    module_name: field(j, path, "moduleName", (v, p) => {
      node_at(v, p, module_name_at)
    }),
    exposing_list: field(j, path, "exposingList", (v, p) => {
      node_at(v, p, exposing_at)
    }),
    command: field(j, path, "command", (v, p) => {
      nullable_at(v, p, string_node_at)
    }),
    subscription: field(j, path, "subscription", (v, p) => {
      nullable_at(v, p, string_node_at)
    }),
  }
}

///|
fn exposing_at(j : Json, path : Path) -> Exposing raise DecodeError {
  let (tag, m) = typed(j, path)
  match tag {
    "all" => All(payload(m, tag, path, range_at))
    "explicit" =>
      Explicit(
        payload(m, tag, path, (v, p) => {
          list_at(v, p, (v, p) => node_at(v, p, top_level_expose_at))
        }),
      )
    _ => unknown_tag(path, tag)
  }
}

///|
fn name_field(j : Json, path : Path) -> String raise DecodeError {
  field(j, path, "name", string_at)
}

///|
fn top_level_expose_at(
  j : Json,
  path : Path,
) -> TopLevelExpose raise DecodeError {
  let (tag, m) = typed(j, path)
  match tag {
    "infix" => InfixExpose(payload(m, tag, path, name_field))
    "function" => FunctionExpose(payload(m, tag, path, name_field))
    "typeOrAlias" => TypeOrAliasExpose(payload(m, tag, path, name_field))
    "typeexpose" => TypeExpose(payload(m, tag, path, exposed_type_at))
    _ => unknown_tag(path, tag)
  }
}

///|
fn exposed_type_at(j : Json, path : Path) -> ExposedType raise DecodeError {
  {
    name: name_field(j, path),
    open: field(j, path, "open", (v, p) => nullable_at(v, p, range_at)),
  }
}

///|
fn import_at(j : Json, path : Path) -> Import raise DecodeError {
  {
    module_name: field(j, path, "moduleName", (v, p) => {
      node_at(v, p, module_name_at)
    }),
    module_alias: field(j, path, "moduleAlias", (v, p) => {
      nullable_at(v, p, (v, p) => node_at(v, p, module_name_at))
    }),
    exposing_list: field(j, path, "exposingList", (v, p) => {
      nullable_at(v, p, (v, p) => node_at(v, p, exposing_at))
    }),
  }
}

///|
fn declaration_at(j : Json, path : Path) -> Declaration raise DecodeError {
  let (tag, m) = typed(j, path)
  match tag {
    "function" => FunctionDeclaration(payload(m, tag, path, function_at))
    "typeAlias" => AliasDeclaration(payload(m, tag, path, type_alias_at))
    "typedecl" => CustomTypeDeclaration(payload(m, tag, path, type_at))
    "port" => PortDeclaration(payload(m, tag, path, signature_at))
    "infix" => InfixDeclaration(payload(m, tag, path, infix_at))
    "destructuring" =>
      payload(m, tag, path, (v, p) => {
        Destructuring(
          field(v, p, "pattern", pattern_node_at),
          field(v, p, "expression", expression_node_at),
        )
      })
    _ => unknown_tag(path, tag)
  }
}

///|
fn infix_at(j : Json, path : Path) -> Infix raise DecodeError {
  {
    direction: field(j, path, "direction", (v, p) => {
      node_at(v, p, infix_direction_at)
    }),
    precedence: field(j, path, "precedence", (v, p) => node_at(v, p, int_at)),
    operator: field(j, path, "operator", string_node_at),
    function: field(j, path, "function", string_node_at),
  }
}

///|
fn infix_direction_at(
  j : Json,
  path : Path,
) -> InfixDirection raise DecodeError {
  match string_at(j, path) {
    "left" => Left
    "right" => Right
    "non" => Non
    _ => fail(path, "Invalid direction")
  }
}

///|
fn signature_at(j : Json, path : Path) -> Signature raise DecodeError {
  {
    name: field(j, path, "name", string_node_at),
    type_annotation: field(j, path, "typeAnnotation", type_annotation_node_at),
  }
}

///|
fn documentation_at(
  j : Json,
  path : Path,
) -> Node[Documentation]? raise DecodeError {
  field(j, path, "documentation", (v, p) => nullable_at(v, p, string_node_at))
}

///|
fn generics_at(j : Json, path : Path) -> Array[Node[String]] raise DecodeError {
  field(j, path, "generics", (v, p) => list_at(v, p, string_node_at))
}

///|
fn type_alias_at(j : Json, path : Path) -> TypeAlias raise DecodeError {
  {
    documentation: documentation_at(j, path),
    name: field(j, path, "name", string_node_at),
    generics: generics_at(j, path),
    type_annotation: field(j, path, "typeAnnotation", type_annotation_node_at),
  }
}

///|
fn type_at(j : Json, path : Path) -> Type raise DecodeError {
  {
    documentation: documentation_at(j, path),
    name: field(j, path, "name", string_node_at),
    generics: generics_at(j, path),
    constructors: field(j, path, "constructors", (v, p) => {
      list_at(v, p, (v, p) => node_at(v, p, value_constructor_at))
    }),
  }
}

///|
fn value_constructor_at(
  j : Json,
  path : Path,
) -> ValueConstructor raise DecodeError {
  {
    name: field(j, path, "name", string_node_at),
    arguments: field(j, path, "arguments", (v, p) => {
      list_at(v, p, type_annotation_node_at)
    }),
  }
}

///|
fn type_annotation_node_at(
  j : Json,
  path : Path,
) -> Node[TypeAnnotation] raise DecodeError {
  node_at(j, path, type_annotation_at)
}

///|
fn type_annotation_list_at(
  j : Json,
  path : Path,
) -> Array[Node[TypeAnnotation]] raise DecodeError {
  list_at(j, path, type_annotation_node_at)
}

///|
fn type_annotation_at(
  j : Json,
  path : Path,
) -> TypeAnnotation raise DecodeError {
  let (tag, m) = typed(j, path)
  match tag {
    "generic" =>
      GenericType(
        payload(m, tag, path, (v, p) => field(v, p, "value", string_at)),
      )
    "typed" =>
      payload(m, tag, path, (v, p) => {
        Typed(
          field(v, p, "moduleNameAndName", (v, p) => {
            node_at(v, p, (v, p) => {
              (
                field(v, p, "moduleName", module_name_at),
                field(v, p, "name", string_at),
              )
            })
          }),
          field(v, p, "args", type_annotation_list_at),
        )
      })
    "unit" => payload(m, tag, path, (_, _) => Unit)
    "tupled" =>
      Tupled(
        payload(m, tag, path, (v, p) => {
          field(v, p, "values", type_annotation_list_at)
        }),
      )
    "function" =>
      payload(m, tag, path, (v, p) => {
        FunctionTypeAnnotation(
          field(v, p, "left", type_annotation_node_at),
          field(v, p, "right", type_annotation_node_at),
        )
      })
    "record" =>
      Record(
        payload(m, tag, path, (v, p) => {
          field(v, p, "value", record_definition_at)
        }),
      )
    "genericRecord" =>
      payload(m, tag, path, (v, p) => {
        GenericRecord(
          field(v, p, "name", string_node_at),
          field(v, p, "values", (v, p) => node_at(v, p, record_definition_at)),
        )
      })
    _ => unknown_tag(path, tag)
  }
}

///|
fn record_definition_at(
  j : Json,
  path : Path,
) -> RecordDefinition raise DecodeError {
  list_at(j, path, (v, p) => {
    node_at(v, p, (v, p) => {
      name: field(v, p, "name", string_node_at),
      type_annotation: field(v, p, "typeAnnotation", type_annotation_node_at),
    })
  })
}

///|
fn pattern_node_at(j : Json, path : Path) -> Node[Pattern] raise DecodeError {
  node_at(j, path, pattern_at)
}

///|
fn pattern_list_at(
  j : Json,
  path : Path,
) -> Array[Node[Pattern]] raise DecodeError {
  list_at(j, path, pattern_node_at)
}

///|
/// elm-syntax 7.3.9 encodes HexPattern as `{"value": h}` but its decoder
/// reads a bare int (`JD.int |> JD.map HexPattern`), so elm-syntax cannot
/// decode its own output. This decoder accepts the encoded shape and also the
/// bare int.
fn hex_pattern_value_at(j : Json, path : Path) -> Int64 raise DecodeError {
  match j {
    Number(_, ..) => int64_at(j, path)
    _ => field(j, path, "value", int64_at)
  }
}

///|
fn pattern_at(j : Json, path : Path) -> Pattern raise DecodeError {
  let (tag, m) = typed(j, path)
  match tag {
    "all" => payload(m, tag, path, (_, _) => AllPattern)
    "unit" => payload(m, tag, path, (_, _) => UnitPattern)
    "char" =>
      CharPattern(
        payload(m, tag, path, (v, p) => field(v, p, "value", char_at)),
      )
    "string" =>
      StringPattern(
        payload(m, tag, path, (v, p) => field(v, p, "value", string_at)),
      )
    "hex" => HexPattern(payload(m, tag, path, hex_pattern_value_at))
    "int" =>
      IntPattern(
        payload(m, tag, path, (v, p) => field(v, p, "value", int64_at)),
      )
    "float" =>
      FloatPattern(
        payload(m, tag, path, (v, p) => field(v, p, "value", double_at)),
      )
    "tuple" =>
      TuplePattern(
        payload(m, tag, path, (v, p) => field(v, p, "value", pattern_list_at)),
      )
    "record" =>
      RecordPattern(
        payload(m, tag, path, (v, p) => {
          field(v, p, "value", (v, p) => list_at(v, p, string_node_at))
        }),
      )
    "uncons" =>
      payload(m, tag, path, (v, p) => {
        UnConsPattern(
          field(v, p, "left", pattern_node_at),
          field(v, p, "right", pattern_node_at),
        )
      })
    "list" =>
      ListPattern(
        payload(m, tag, path, (v, p) => field(v, p, "value", pattern_list_at)),
      )
    "var" =>
      VarPattern(
        payload(m, tag, path, (v, p) => field(v, p, "value", string_at)),
      )
    "named" =>
      payload(m, tag, path, (v, p) => {
        NamedPattern(
          field(v, p, "qualified", (v, p) => {
            module_name: field(v, p, "moduleName", module_name_at),
            name: field(v, p, "name", string_at),
          }),
          field(v, p, "patterns", pattern_list_at),
        )
      })
    "as" =>
      payload(m, tag, path, (v, p) => {
        AsPattern(
          field(v, p, "pattern", pattern_node_at),
          field(v, p, "name", string_node_at),
        )
      })
    "parentisized" =>
      ParenthesizedPattern(
        payload(m, tag, path, (v, p) => field(v, p, "value", pattern_node_at)),
      )
    _ => unknown_tag(path, tag)
  }
}

///|
fn expression_node_at(
  j : Json,
  path : Path,
) -> Node[Expression] raise DecodeError {
  node_at(j, path, expression_at)
}

///|
fn expression_list_at(
  j : Json,
  path : Path,
) -> Array[Node[Expression]] raise DecodeError {
  list_at(j, path, expression_node_at)
}

///|
fn record_setter_list_at(
  j : Json,
  path : Path,
) -> Array[Node[RecordSetter]] raise DecodeError {
  list_at(j, path, (v, p) => {
    node_at(v, p, (v, p) => {
      field: field(v, p, "field", string_node_at),
      expression: field(v, p, "expression", expression_node_at),
    })
  })
}

///|
fn expression_at(j : Json, path : Path) -> Expression raise DecodeError {
  let (tag, m) = typed(j, path)
  match tag {
    "unit" => payload(m, tag, path, (_, _) => UnitExpr)
    "application" => Application(payload(m, tag, path, expression_list_at))
    "operatorapplication" =>
      payload(m, tag, path, (v, p) => {
        OperatorApplication(
          field(v, p, "operator", string_at),
          field(v, p, "direction", infix_direction_at),
          field(v, p, "left", expression_node_at),
          field(v, p, "right", expression_node_at),
        )
      })
    "functionOrValue" =>
      payload(m, tag, path, (v, p) => {
        FunctionOrValue(
          field(v, p, "moduleName", module_name_at),
          field(v, p, "name", string_at),
        )
      })
    "ifBlock" =>
      payload(m, tag, path, (v, p) => {
        IfBlock(
          field(v, p, "clause", expression_node_at),
          field(v, p, "then", expression_node_at),
          field(v, p, "else", expression_node_at),
        )
      })
    "prefixoperator" => PrefixOperator(payload(m, tag, path, string_at))
    "operator" => Operator(payload(m, tag, path, string_at))
    "hex" => Hex(payload(m, tag, path, int64_at))
    "integer" => Integer(payload(m, tag, path, int64_at))
    "float" => Floatable(payload(m, tag, path, double_at))
    "negation" => Negation(payload(m, tag, path, expression_node_at))
    "literal" => Literal(payload(m, tag, path, string_at))
    "charLiteral" => CharLiteral(payload(m, tag, path, char_at))
    "tupled" => TupledExpression(payload(m, tag, path, expression_list_at))
    "list" => ListExpr(payload(m, tag, path, expression_list_at))
    "parenthesized" =>
      ParenthesizedExpression(payload(m, tag, path, expression_node_at))
    "let" => LetExpression(payload(m, tag, path, let_block_at))
    "case" => CaseExpression(payload(m, tag, path, case_block_at))
    "lambda" => LambdaExpression(payload(m, tag, path, lambda_at))
    "recordAccess" =>
      payload(m, tag, path, (v, p) => {
        RecordAccess(
          field(v, p, "expression", expression_node_at),
          field(v, p, "name", string_node_at),
        )
      })
    "recordAccessFunction" =>
      RecordAccessFunction(payload(m, tag, path, string_at))
    "record" => RecordExpr(payload(m, tag, path, record_setter_list_at))
    "recordUpdate" =>
      payload(m, tag, path, (v, p) => {
        RecordUpdateExpression(
          field(v, p, "name", string_node_at),
          field(v, p, "updates", record_setter_list_at),
        )
      })
    "glsl" => GLSLExpression(payload(m, tag, path, string_at))
    _ => unknown_tag(path, tag)
  }
}

///|
fn let_block_at(j : Json, path : Path) -> LetBlock raise DecodeError {
  {
    declarations: field(j, path, "declarations", (v, p) => {
      list_at(v, p, (v, p) => node_at(v, p, let_declaration_at))
    }),
    expression: field(j, path, "expression", expression_node_at),
  }
}

///|
fn let_declaration_at(
  j : Json,
  path : Path,
) -> LetDeclaration raise DecodeError {
  let (tag, m) = typed(j, path)
  match tag {
    "function" => LetFunction(payload(m, tag, path, function_at))
    "destructuring" =>
      payload(m, tag, path, (v, p) => {
        LetDestructuring(
          field(v, p, "pattern", pattern_node_at),
          field(v, p, "expression", expression_node_at),
        )
      })
    _ => unknown_tag(path, tag)
  }
}

///|
fn case_block_at(j : Json, path : Path) -> CaseBlock raise DecodeError {
  {
    expression: field(j, path, "expression", expression_node_at),
    cases: field(j, path, "cases", (v, p) => {
      list_at(v, p, (v, p) => {
        pattern: field(v, p, "pattern", pattern_node_at),
        expression: field(v, p, "expression", expression_node_at),
      })
    }),
  }
}

///|
fn lambda_at(j : Json, path : Path) -> Lambda raise DecodeError {
  {
    args: field(j, path, "patterns", pattern_list_at),
    expression: field(j, path, "expression", expression_node_at),
  }
}

///|
fn function_at(j : Json, path : Path) -> Function raise DecodeError {
  {
    documentation: documentation_at(j, path),
    signature: field(j, path, "signature", (v, p) => {
      nullable_at(v, p, (v, p) => node_at(v, p, signature_at))
    }),
    declaration: field(j, path, "declaration", (v, p) => {
      node_at(v, p, function_implementation_at)
    }),
  }
}

///|
fn function_implementation_at(
  j : Json,
  path : Path,
) -> FunctionImplementation raise DecodeError {
  {
    name: field(j, path, "name", string_node_at),
    arguments: field(j, path, "arguments", pattern_list_at),
    expression: field(j, path, "expression", expression_node_at),
  }
}

// ---------------------------------------------------------------------------
// Public decoders. Each one mirrors an elm-syntax `decoder`.

///|
/// Elm.Syntax.File.decoder.
pub fn decode_file(json : Json) -> File raise DecodeError {
  file_at(json, Root)
}

///|
/// Elm.Syntax.Range.decoder.
pub fn decode_range(json : Json) -> Range raise DecodeError {
  range_at(json, Root)
}

///|
/// Elm.Syntax.Node.decoder. Errors raised by `f` get the prefix `$.value`.
pub fn[T] decode_node(
  json : Json,
  f : (Json) -> T raise DecodeError,
) -> Node[T] raise DecodeError {
  node_at(json, Root, (v, p) => {
    f(v) catch {
      DecodeError(path~, message~) =>
        raise DecodeError(path=p.render() + path[1:].to_owned(), message~)
    }
  })
}

///|
/// Elm.Syntax.ModuleName.decoder.
pub fn decode_module_name(json : Json) -> ModuleName raise DecodeError {
  module_name_at(json, Root)
}

///|
/// Elm.Syntax.Module.decoder.
pub fn decode_module(json : Json) -> Module raise DecodeError {
  module_at(json, Root)
}

///|
/// Elm.Syntax.Exposing.decoder.
pub fn decode_exposing(json : Json) -> Exposing raise DecodeError {
  exposing_at(json, Root)
}

///|
/// Elm.Syntax.Exposing.topLevelExposeDecoder (the value inside the Node).
pub fn decode_top_level_expose(json : Json) -> TopLevelExpose raise DecodeError {
  top_level_expose_at(json, Root)
}

///|
/// Elm.Syntax.Import.decoder.
pub fn decode_import(json : Json) -> Import raise DecodeError {
  import_at(json, Root)
}

///|
/// Elm.Syntax.Declaration.decoder.
pub fn decode_declaration(json : Json) -> Declaration raise DecodeError {
  declaration_at(json, Root)
}

///|
/// Elm.Syntax.Infix.decoder.
pub fn decode_infix(json : Json) -> Infix raise DecodeError {
  infix_at(json, Root)
}

///|
/// Elm.Syntax.Infix.decodeDirection.
pub fn decode_infix_direction(json : Json) -> InfixDirection raise DecodeError {
  infix_direction_at(json, Root)
}

///|
/// Elm.Syntax.Signature.decoder.
pub fn decode_signature(json : Json) -> Signature raise DecodeError {
  signature_at(json, Root)
}

///|
/// Elm.Syntax.TypeAlias.decoder.
pub fn decode_type_alias(json : Json) -> TypeAlias raise DecodeError {
  type_alias_at(json, Root)
}

///|
/// Elm.Syntax.Type.decoder.
pub fn decode_type(json : Json) -> Type raise DecodeError {
  type_at(json, Root)
}

///|
/// Elm.Syntax.Type.valueConstructorDecoder.
pub fn decode_value_constructor(
  json : Json,
) -> ValueConstructor raise DecodeError {
  value_constructor_at(json, Root)
}

///|
/// Elm.Syntax.TypeAnnotation.decoder.
pub fn decode_type_annotation(json : Json) -> TypeAnnotation raise DecodeError {
  type_annotation_at(json, Root)
}

///|
/// Elm.Syntax.Pattern.decoder.
pub fn decode_pattern(json : Json) -> Pattern raise DecodeError {
  pattern_at(json, Root)
}

///|
/// Elm.Syntax.Expression.decoder.
pub fn decode_expression(json : Json) -> Expression raise DecodeError {
  expression_at(json, Root)
}

///|
/// Elm.Syntax.Expression.functionDecoder.
pub fn decode_function(json : Json) -> Function raise DecodeError {
  function_at(json, Root)
}
