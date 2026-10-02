///|
/// The Elm source of a type annotation, laid out in `width` columns where
/// elm-format allows a choice. Parentheses are added where precedence needs
/// them. Raises `PrintError` when the type cannot print as valid Elm; the
/// error's path starts at `t`.
///
/// ```mbt check
/// test {
///   let r : @ast.Range = {
///     start: { row: 0, column: 0, },
///     end: { row: 0, column: 0, },
///   }
///   let a : @ast.Node[@ast.TypeAnnotation] = {
///     range: r,
///     value: GenericType("a"),
///   }
///   let maybe : @ast.Node[@ast.TypeAnnotation] = {
///     range: r,
///     value: Typed({ range: r, value: ([][:], "Maybe"), }, [a][:]),
///   }
///   let list : @ast.Node[@ast.TypeAnnotation] = {
///     range: r,
///     value: Typed({ range: r, value: ([][:], "List"), }, [maybe][:]),
///   }
///   inspect(@printer.print_type_annotation(list), content="List (Maybe a)")
/// }
/// ```
pub fn print_type_annotation(
  t : @ast.Node[@ast.TypeAnnotation],
  width? : Int = 120,
  dialect? : @dialect.Dialect = @dialect.Dialect::elm_0_19_1(),
) -> String raise PrintError {
  let ctx : Ctx = { dialect, }
  @pretty.render(ctx.type_doc(@syntax.NodePath::root(), 0, t, AnyType), width~)
}

///|
/// The Elm source of a pattern. Raises `PrintError` for a pattern that Elm
/// cannot write (a negative number, a bad name, a tuple with one item); the
/// error's path starts at `p`.
pub fn print_pattern(
  p : @ast.Node[@ast.Pattern],
  width? : Int = 120,
  dialect? : @dialect.Dialect = @dialect.Dialect::elm_0_19_1(),
) -> String raise PrintError {
  let ctx : Ctx = { dialect, }
  @pretty.render(
    ctx.pattern_doc(@syntax.NodePath::root(), 0, p, AnyPattern),
    width~,
  )
}

///|
/// The Elm source of an expression. Parentheses are added where
/// precedence needs them; parentheses in the AST stay. `if`, `case` and
/// `let` are always multi-line (elm-format). Raises `PrintError` for an
/// expression that cannot print as valid Elm; the error's path starts at
/// `e`.
///
/// ```mbt check
/// test {
///   let r : @ast.Range = {
///     start: { row: 0, column: 0, },
///     end: { row: 0, column: 0, },
///   }
///   fn v(name : String) -> @ast.Node[@ast.Expression] {
///     { range: r, value: FunctionOrValue([][:], name), }
///   }
///   let sum : @ast.Node[@ast.Expression] = {
///     range: r,
///     value: OperatorApplication("+", Left, v("a"), v("b")),
///   }
///   let product : @ast.Node[@ast.Expression] = {
///     range: r,
///     value: OperatorApplication("*", Left, sum, v("c")),
///   }
///   inspect(@printer.print_expression(product), content="(a + b) * c")
/// }
/// ```
pub fn print_expression(
  e : @ast.Node[@ast.Expression],
  width? : Int = 120,
  dialect? : @dialect.Dialect = @dialect.Dialect::elm_0_19_1(),
) -> String raise PrintError {
  let ctx : Ctx = { dialect, }
  @pretty.render(ctx.expr_doc(@syntax.NodePath::root(), 0, e, AnyExpr), width~)
}
