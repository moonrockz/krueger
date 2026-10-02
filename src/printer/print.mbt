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
///
/// `UnConsPattern(a, AsPattern(b, c))` prints as `a :: b as c`, because
/// krueger and elm-syntax read that text back as the same AST. `elm make`
/// 0.19.1 and elm-format read `a :: b as c` as `(a :: b) as c`. To bind
/// only the tail, use `ParenthesizedPattern`: `a :: (b as c)`.
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

///|
/// The Elm source of a declaration, without a trailing line feed. A port's
/// doc comment is not part of its declaration (elm-syntax keeps it in
/// `File.comments`), so only `print_file` prints it.
pub fn print_declaration(
  d : @ast.Node[@ast.Declaration],
  width? : Int = 120,
  dialect? : @dialect.Dialect = @dialect.Dialect::elm_0_19_1(),
) -> String raise PrintError {
  let ctx : Ctx = { dialect, }
  @pretty.render(ctx.declaration_doc(@syntax.NodePath::root(), 0, d), width~)
}

///|
/// The Elm source of a file in the elm-format layout, ending with one line
/// feed. Fixed shapes (declaration bodies, custom types, `if`, `case`,
/// `let`) are always multi-line; other constructs stay on one line when they
/// fit in `width` columns. Prints documentation and the doc comments of
/// `File.comments` (module and port documentation), not regular comments.
/// Text inside doc comments and GLSL is written as it is, line ends
/// included: a doc comment from a CRLF source keeps its `\r\n`.
/// Raises `PrintError` for an AST that cannot print as valid Elm; the
/// error's path starts at the file.
///
/// `UnConsPattern(a, AsPattern(b, c))` prints as `a :: b as c`, which
/// `elm make` 0.19.1 and elm-format read as `(a :: b) as c` (see
/// `print_pattern`).
///
/// ```mbt check
/// test {
///   let text = "module Main exposing (main)\n\n\nmain =\n    1 + 2\n"
///   let result = @parser.parse_module(
///     @scanner.SourceText::new(text),
///     @scanner.DefaultScanner::new(),
///   )
///   inspect(@printer.print_file(result.ast.unwrap()) == text, content="true")
/// }
/// ```
pub fn print_file(
  file : @ast.File,
  width? : Int = 120,
  dialect? : @dialect.Dialect = @dialect.Dialect::elm_0_19_1(),
) -> String raise PrintError {
  let ctx : Ctx = { dialect, }
  @pretty.render(ctx.file_doc(file), width~)
}
