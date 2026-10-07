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
  range? : @ast.Range? = None,
) -> @pretty.Doc raise PrintError {
  // elm-format Box.hs formatTypeAnnotation: the comments between the name
  // and the `:` follow the name (`formatTailCommented`). When one of them
  // is not one line, the name, each comment, the `:` (indented by 4) and
  // the type (indented by 4) go on lines of their own.
  let colon = self.token_after(s.name.range.end)
  let name_post = self.take_if(Trailing, s.name.range, c => {
    is_line_comment(c) && ends_before(c, colon)
  })
  name_post.append(
    self.take_if(Leading, s.type_annotation.range, c => ends_before(c, colon)),
  )
  let moved = self.after_token(s.name.range)
  let name = self.with_comments(
    s.name.range,
    self.lower_name(path.child("name", 0), s.name.value),
  )
  // elm-format Parse/Helpers.hs separated: the last term of a function
  // type takes the line comment at the end of its line (`withEol`). After
  // another type, the comment goes after the signature. `range` is the
  // range of the signature node, which holds the trailing comments.
  let eol = match range {
    Some(r) if s.type_annotation.value is FunctionTypeAnnotation(_, _) &&
      !self.has_comment(Trailing, r, c => !is_line_comment(c)) =>
      self.take(Trailing, r)
    _ => []
  }
  let chain = self.arrow_chain(
    path.child("typeAnnotation", 0),
    level + 1,
    s.type_annotation,
    eol~,
  )
  // elm-format ElmStructure.definition ":" False: the type goes on the
  // next line when it is multi-line; its arrows break on their own
  // (`Ctx::arrow_chain`).
  let chain = match self.layout {
    Width(_) => chain
    ElmFormat => @pretty.group(chain)
  }
  if !name_post.iter().all(one_line) {
    return name +
      @pretty.hardline() +
      comment_block(name_post) +
      @pretty.nest(4, @pretty.hardline() + @pretty.text(":")) +
      comments_after(moved) +
      @pretty.nest(4, @pretty.hardline() + chain)
  }
  let name = name + comments_after(name_post)
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
        self.signature_doc(
          path.child("signature", 0),
          level + 1,
          sig.value,
          range=Some(sig.range),
        )
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
