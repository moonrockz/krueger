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
/// Shows the error as its JSON path, then `: `, then the message (see the
/// example on `decode_file`).
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
  Index(Path, Int32)
}

///|
/// Renders the path without recursion (a path at the bottom of a deep tree
/// has thousands of segments): the segments are collected from the leaf
/// up, then written from the root down.
fn Path::render(self : Path) -> String {
  let segments : Array[String] = []
  let mut at = self
  while true {
    match at {
      Root => break
      Key(parent, key) => {
        segments.push("." + key)
        at = parent
      }
      Index(parent, i) => {
        segments.push("[" + i.to_string() + "]")
        at = parent
      }
    }
  }
  let sb = StringBuilder()
  sb.write_string("$")
  for i = segments.length() - 1; i >= 0; i = i - 1 {
    sb.write_string(segments[i])
  }
  sb.to_string()
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
fn int_at(j : Json, path : Path) -> Int32 raise DecodeError {
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
/// `digits` as an Int64, when they are an Int literal in its range.
fn exact_int64(digits : String) -> Int64? {
  try @string.parse_int64(digits) catch {
    _ => None
  } noraise {
    i => Some(i)
  }
}

///|
/// Elm `JD.int` for literal values. Elm ints on JS are doubles, so literals
/// such as `0xFFFFFFFF` or `31536000000` do not fit a 32-bit Int.
fn int64_at(j : Json, path : Path) -> Int64 raise DecodeError {
  match j {
    // Parsed JSON keeps a number's digits. Read them exactly when they are an
    // Int that rounds to the number's Double and are not that Double's own
    // shortest form (elm-syntax writes 2^60 as `1152921504606847000`, which
    // means the Double, not those digits); else read the Double.
    Number(d, repr=Some(digits)) if digits != d.to_string() &&
      exact_int64(digits) is Some(i) &&
      i.to_double() == d => i
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
/// A step of the decoder. The decoder does not recurse per AST level: a
/// step reads the shallow fields of one node in elm-syntax's order, and
/// gives back the steps for its nested nodes (each one looks its field up
/// when it runs, so the first error reported is the one a depth-first
/// decoder reports) and a last step that builds the node from the cells
/// its children filled. `run` pops steps until none is left.
priv struct Step(() -> Array[Step] raise DecodeError)

///|
fn run(start : Step) -> Unit raise DecodeError {
  let stack : Array[Step] = [start]
  while stack.pop() is Some(step) {
    let Step(f) = step
    let more = f()
    for i = more.length() - 1; i >= 0; i = i - 1 {
      stack.push(more[i])
    }
  }
}

///|
/// The value a child step decoded into its cell.
fn[T] got(cell : Ref[T?]) -> T raise DecodeError {
  match cell.val {
    Some(v) => v
    None => fail(Root, "internal error: a nested node was not decoded")
  }
}

///|
/// `(Json, Path)` as a decoder, for `field` and `payload`: the step that
/// uses the value does the decoding.
let pair : (Json, Path) -> (Json, Path) raise DecodeError = (j, p) => (j, p)

///|
/// A step that decodes the node at `get()`: its range, then its value with
/// `value_steps`, into `out`.
fn[T] node_step(
  get : () -> (Json, Path) raise DecodeError,
  value_steps : (Json, Path, Ref[T?]) -> Array[Step] raise DecodeError,
  out : Ref[Node[T]?],
) -> Step {
  Step(() => {
    let (j, path) = get()
    let range = field(j, path, "range", range_at)
    let (v, p) = field(j, path, "value", pair)
    let value : Ref[T?] = Ref(None)
    let steps = value_steps(v, p, value)
    steps.push(
      Step(() => {
        out.val = Some({ range, value: got(value), })
        []
      }),
    )
    steps
  })
}

///|
/// A step that decodes the list at `get()` with one `element` step per
/// item, into `out`.
fn[T] list_step(
  get : () -> (Json, Path) raise DecodeError,
  element : (() -> (Json, Path) raise DecodeError, Ref[T?]) -> Step,
  out : Ref[Array[T]?],
) -> Step {
  Step(() => {
    let (j, path) = get()
    guard j is Array(xs) else {
      fail(path, "Expecting a LIST but got \{kind(j)}")
    }
    let cells : Array[Ref[T?]] = []
    let steps : Array[Step] = []
    for i, x in xs {
      let cell : Ref[T?] = Ref(None)
      cells.push(cell)
      steps.push(element(() => (x, Index(path, i)), cell))
    }
    steps.push(
      Step(() => {
        let items = Array(capacity=cells.length())
        for cell in cells {
          items.push(got(cell))
        }
        out.val = Some(items)
        []
      }),
    )
    steps
  })
}

///|
/// Runs `steps` for the value at `(j, path)` and gives the value.
fn[T] decode_with(
  j : Json,
  path : Path,
  steps : (Json, Path, Ref[T?]) -> Array[Step] raise DecodeError,
) -> T raise DecodeError {
  let out : Ref[T?] = Ref(None)
  run(Step(() => steps(j, path, out)))
  got(out)
}

// --- file and declarations --------------------------------------------------

///|
fn file_steps(
  j : Json,
  path : Path,
  out : Ref[File?],
) -> Array[Step] raise DecodeError {
  let module_definition = field(j, path, "moduleDefinition", (v, p) => {
    node_at(v, p, module_at)
  })
  let imports = field(j, path, "imports", (v, p) => {
    list_at(v, p, (v, p) => node_at(v, p, import_at))
  })
  let declarations : Ref[Array[Node[Declaration]]?] = Ref(None)
  [
    list_step(
      () => field(j, path, "declarations", pair),
      (get, cell) => node_step(get, declaration_steps, cell),
      declarations,
    ),
    Step(() => {
      let comments = field(j, path, "comments", (v, p) => {
        list_at(v, p, string_node_at)
      })
      out.val = Some({
        module_definition,
        imports,
        declarations: got(declarations),
        comments,
      })
      []
    }),
  ]
}

///|
fn declaration_steps(
  j : Json,
  path : Path,
  out : Ref[Declaration?],
) -> Array[Step] raise DecodeError {
  let (tag, m) = typed(j, path)
  match tag {
    "function" => {
      let (v, p) = payload(m, tag, path, pair)
      let f : Ref[Function?] = Ref(None)
      let steps = function_steps(v, p, f)
      steps.push(
        Step(() => {
          out.val = Some(FunctionDeclaration(got(f)))
          []
        }),
      )
      steps
    }
    "typeAlias" => {
      let (v, p) = payload(m, tag, path, pair)
      let a : Ref[TypeAlias?] = Ref(None)
      let steps = type_alias_steps(v, p, a)
      steps.push(
        Step(() => {
          out.val = Some(AliasDeclaration(got(a)))
          []
        }),
      )
      steps
    }
    "typedecl" => {
      let (v, p) = payload(m, tag, path, pair)
      let t : Ref[Type?] = Ref(None)
      let steps = type_steps(v, p, t)
      steps.push(
        Step(() => {
          out.val = Some(CustomTypeDeclaration(got(t)))
          []
        }),
      )
      steps
    }
    "port" => {
      let (v, p) = payload(m, tag, path, pair)
      let sig : Ref[Signature?] = Ref(None)
      let steps = signature_steps(v, p, sig)
      steps.push(
        Step(() => {
          out.val = Some(PortDeclaration(got(sig)))
          []
        }),
      )
      steps
    }
    "infix" => {
      out.val = Some(InfixDeclaration(payload(m, tag, path, infix_at)))
      []
    }
    "destructuring" => {
      let (v, p) = payload(m, tag, path, pair)
      let pattern : Ref[Node[Pattern]?] = Ref(None)
      let expression : Ref[Node[Expression]?] = Ref(None)
      [
        node_step(() => field(v, p, "pattern", pair), pattern_steps, pattern),
        node_step(
          () => field(v, p, "expression", pair),
          expression_steps,
          expression,
        ),
        Step(() => {
          out.val = Some(Destructuring(got(pattern), got(expression)))
          []
        }),
      ]
    }
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
fn signature_steps(
  j : Json,
  path : Path,
  out : Ref[Signature?],
) -> Array[Step] raise DecodeError {
  let name = field(j, path, "name", string_node_at)
  let type_annotation : Ref[Node[TypeAnnotation]?] = Ref(None)
  [
    node_step(
      () => field(j, path, "typeAnnotation", pair),
      type_annotation_steps,
      type_annotation,
    ),
    Step(() => {
      out.val = Some({ name, type_annotation: got(type_annotation), })
      []
    }),
  ]
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
fn type_alias_steps(
  j : Json,
  path : Path,
  out : Ref[TypeAlias?],
) -> Array[Step] raise DecodeError {
  let documentation = documentation_at(j, path)
  let name = field(j, path, "name", string_node_at)
  let generics = generics_at(j, path)
  let type_annotation : Ref[Node[TypeAnnotation]?] = Ref(None)
  [
    node_step(
      () => field(j, path, "typeAnnotation", pair),
      type_annotation_steps,
      type_annotation,
    ),
    Step(() => {
      out.val = Some({
        documentation,
        name,
        generics,
        type_annotation: got(type_annotation),
      })
      []
    }),
  ]
}

///|
fn type_steps(
  j : Json,
  path : Path,
  out : Ref[Type?],
) -> Array[Step] raise DecodeError {
  let documentation = documentation_at(j, path)
  let name = field(j, path, "name", string_node_at)
  let generics = generics_at(j, path)
  let constructors : Ref[Array[Node[ValueConstructor]]?] = Ref(None)
  [
    list_step(
      () => field(j, path, "constructors", pair),
      (get, cell) => node_step(get, value_constructor_steps, cell),
      constructors,
    ),
    Step(() => {
      out.val = Some({
        documentation,
        name,
        generics,
        constructors: got(constructors),
      })
      []
    }),
  ]
}

///|
fn value_constructor_steps(
  j : Json,
  path : Path,
  out : Ref[ValueConstructor?],
) -> Array[Step] raise DecodeError {
  let name = field(j, path, "name", string_node_at)
  let arguments : Ref[Array[Node[TypeAnnotation]]?] = Ref(None)
  [
    type_annotation_list_step(
      () => field(j, path, "arguments", pair),
      arguments,
    ),
    Step(() => {
      out.val = Some({ name, arguments: got(arguments), })
      []
    }),
  ]
}

// --- type annotations -------------------------------------------------------

///|
fn type_annotation_list_step(
  get : () -> (Json, Path) raise DecodeError,
  out : Ref[Array[Node[TypeAnnotation]]?],
) -> Step {
  list_step(
    get,
    (get, cell) => node_step(get, type_annotation_steps, cell),
    out,
  )
}

///|
fn type_annotation_steps(
  j : Json,
  path : Path,
  out : Ref[TypeAnnotation?],
) -> Array[Step] raise DecodeError {
  let (tag, m) = typed(j, path)
  match tag {
    "generic" => {
      out.val = Some(
        GenericType(
          payload(m, tag, path, (v, p) => field(v, p, "value", string_at)),
        ),
      )
      []
    }
    "typed" => {
      let (v, p) = payload(m, tag, path, pair)
      let name = field(v, p, "moduleNameAndName", (v, p) => {
        node_at(v, p, (v, p) => {
          (
            field(v, p, "moduleName", module_name_at),
            field(v, p, "name", string_at),
          )
        })
      })
      let args : Ref[Array[Node[TypeAnnotation]]?] = Ref(None)
      [
        type_annotation_list_step(() => field(v, p, "args", pair), args),
        Step(() => {
          out.val = Some(Typed(name, got(args)))
          []
        }),
      ]
    }
    "unit" => {
      ignore(payload(m, tag, path, pair))
      out.val = Some(Unit)
      []
    }
    "tupled" => {
      let (v, p) = payload(m, tag, path, pair)
      let values : Ref[Array[Node[TypeAnnotation]]?] = Ref(None)
      [
        type_annotation_list_step(() => field(v, p, "values", pair), values),
        Step(() => {
          out.val = Some(Tupled(got(values)))
          []
        }),
      ]
    }
    "function" => {
      let (v, p) = payload(m, tag, path, pair)
      let left : Ref[Node[TypeAnnotation]?] = Ref(None)
      let right : Ref[Node[TypeAnnotation]?] = Ref(None)
      [
        node_step(() => field(v, p, "left", pair), type_annotation_steps, left),
        node_step(
          () => field(v, p, "right", pair),
          type_annotation_steps,
          right,
        ),
        Step(() => {
          out.val = Some(FunctionTypeAnnotation(got(left), got(right)))
          []
        }),
      ]
    }
    "record" => {
      let (v, p) = payload(m, tag, path, pair)
      let fields : Ref[Array[Node[RecordField]]?] = Ref(None)
      [
        record_definition_step(() => field(v, p, "value", pair), fields),
        Step(() => {
          out.val = Some(Record(got(fields)))
          []
        }),
      ]
    }
    "genericRecord" => {
      let (v, p) = payload(m, tag, path, pair)
      let name = field(v, p, "name", string_node_at)
      let fields : Ref[Node[Array[Node[RecordField]]]?] = Ref(None)
      [
        node_step(
          () => field(v, p, "values", pair),
          (j, p, cell) => [record_definition_step(() => (j, p), cell)],
          fields,
        ),
        Step(() => {
          let f = got(fields)
          out.val = Some(
            GenericRecord(name, { range: f.range, value: f.value, }),
          )
          []
        }),
      ]
    }
    _ => unknown_tag(path, tag)
  }
}

///|
fn record_definition_step(
  get : () -> (Json, Path) raise DecodeError,
  out : Ref[Array[Node[RecordField]]?],
) -> Step {
  list_step(
    get,
    (get, cell) => {
      node_step(
        get,
        (v, p, field_out) => {
          let name = field(v, p, "name", string_node_at)
          let type_annotation : Ref[Node[TypeAnnotation]?] = Ref(None)
          [
            node_step(
              () => field(v, p, "typeAnnotation", pair),
              type_annotation_steps,
              type_annotation,
            ),
            Step(() => {
              field_out.val = Some(
                ({ name, type_annotation: got(type_annotation), } : RecordField),
              )
              []
            }),
          ]
        },
        cell,
      )
    },
    out,
  )
}

// --- patterns ---------------------------------------------------------------

///|
fn pattern_list_step(
  get : () -> (Json, Path) raise DecodeError,
  out : Ref[Array[Node[Pattern]]?],
) -> Step {
  list_step(get, (get, cell) => node_step(get, pattern_steps, cell), out)
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
fn pattern_steps(
  j : Json,
  path : Path,
  out : Ref[Pattern?],
) -> Array[Step] raise DecodeError {
  let (tag, m) = typed(j, path)
  let done = (p : Pattern) => {
    out.val = Some(p)
    ([] : Array[Step])
  }
  match tag {
    "all" => {
      ignore(payload(m, tag, path, pair))
      done(AllPattern)
    }
    "unit" => {
      ignore(payload(m, tag, path, pair))
      done(UnitPattern)
    }
    "char" =>
      done(
        CharPattern(
          payload(m, tag, path, (v, p) => field(v, p, "value", char_at)),
        ),
      )
    "string" =>
      done(
        StringPattern(
          payload(m, tag, path, (v, p) => field(v, p, "value", string_at)),
        ),
      )
    "hex" => done(HexPattern(payload(m, tag, path, hex_pattern_value_at)))
    "int" =>
      done(
        IntPattern(
          payload(m, tag, path, (v, p) => field(v, p, "value", int64_at)),
        ),
      )
    "float" =>
      done(
        FloatPattern(
          payload(m, tag, path, (v, p) => field(v, p, "value", double_at)),
        ),
      )
    "tuple" => {
      let (v, p) = payload(m, tag, path, pair)
      let items : Ref[Array[Node[Pattern]]?] = Ref(None)
      [
        pattern_list_step(() => field(v, p, "value", pair), items),
        Step(() => done(TuplePattern(got(items)))),
      ]
    }
    "record" =>
      done(
        RecordPattern(
          payload(m, tag, path, (v, p) => {
            field(v, p, "value", (v, p) => list_at(v, p, string_node_at))
          }),
        ),
      )
    "uncons" => {
      let (v, p) = payload(m, tag, path, pair)
      let left : Ref[Node[Pattern]?] = Ref(None)
      let right : Ref[Node[Pattern]?] = Ref(None)
      [
        node_step(() => field(v, p, "left", pair), pattern_steps, left),
        node_step(() => field(v, p, "right", pair), pattern_steps, right),
        Step(() => done(UnConsPattern(got(left), got(right)))),
      ]
    }
    "list" => {
      let (v, p) = payload(m, tag, path, pair)
      let items : Ref[Array[Node[Pattern]]?] = Ref(None)
      [
        pattern_list_step(() => field(v, p, "value", pair), items),
        Step(() => done(ListPattern(got(items)))),
      ]
    }
    "var" =>
      done(
        VarPattern(
          payload(m, tag, path, (v, p) => field(v, p, "value", string_at)),
        ),
      )
    "named" => {
      let (v, p) = payload(m, tag, path, pair)
      let qualified : QualifiedNameRef = field(v, p, "qualified", (v, p) => {
        module_name: field(v, p, "moduleName", module_name_at),
        name: field(v, p, "name", string_at),
      })
      let args : Ref[Array[Node[Pattern]]?] = Ref(None)
      [
        pattern_list_step(() => field(v, p, "patterns", pair), args),
        Step(() => done(NamedPattern(qualified, got(args)))),
      ]
    }
    "as" => {
      let (v, p) = payload(m, tag, path, pair)
      let inner : Ref[Node[Pattern]?] = Ref(None)
      [
        node_step(() => field(v, p, "pattern", pair), pattern_steps, inner),
        // The name is read after the pattern, as elm-syntax does.
        Step(() => {
          done(AsPattern(got(inner), field(v, p, "name", string_node_at)))
        }),
      ]
    }
    "parentisized" => {
      let (v, p) = payload(m, tag, path, pair)
      let inner : Ref[Node[Pattern]?] = Ref(None)
      [
        node_step(() => field(v, p, "value", pair), pattern_steps, inner),
        Step(() => done(ParenthesizedPattern(got(inner)))),
      ]
    }
    _ => unknown_tag(path, tag)
  }
}

// --- expressions ------------------------------------------------------------

///|
fn expression_list_step(
  get : () -> (Json, Path) raise DecodeError,
  out : Ref[Array[Node[Expression]]?],
) -> Step {
  list_step(get, (get, cell) => node_step(get, expression_steps, cell), out)
}

///|
fn record_setter_list_step(
  get : () -> (Json, Path) raise DecodeError,
  out : Ref[Array[Node[RecordSetter]]?],
) -> Step {
  list_step(
    get,
    (get, cell) => {
      node_step(
        get,
        (v, p, setter_out) => {
          let field_name = field(v, p, "field", string_node_at)
          let expression : Ref[Node[Expression]?] = Ref(None)
          [
            node_step(
              () => field(v, p, "expression", pair),
              expression_steps,
              expression,
            ),
            Step(() => {
              setter_out.val = Some(
                (
                  { field: field_name, expression: got(expression), } :
                  RecordSetter),
              )
              []
            }),
          ]
        },
        cell,
      )
    },
    out,
  )
}

///|
fn expression_steps(
  j : Json,
  path : Path,
  out : Ref[Expression?],
) -> Array[Step] raise DecodeError {
  let (tag, m) = typed(j, path)
  let done = (e : Expression) => {
    out.val = Some(e)
    ([] : Array[Step])
  }
  // One nested expression in the payload, wrapped by `make`.
  let nested = (make : (Node[Expression]) -> Expression) => {
    let (v, p) = payload(m, tag, path, pair)
    let inner : Ref[Node[Expression]?] = Ref(None)
    [
      node_step(() => (v, p), expression_steps, inner),
      Step(() => done(make(got(inner)))),
    ]
  }
  // A list of nested expressions in the payload, wrapped by `make`.
  let nested_list = (make : (Array[Node[Expression]]) -> Expression) => {
    let (v, p) = payload(m, tag, path, pair)
    let items : Ref[Array[Node[Expression]]?] = Ref(None)
    [
      expression_list_step(() => (v, p), items),
      Step(() => done(make(got(items)))),
    ]
  }
  match tag {
    "unit" => {
      ignore(payload(m, tag, path, pair))
      done(UnitExpr)
    }
    "application" => nested_list(xs => Application(xs))
    "operatorapplication" => {
      let (v, p) = payload(m, tag, path, pair)
      let op = field(v, p, "operator", string_at)
      let direction = field(v, p, "direction", infix_direction_at)
      let left : Ref[Node[Expression]?] = Ref(None)
      let right : Ref[Node[Expression]?] = Ref(None)
      [
        node_step(() => field(v, p, "left", pair), expression_steps, left),
        node_step(() => field(v, p, "right", pair), expression_steps, right),
        Step(() => {
          done(OperatorApplication(op, direction, got(left), got(right)))
        }),
      ]
    }
    "functionOrValue" => {
      let (v, p) = payload(m, tag, path, pair)
      done(
        FunctionOrValue(
          field(v, p, "moduleName", module_name_at),
          field(v, p, "name", string_at),
        ),
      )
    }
    "ifBlock" => {
      let (v, p) = payload(m, tag, path, pair)
      let clause : Ref[Node[Expression]?] = Ref(None)
      let then_ : Ref[Node[Expression]?] = Ref(None)
      let else_ : Ref[Node[Expression]?] = Ref(None)
      [
        node_step(() => field(v, p, "clause", pair), expression_steps, clause),
        node_step(() => field(v, p, "then", pair), expression_steps, then_),
        node_step(() => field(v, p, "else", pair), expression_steps, else_),
        Step(() => done(IfBlock(got(clause), got(then_), got(else_)))),
      ]
    }
    "prefixoperator" => done(PrefixOperator(payload(m, tag, path, string_at)))
    "operator" => done(Operator(payload(m, tag, path, string_at)))
    "hex" => done(Hex(payload(m, tag, path, int64_at)))
    "integer" => done(Integer(payload(m, tag, path, int64_at)))
    "float" => done(Floatable(payload(m, tag, path, double_at)))
    "negation" => nested(x => Negation(x))
    "literal" => done(Literal(payload(m, tag, path, string_at)))
    "charLiteral" => done(CharLiteral(payload(m, tag, path, char_at)))
    "tupled" => nested_list(xs => TupledExpression(xs))
    "list" => nested_list(xs => ListExpr(xs))
    "parenthesized" => nested(x => ParenthesizedExpression(x))
    "let" => {
      let (v, p) = payload(m, tag, path, pair)
      let declarations : Ref[Array[Node[LetDeclaration]]?] = Ref(None)
      let expression : Ref[Node[Expression]?] = Ref(None)
      [
        list_step(
          () => field(v, p, "declarations", pair),
          (get, cell) => node_step(get, let_declaration_steps, cell),
          declarations,
        ),
        node_step(
          () => field(v, p, "expression", pair),
          expression_steps,
          expression,
        ),
        Step(() => {
          done(
            LetExpression({
              declarations: got(declarations),
              expression: got(expression),
            }),
          )
        }),
      ]
    }
    "case" => {
      let (v, p) = payload(m, tag, path, pair)
      let expression : Ref[Node[Expression]?] = Ref(None)
      let cases : Ref[Array[Case]?] = Ref(None)
      [
        node_step(
          () => field(v, p, "expression", pair),
          expression_steps,
          expression,
        ),
        list_step(
          () => field(v, p, "cases", pair),
          (get, cell) => {
            Step(() => {
              let (cv, cp) = get()
              let pattern : Ref[Node[Pattern]?] = Ref(None)
              let body : Ref[Node[Expression]?] = Ref(None)
              [
                node_step(
                  () => field(cv, cp, "pattern", pair),
                  pattern_steps,
                  pattern,
                ),
                node_step(
                  () => field(cv, cp, "expression", pair),
                  expression_steps,
                  body,
                ),
                Step(() => {
                  cell.val = Some(
                    ({ pattern: got(pattern), expression: got(body), } : Case),
                  )
                  []
                }),
              ]
            })
          },
          cases,
        ),
        Step(() => {
          done(
            CaseExpression({ expression: got(expression), cases: got(cases), }),
          )
        }),
      ]
    }
    "lambda" => {
      let (v, p) = payload(m, tag, path, pair)
      let args : Ref[Array[Node[Pattern]]?] = Ref(None)
      let expression : Ref[Node[Expression]?] = Ref(None)
      [
        pattern_list_step(() => field(v, p, "patterns", pair), args),
        node_step(
          () => field(v, p, "expression", pair),
          expression_steps,
          expression,
        ),
        Step(() => {
          done(
            LambdaExpression({ args: got(args), expression: got(expression), }),
          )
        }),
      ]
    }
    "recordAccess" => {
      let (v, p) = payload(m, tag, path, pair)
      let expression : Ref[Node[Expression]?] = Ref(None)
      [
        node_step(
          () => field(v, p, "expression", pair),
          expression_steps,
          expression,
        ),
        // The name is read after the expression, as elm-syntax does.
        Step(() => {
          done(
            RecordAccess(got(expression), field(v, p, "name", string_node_at)),
          )
        }),
      ]
    }
    "recordAccessFunction" =>
      done(RecordAccessFunction(payload(m, tag, path, string_at)))
    "record" => {
      let (v, p) = payload(m, tag, path, pair)
      let setters : Ref[Array[Node[RecordSetter]]?] = Ref(None)
      [
        record_setter_list_step(() => (v, p), setters),
        Step(() => done(RecordExpr(got(setters)))),
      ]
    }
    "recordUpdate" => {
      let (v, p) = payload(m, tag, path, pair)
      let name = field(v, p, "name", string_node_at)
      let updates : Ref[Array[Node[RecordSetter]]?] = Ref(None)
      [
        record_setter_list_step(() => field(v, p, "updates", pair), updates),
        Step(() => done(RecordUpdateExpression(name, got(updates)))),
      ]
    }
    "glsl" => done(GLSLExpression(payload(m, tag, path, string_at)))
    _ => unknown_tag(path, tag)
  }
}

///|
fn let_declaration_steps(
  j : Json,
  path : Path,
  out : Ref[LetDeclaration?],
) -> Array[Step] raise DecodeError {
  let (tag, m) = typed(j, path)
  match tag {
    "function" => {
      let (v, p) = payload(m, tag, path, pair)
      let f : Ref[Function?] = Ref(None)
      let steps = function_steps(v, p, f)
      steps.push(
        Step(() => {
          out.val = Some(LetFunction(got(f)))
          []
        }),
      )
      steps
    }
    "destructuring" => {
      let (v, p) = payload(m, tag, path, pair)
      let pattern : Ref[Node[Pattern]?] = Ref(None)
      let expression : Ref[Node[Expression]?] = Ref(None)
      [
        node_step(() => field(v, p, "pattern", pair), pattern_steps, pattern),
        node_step(
          () => field(v, p, "expression", pair),
          expression_steps,
          expression,
        ),
        Step(() => {
          out.val = Some(LetDestructuring(got(pattern), got(expression)))
          []
        }),
      ]
    }
    _ => unknown_tag(path, tag)
  }
}

///|
/// The steps of a function: the documentation now, then the signature, the
/// declaration and the function itself, in elm-syntax's order.
fn function_steps(
  j : Json,
  path : Path,
  out : Ref[Function?],
) -> Array[Step] raise DecodeError {
  let documentation = documentation_at(j, path)
  let signature : Ref[Node[Signature]??] = Ref(None)
  let declaration : Ref[Node[FunctionImplementation]?] = Ref(None)
  [
    Step(() => {
      let (v, p) = field(j, path, "signature", pair)
      match v {
        Null => {
          signature.val = Some(None)
          []
        }
        _ => {
          let present : Ref[Node[Signature]?] = Ref(None)
          [
            node_step(() => (v, p), signature_steps, present),
            Step(() => {
              signature.val = Some(Some(got(present)))
              []
            }),
          ]
        }
      }
    }),
    node_step(
      () => field(j, path, "declaration", pair),
      (v, p, impl_out) => {
        let name = field(v, p, "name", string_node_at)
        let arguments : Ref[Array[Node[Pattern]]?] = Ref(None)
        let expression : Ref[Node[Expression]?] = Ref(None)
        [
          pattern_list_step(() => field(v, p, "arguments", pair), arguments),
          node_step(
            () => field(v, p, "expression", pair),
            expression_steps,
            expression,
          ),
          Step(() => {
            impl_out.val = Some(
              (
                {
                  name,
                  arguments: got(arguments),
                  expression: got(expression),
                } : FunctionImplementation),
            )
            []
          }),
        ]
      },
      declaration,
    ),
    Step(() => {
      out.val = Some({
        documentation,
        signature: got(signature),
        declaration: got(declaration),
      })
      []
    }),
  ]
}

// ---------------------------------------------------------------------------
// Public decoders. Each one mirrors an elm-syntax `decoder`.

///|
/// Elm.Syntax.File.decoder.
///
/// It reads the JSON that elm-syntax 7.3.9 writes, and the JSON from
/// `encode_file` and `encode_file_with`. `decode_file(encode_file(f))` gives
/// `f` back, except for Int literals above 2^53 (use `exact_ints=true` for
/// those). Malformed input raises `DecodeError` with the JSON path of the
/// problem. The decoder does not recurse per AST level, so a `Json` value
/// of any depth decodes; `@json.parse` has its own `max_nesting_depth`.
///
/// ```mbt check
/// test {
///   let source = @scanner.SourceText::new(
///     "module Main exposing (main)\n\nmain =\n    \"hi\"\n",
///   )
///   let result = @parser.parse_module(source, @scanner.DefaultScanner::new())
///   guard result.ast is Some(file) else { fail("no AST") }
///   let text = @ast.encode_file(file).stringify()
///   let decoded = @ast.decode_file(@json.parse(text))
///   inspect(decoded == file, content="true")
///   // Malformed input raises an error that names the JSON path.
///   try @ast.decode_file({ "imports": [] }) catch {
///     e =>
///       inspect(
///         e,
///         content="$: Expecting an OBJECT with a field named `moduleDefinition`",
///       )
///   } noraise {
///     _ => fail("expected a DecodeError")
///   }
/// }
/// ```
pub fn decode_file(json : Json) -> File raise DecodeError {
  decode_with(json, Root, file_steps)
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
  decode_with(json, Root, declaration_steps)
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
  decode_with(json, Root, signature_steps)
}

///|
/// Elm.Syntax.TypeAlias.decoder.
pub fn decode_type_alias(json : Json) -> TypeAlias raise DecodeError {
  decode_with(json, Root, type_alias_steps)
}

///|
/// Elm.Syntax.Type.decoder.
pub fn decode_type(json : Json) -> Type raise DecodeError {
  decode_with(json, Root, type_steps)
}

///|
/// Elm.Syntax.Type.valueConstructorDecoder.
pub fn decode_value_constructor(
  json : Json,
) -> ValueConstructor raise DecodeError {
  decode_with(json, Root, value_constructor_steps)
}

///|
/// Elm.Syntax.TypeAnnotation.decoder.
pub fn decode_type_annotation(json : Json) -> TypeAnnotation raise DecodeError {
  decode_with(json, Root, type_annotation_steps)
}

///|
/// Elm.Syntax.Pattern.decoder.
pub fn decode_pattern(json : Json) -> Pattern raise DecodeError {
  decode_with(json, Root, pattern_steps)
}

///|
/// Elm.Syntax.Expression.decoder.
pub fn decode_expression(json : Json) -> Expression raise DecodeError {
  decode_with(json, Root, expression_steps)
}

///|
/// Elm.Syntax.Expression.functionDecoder.
pub fn decode_function(json : Json) -> Function raise DecodeError {
  decode_with(json, Root, function_steps)
}
