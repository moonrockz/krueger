///|
/// A random AST built directly, not parsed; every range is zero. Edge
/// values: operator applications without the parentheses that precedence
/// needs (every standard operator: left, right and non-associative, mixed
/// associativity at one precedence); lambdas, `if`, `case` and `let` as
/// operands and arguments; applications in function position; negations
/// of negations; negative Int, Hex and Float literals, `-0.0` and the
/// largest Int; record access on numbers, constructors and record access
/// functions; strings and chars with quotes, backslashes, control
/// characters and surrogate pairs; nested constructor, `::` and `as`
/// patterns; nested function types and type applications. All names are
/// valid, so the printer never raises. Depth is bounded by `size`.
pub(all) struct ElmAst(@ast.File) derive(Debug)

///|
/// The file of the generated value.
pub fn ElmAst::file(self : ElmAst) -> @ast.File {
  let ElmAst(f) = self
  f
}

///|
pub impl @quickcheck.Arbitrary for ElmAst with fn arbitrary(size, rs) {
  ElmAst(gen_ast_file(size, rs))
}

///|
pub impl @quickcheck.Shrink for ElmAst

///|
let zero_range : @ast.Range = {
  start: { row: 0, column: 0, },
  end: { row: 0, column: 0, },
}

///|
fn[T] at0(value : T) -> @ast.Node[T] {
  { range: zero_range, value, }
}

///|
/// The standard operators with the directions of the operator table.
let ast_operators : Array[(String, @ast.InfixDirection)] = [
  ("+", Left),
  ("-", Left),
  ("*", Left),
  ("//", Left),
  ("++", Right),
  ("::", Right),
  ("|>", Left),
  ("<|", Right),
  ("==", Non),
  ("<", Non),
  ("&&", Right),
  ("||", Right),
  ("^", Right),
  ("<<", Left),
  (">>", Right),
  ("|.", Left),
  ("|=", Left),
  ("</>", Right),
  ("<?>", Left),
]

///|
fn gen_ast_leaf(rs : @splitmix.RandomState) -> @ast.Expression {
  match pick(rs, 13) {
    0 => UnitExpr
    1 => FunctionOrValue([][:], "x")
    2 => FunctionOrValue(["List"][:], "map")
    3 => FunctionOrValue([][:], "Just")
    4 => Integer([0L, 7L, -3L, 9223372036854775807L][pick(rs, 4)])
    5 => Hex([0L, 255L, 65536L, -16L][pick(rs, 4)])
    6 => Floatable([0.0, 1.5, -2.25, 1.0e21, 5.0e-324, -0.0, 0.1][pick(rs, 7)])
    7 =>
      Literal(
        ["", "a\"b\\c", "line\nnext\ttab", "é😀", "\u{7}\r"][pick(rs, 5)],
      )
    8 => CharLiteral(['a', '\'', '"', '\n', '😀'][pick(rs, 5)])
    9 => RecordAccessFunction(".f")
    10 => PrefixOperator("+")
    11 => ListExpr([][:])
    _ => FunctionOrValue([][:], "y")
  }
}

///|
fn gen_ast_expr(
  size : Int,
  rs : @splitmix.RandomState,
) -> @ast.Node[@ast.Expression] {
  if size <= 0 {
    return at0(gen_ast_leaf(rs))
  }
  let s = size / 2
  let e : @ast.Expression = match pick(rs, 16) {
    0 | 1 => {
      let (symbol, direction) = ast_operators[pick(rs, ast_operators.length())]
      OperatorApplication(
        symbol,
        direction,
        gen_ast_expr(s, rs),
        gen_ast_expr(s, rs),
      )
    }
    2 =>
      Application(
        [gen_ast_expr(s, rs), gen_ast_expr(s, rs), gen_ast_expr(s, rs)][:],
      )
    3 => IfBlock(gen_ast_expr(s, rs), gen_ast_expr(s, rs), gen_ast_expr(s, rs))
    4 => Negation(gen_ast_expr(s, rs))
    5 => TupledExpression([gen_ast_expr(s, rs), gen_ast_expr(s, rs)][:])
    6 => ParenthesizedExpression(gen_ast_expr(s, rs))
    7 =>
      LetExpression({
        declarations: [
          at0(@ast.LetDeclaration::LetFunction(gen_ast_function("y", s, rs))),
          at0(
            @ast.LetDeclaration::LetDestructuring(
              gen_arg_pattern(rs),
              gen_ast_expr(s, rs),
            ),
          ),
        ][:],
        expression: gen_ast_expr(s, rs),
      })
    8 =>
      CaseExpression({
        expression: gen_ast_expr(s, rs),
        cases: [
          @ast.Case::{
            pattern: gen_ast_pattern(s, rs),
            expression: gen_ast_expr(s, rs),
          },
          @ast.Case::{
            pattern: at0(@ast.Pattern::AllPattern),
            expression: gen_ast_expr(s, rs),
          },
        ][:],
      })
    9 =>
      LambdaExpression({
        args: [at0(@ast.Pattern::VarPattern("z")), gen_arg_pattern(rs)][:],
        expression: gen_ast_expr(s, rs),
      })
    10 =>
      RecordExpr(
        [
          at0(@ast.RecordSetter::{
            field: at0("a"),
            expression: gen_ast_expr(s, rs),
          }),
          at0(@ast.RecordSetter::{
            field: at0("b"),
            expression: gen_ast_expr(s, rs),
          }),
        ][:],
      )
    11 => ListExpr([gen_ast_expr(s, rs), gen_ast_expr(s, rs)][:])
    12 => RecordAccess(gen_ast_expr(s, rs), at0("f"))
    13 =>
      RecordUpdateExpression(
        at0("r"),
        [
          at0(@ast.RecordSetter::{
            field: at0("a"),
            expression: gen_ast_expr(s, rs),
          }),
        ][:],
      )
    _ =>
      Application(
        [at0(@ast.Expression::FunctionOrValue([][:], "f")), gen_ast_expr(s, rs)][:],
      )
  }
  at0(e)
}

///|
/// A pattern for a case branch.
fn gen_ast_pattern(
  size : Int,
  rs : @splitmix.RandomState,
) -> @ast.Node[@ast.Pattern] {
  if size <= 0 {
    let p : @ast.Pattern = match pick(rs, 7) {
      0 => AllPattern
      1 => UnitPattern
      2 => VarPattern("p")
      3 => IntPattern(7L)
      4 => HexPattern(255L)
      5 => CharPattern('\'')
      _ => StringPattern("q\"")
    }
    return at0(p)
  }
  let s = size / 2
  let p : @ast.Pattern = match pick(rs, 8) {
    0 => TuplePattern([gen_ast_pattern(s, rs), gen_ast_pattern(s, rs)][:])
    1 => RecordPattern([at0("a"), at0("b")][:])
    2 => UnConsPattern(gen_ast_pattern(s, rs), gen_ast_pattern(s, rs))
    3 => ListPattern([gen_ast_pattern(s, rs)][:])
    4 =>
      NamedPattern(
        { module_name: [][:], name: "Just", },
        [gen_ast_pattern(s, rs)][:],
      )
    5 => AsPattern(gen_ast_pattern(s, rs), at0("all"))
    6 => ParenthesizedPattern(gen_ast_pattern(s, rs))
    _ => NamedPattern({ module_name: ["Maybe"][:], name: "Nothing", }, [][:])
  }
  at0(p)
}

///|
/// A pattern for a function or lambda argument or a let destructuring.
fn gen_arg_pattern(rs : @splitmix.RandomState) -> @ast.Node[@ast.Pattern] {
  let p : @ast.Pattern = match pick(rs, 6) {
    0 => VarPattern("p")
    1 => AllPattern
    2 => UnitPattern
    3 =>
      TuplePattern(
        [at0(@ast.Pattern::VarPattern("a")), at0(@ast.Pattern::VarPattern("b"))][:],
      )
    4 => RecordPattern([at0("a")][:])
    _ =>
      NamedPattern(
        { module_name: [][:], name: "Wrap", },
        [at0(@ast.Pattern::VarPattern("w"))][:],
      )
  }
  at0(p)
}

///|
fn gen_ast_type(
  size : Int,
  rs : @splitmix.RandomState,
) -> @ast.Node[@ast.TypeAnnotation] {
  if size <= 0 {
    let t : @ast.TypeAnnotation = match pick(rs, 4) {
      0 => GenericType("a")
      1 => Unit
      2 => Typed(at0(([][:], "Int")), [][:])
      _ =>
        Typed(
          at0((["Dict"][:], "Dict")),
          [
            at0(@ast.TypeAnnotation::GenericType("k")),
            at0(@ast.TypeAnnotation::GenericType("v")),
          ][:],
        )
    }
    return at0(t)
  }
  let s = size / 2
  let t : @ast.TypeAnnotation = match pick(rs, 5) {
    0 => Typed(at0(([][:], "Maybe")), [gen_ast_type(s, rs)][:])
    1 => FunctionTypeAnnotation(gen_ast_type(s, rs), gen_ast_type(s, rs))
    2 => Tupled([gen_ast_type(s, rs), gen_ast_type(s, rs)][:])
    3 =>
      Record(
        [
          at0(@ast.RecordField::{
            name: at0("a"),
            type_annotation: gen_ast_type(s, rs),
          }),
        ][:],
      )
    _ =>
      GenericRecord(
        at0("r"),
        at0(
          [
            at0(@ast.RecordField::{
              name: at0("b"),
              type_annotation: gen_ast_type(s, rs),
            }),
          ][:],
        ),
      )
  }
  at0(t)
}

///|
fn gen_ast_function(
  name : String,
  size : Int,
  rs : @splitmix.RandomState,
) -> @ast.Function {
  let args = []
  for _ in 0..<pick(rs, 3) {
    args.push(gen_arg_pattern(rs))
  }
  {
    documentation: None,
    signature: if pick(rs, 2) == 0 {
      Some(
        at0(@ast.Signature::{
          name: at0(name),
          type_annotation: gen_ast_type(size / 2, rs),
        }),
      )
    } else {
      None
    },
    declaration: at0(@ast.FunctionImplementation::{
      name: at0(name),
      arguments: args[:],
      expression: gen_ast_expr(size, rs),
    }),
  }
}

///|
fn gen_ast_file(size : Int, rs : @splitmix.RandomState) -> @ast.File {
  let decls : Array[@ast.Node[@ast.Declaration]] = []
  for i in 0..<(1 + pick(rs, 3)) {
    decls.push(
      at0(
        @ast.Declaration::FunctionDeclaration(
          gen_ast_function("f" + i.to_string(), size, rs),
        ),
      ),
    )
  }
  if pick(rs, 2) == 0 {
    decls.push(
      at0(
        @ast.Declaration::AliasDeclaration({
          documentation: None,
          name: at0("Alias"),
          generics: [at0("a")][:],
          type_annotation: gen_ast_type(size, rs),
        }),
      ),
    )
  }
  if pick(rs, 2) == 0 {
    decls.push(
      at0(
        @ast.Declaration::CustomTypeDeclaration({
          documentation: None,
          name: at0("Custom"),
          generics: [][:],
          constructors: [
            at0(@ast.ValueConstructor::{ name: at0("One"), arguments: [][:], }),
            at0(@ast.ValueConstructor::{
              name: at0("Two"),
              arguments: [
                gen_ast_type(size / 2, rs),
                gen_ast_type(size / 2, rs),
              ][:],
            }),
          ][:],
        }),
      ),
    )
  }
  {
    module_definition: at0(
      @ast.Module::NormalModule({
        module_name: at0(["Main"][:]),
        exposing_list: at0(@ast.Exposing::All(zero_range)),
      }),
    ),
    imports: [
      at0(@ast.Import::{
        module_name: at0(["Dict"][:]),
        module_alias: None,
        exposing_list: None,
      }),
    ][:],
    declarations: decls[:],
    comments: [][:],
  }
}
