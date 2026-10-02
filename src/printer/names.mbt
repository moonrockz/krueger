///|
/// The reserved words of Elm 0.19.1 (the scanner's `KeywordKind`).
let reserved : Array[String] = [
  "module", "exposing", "import", "as", "type", "if", "then", "else", "let", "in",
  "case", "of", "port", "where",
]

///|
fn is_name(s : String, start : (Char) -> Bool) -> Bool {
  let mut first = true
  for c in s {
    if first {
      if !start(c) {
        return false
      }
      first = false
    } else if !@scanner.is_name_part(c) {
      return false
    }
  }
  !first
}

///|
fn Ctx::is_lower(self : Ctx, s : String) -> Bool {
  is_name(s, @scanner.is_lower_start) &&
  !reserved.contains(s) &&
  !self.dialect.reserved_words.contains(s)
}

///|
fn is_upper(s : String) -> Bool {
  is_name(s, @scanner.is_upper_start)
}

///|
fn Ctx::lower_name(
  self : Ctx,
  path : @syntax.NodePath,
  s : String,
) -> @pretty.Doc raise PrintError {
  guard self.is_lower(s) else {
    raise PrintError(path~, problem=InvalidName(Lower, s))
  }
  @pretty.text(s)
}

///|
fn upper_name(
  path : @syntax.NodePath,
  s : String,
) -> @pretty.Doc raise PrintError {
  guard is_upper(s) else {
    raise PrintError(path~, problem=InvalidName(Upper, s))
  }
  @pretty.text(s)
}

///|
/// An operator symbol in a prefix operator, an exposing list or an infix
/// declaration. Elm 0.19 has no user-defined operators, so a symbol is
/// valid only when the dialect's operator table has it.
fn Ctx::operator_symbol(
  self : Ctx,
  path : @syntax.NodePath,
  s : String,
) -> String raise PrintError {
  guard self.dialect.operator(s) is Some(_) else {
    raise PrintError(path~, problem=InvalidName(Operator, s))
  }
  s
}

///|
/// `Html.Events` from its segments.
fn module_name(
  path : @syntax.NodePath,
  segments : ArrayView[String],
) -> String raise PrintError {
  guard !segments.is_empty() else {
    raise PrintError(path~, problem=EmptyModuleName)
  }
  let out = StringBuilder()
  for i, s in segments {
    guard is_upper(s) else {
      raise PrintError(path~, problem=InvalidName(Upper, s))
    }
    if i > 0 {
      out.write_char('.')
    }
    out.write_string(s)
  }
  out.to_string()
}

///|
/// A value or constructor reference: `x`, `Just`, `List.map`.
fn Ctx::qualified_value(
  self : Ctx,
  path : @syntax.NodePath,
  module_ : ArrayView[String],
  name : String,
) -> @pretty.Doc raise PrintError {
  guard self.is_lower(name) || is_upper(name) else {
    raise PrintError(path~, problem=InvalidName(Lower, name))
  }
  if module_.is_empty() {
    @pretty.text(name)
  } else {
    @pretty.text(module_name(path, module_) + "." + name)
  }
}

///|
/// A type or constructor-pattern reference: `Maybe`, `Dict.Dict`.
fn qualified_upper(
  path : @syntax.NodePath,
  module_ : ArrayView[String],
  name : String,
) -> @pretty.Doc raise PrintError {
  guard is_upper(name) else {
    raise PrintError(path~, problem=InvalidName(Upper, name))
  }
  if module_.is_empty() {
    @pretty.text(name)
  } else {
    @pretty.text(module_name(path, module_) + "." + name)
  }
}

///|
/// The dialect's entry for an operator.
fn Ctx::operator_def(
  self : Ctx,
  path : @syntax.NodePath,
  symbol : String,
) -> @dialect.OperatorDef raise PrintError {
  match self.dialect.operator(symbol) {
    Some(def) => def
    None => raise PrintError(path~, problem=UnknownOperator(symbol))
  }
}
