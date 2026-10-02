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
fn Ctx::function_doc(
  self : Ctx,
  path : @syntax.NodePath,
  level : Int,
  f : @ast.Function,
) -> @pretty.Doc raise PrintError {
  let mut d = @pretty.empty()
  if f.documentation is Some(doc) {
    d = d +
      documentation_doc(path.child("documentation", 0), doc.value) +
      @pretty.hardline()
  }
  if f.signature is Some(sig) {
    d = d +
      self.signature_doc(path.child("signature", 0), level + 1, sig.value) +
      @pretty.hardline()
  }
  let p = path.child("declaration", 0)
  let imp = f.declaration.value
  let mut head = self.lower_name(p.child("name", 0), imp.name.value)
  for i, a in imp.arguments {
    head = head +
      @pretty.text(" ") +
      self.pattern_doc(p.child("arguments", i), level + 1, a, PatternArg)
  }
  d +
  head +
  @pretty.text(" =") +
  @pretty.nest(
    4,
    @pretty.hardline() +
    self.expr_doc(p.child("expression", 0), level + 1, imp.expression, AnyExpr),
  )
}
