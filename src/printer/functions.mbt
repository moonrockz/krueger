///|
/// A doc comment, with its Markdown and code as elm-format writes them
/// (see `format_documentation`). It must start with `{-|` and end with
/// `-}`.
fn Ctx::documentation_doc(
  self : Ctx,
  path : @syntax.NodePath,
  text : String,
) -> @pretty.Doc raise PrintError {
  guard text.length() >= 5 && text.has_prefix("{-|") && text.has_suffix("-}") else {
    raise PrintError(path~, problem=InvalidDocumentation)
  }
  @pretty.verbatim(format_documentation(text, self.dialect, self.doc_depth))
}

///|
/// `name : type`; when it breaks, the type goes on the next lines with each
/// `->` at the start of a line (elm-format).
fn Ctx::signature_doc(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  s : @ast.Signature,
) -> @pretty.Doc raise PrintError {
  let moved = self.after_token(s.name.range)
  let name = self.with_comments(
    s.name.range,
    self.lower_name(path.child("name", 0), s.name.value),
  )
  let chain = self.arrow_chain(
    path.child("typeAnnotation", 0),
    level + 1,
    s.type_annotation,
  )
  // elm-format ElmStructure.definition ":" False: the type goes on the
  // next line when it is multi-line; its arrows break on their own
  // (`Ctx::arrow_chain`).
  let chain = match self.layout {
    Width(_) => chain
    ElmFormat => @pretty.group(chain)
  }
  @pretty.group(
    name +
    self.separator(s.name.range, " :", moved) +
    @pretty.nest(4, @pretty.line() + chain),
  )
}

///|
/// Documentation, signature and `name args =` with the body on the next
/// line, indented by 4. Fields: `documentation`, `signature`, `declaration`.
/// A `let` uses `function_plan` (one work stack for the whole expression);
/// top-level function declarations use this entry.
fn Ctx::function_doc(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  f : @ast.Function,
) -> @pretty.Doc raise PrintError {
  self.run(self.function_plan(path, level, f))
}

///|
/// A part of a function declaration: the documentation, the signature or
/// the implementation, or the comments between them.
priv enum FunctionPart {
  Main
  Between(Int)
}

///|
/// The work items of `function_doc`, in the order it checks them: the
/// documentation, the signature, the name, the arguments, the body. Elm has
/// no doc comments in a `let` (`in_let = true`), so documentation there
/// raises `LetDocumentation`.
///
/// The comments between the documentation, the signature and the
/// implementation go on their own lines. At the top level they are blocks
/// between blank lines, as elm-format makes them body comments
/// (`formatTopLevelBody`).
fn Ctx::function_plan(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  f : @ast.Function,
  in_let? : Bool = false,
) -> Work {
  let parts = []
  let kinds = []
  // Whether each block of comments has comments, set when its item runs.
  let found = [false, false, false]
  let comments = (k : Int, take : () -> Array[@ast.Node[String]]) => {
    kinds.push(Between(k))
    parts.push(
      Leaf(() => {
        let cs = take()
        found[k] = !cs.is_empty()
        comment_block(cs)
      }),
    )
  }
  if f.documentation is Some(doc) {
    let p = path.child("documentation", 0)
    kinds.push(Main)
    parts.push(
      Leaf(() => {
        if in_let {
          raise PrintError(path=p, problem=LetDocumentation)
        }
        self.documentation_doc(p, doc.value) + self.trailing(doc.range)
      }),
    )
  }
  if f.signature is Some(sig) {
    comments(0, () => self.take(Leading, sig.range))
    kinds.push(Main)
    parts.push(
      Leaf(() => {
        self.signature_doc(path.child("signature", 0), level + 1, sig.value)
      }),
    )
    comments(1, () => self.take(Trailing, sig.range))
  }
  let p = path.child("declaration", 0)
  let imp = f.declaration
  comments(2, () => self.take(Leading, imp.range))
  let name = imp.value.name
  let args = imp.value.arguments
  let head_start = parts.length()
  kinds.push(Main)
  parts.push(
    Leaf(() => {
      let moved = if args.is_empty() {
        self.after_token(name.range)
      } else {
        []
      }
      self.with_comments(
        name.range,
        self.lower_name(p.child("name", 0), name.value),
      ) +
      self.separator(
        name.range,
        if args.is_empty() {
          " ="
        } else {
          " "
        },
        moved,
      )
    }),
  )
  for i, a in args {
    parts.push(
      Leaf(() => {
        let last = i + 1 == args.length()
        let moved = if last { self.after_token(a.range) } else { [] }
        @pretty.nest(
          4,
          self.pattern_doc(p.child("arguments", i), level + 1, a, PatternArg) +
          self.separator(a.range, if last { " =" } else { " " }, moved),
        )
      }),
    )
  }
  parts.push(
    Expr(p.child("expression", 0), level + 1, imp.value.expression, AnyExpr),
  )
  Plan(parts, docs => {
    // The head and the body are one main part.
    let mut head = @pretty.empty()
    for i in head_start..<(docs.length() - 1) {
      head = head + docs[i]
    }
    let main = head +
      @pretty.nest(4, @pretty.hardline() + docs[docs.length() - 1])
    let mut d = @pretty.empty()
    let mut previous : FunctionPart? = None
    for i, kind in kinds {
      let doc = if i + 1 == kinds.length() { main } else { docs[i] }
      match kind {
        Between(k) if !found[k] => continue
        _ => ()
      }
      let breaks = match (previous, kind) {
        (None, _) => 0
        (Some(Main), Between(_)) if !in_let => 4
        (Some(Between(_)), Main) if !in_let => 3
        _ => 1
      }
      d = d + line_breaks(breaks) + doc
      previous = Some(kind)
    }
    d
  })
}
