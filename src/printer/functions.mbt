///|
/// A doc comment as it is. It must start with `{-|` and end with `-}`.
fn documentation_doc(
  path : @syntax.NodePath,
  text : String,
) -> @pretty.Doc raise PrintError {
  guard text.length() >= 5 && text.has_prefix("{-|") && text.has_suffix("-}") else {
    raise PrintError(path~, problem=InvalidDocumentation)
  }
  @pretty.verbatim(text)
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
  @pretty.group(
    self.lower_name(path.child("name", 0), s.name.value) +
    @pretty.text(" :") +
    @pretty.nest(
      4,
      @pretty.line() +
      self.arrow_chain(
        path.child("typeAnnotation", 0),
        level + 1,
        s.type_annotation,
      ),
    ),
  )
}

///|
/// Documentation, signature and `name args =` with the body on the next
/// line, indented by 4. Fields: `documentation`, `signature`, `declaration`.
/// A `let` uses `function_plan` (one work stack for the whole expression);
/// top-level function declarations use this entry.
#warnings("-unused_value")
fn Ctx::function_doc(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  f : @ast.Function,
) -> @pretty.Doc raise PrintError {
  self.run(self.function_plan(path, level, f))
}

///|
/// The work items of `function_doc`, in the order it checks them: the
/// documentation, the signature, the name, the arguments, the body.
fn Ctx::function_plan(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  f : @ast.Function,
) -> Work {
  let parts = []
  let has_doc = f.documentation is Some(_)
  let has_sig = f.signature is Some(_)
  if f.documentation is Some(doc) {
    parts.push(
      Leaf(() => documentation_doc(path.child("documentation", 0), doc.value)),
    )
  }
  if f.signature is Some(sig) {
    parts.push(
      Leaf(() => {
        self.signature_doc(path.child("signature", 0), level + 1, sig.value)
      }),
    )
  }
  let p = path.child("declaration", 0)
  let imp = f.declaration.value
  parts.push(Leaf(() => self.lower_name(p.child("name", 0), imp.name.value)))
  for i, a in imp.arguments {
    parts.push(
      Leaf(() => {
        self.pattern_doc(p.child("arguments", i), level + 1, a, PatternArg)
      }),
    )
  }
  parts.push(Expr(p.child("expression", 0), level + 1, imp.expression, AnyExpr))
  Plan(parts, docs => {
    let mut d = @pretty.empty()
    let mut k = 0
    if has_doc {
      d = d + docs[k] + @pretty.hardline()
      k = k + 1
    }
    if has_sig {
      d = d + docs[k] + @pretty.hardline()
      k = k + 1
    }
    let last = docs.length() - 1
    let mut head = docs[k]
    for i in (k + 1)..<last {
      head = head + @pretty.text(" ") + docs[i]
    }
    d +
    head +
    @pretty.text(" =") +
    @pretty.nest(4, @pretty.hardline() + docs[last])
  })
}
