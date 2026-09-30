///|
/// A rejection rule: one class of syntax that a dialect rejects. A rule only
/// runs when the dialect enables it.
pub(all) enum Rule {
  LeadingZero
  EmptyHex
  BadUnicodeEscape
  CharLength
  IndentedContinuation
  LetDeclarationColumn
  ModuleLevelColumn
  SpacedOperatorName
  UppercaseHexPrefix
  ExponentWithoutDigits
} derive(Eq, Hash, Debug)

///|
/// Kebab-case name, shown in diagnostics as `[rule: <name>]`.
pub fn Rule::name(self : Rule) -> String {
  match self {
    LeadingZero => "leading-zero"
    EmptyHex => "empty-hex"
    BadUnicodeEscape => "bad-unicode-escape"
    CharLength => "char-length"
    IndentedContinuation => "indented-continuation"
    LetDeclarationColumn => "let-declaration-column"
    ModuleLevelColumn => "module-level-column"
    SpacedOperatorName => "spaced-operator-name"
    UppercaseHexPrefix => "uppercase-hex-prefix"
    ExponentWithoutDigits => "exponent-without-digits"
  }
}

///|
/// An infix operator: its symbol, precedence (1 to 9) and direction.
pub(all) struct OperatorDef {
  symbol : String
  precedence : Int
  direction : @ast.InfixDirection
} derive(Eq, Debug)

///|
/// Whether attributes in doc comments are parsed.
pub(all) enum AttributeSyntax {
  Off
  DocComment
} derive(Eq, Debug)

///|
/// A variant of Elm: which rejection rules run, and the extension data (operator
/// table, extra reserved words, extra operator symbols) the scanner and the
/// parser read. The AST shape is elm-syntax 7.3.9 in every dialect.
///
/// - An extra operator symbol must start with a character the lexer already
///   treats as a symbol (`+ - / * = . < > : & | ^ ?`) and must not start with
///   `--` (a line comment).
/// - An extra reserved word must not be `alias`, `infix` or `effect`: the
///   parser reads those by name.
/// - `{ ..d, field: value }` shares `rules` and `operators` with `d`; copy them
///   before changing either.
pub(all) struct Dialect {
  name : String
  rules : @hashset.HashSet[Rule]
  operators : Array[OperatorDef]
  reserved_words : Array[String]
  operator_symbols : Array[String]
  attributes : AttributeSyntax
}

///|
/// The infix operators of Elm 0.19.1 as elm-syntax 7.3.9 knows them, including
/// `</>` and `<?>` from elm/url.
pub fn standard_operators() -> Array[OperatorDef] {
  let table : Array[(String, Int, @ast.InfixDirection)] = [
    ("|>", 1, Left),
    ("<|", 1, Right),
    ("||", 2, Right),
    ("&&", 3, Right),
    ("==", 4, Non),
    ("/=", 4, Non),
    ("<=", 4, Non),
    (">=", 4, Non),
    (">", 4, Non),
    ("<", 4, Non),
    ("++", 5, Right),
    ("::", 5, Right),
    ("|=", 5, Left),
    ("+", 6, Left),
    ("-", 6, Left),
    ("|.", 6, Left),
    ("//", 7, Left),
    ("*", 7, Left),
    ("/", 7, Left),
    ("</>", 7, Right),
    ("<?>", 8, Left),
    ("^", 8, Right),
    (">>", 9, Right),
    ("<<", 9, Left),
  ]
  table.map(entry => {
    let (symbol, precedence, direction) = entry
    { symbol, precedence, direction, }
  })
}

///|
/// Rules both built-in dialects enable: `elm make` and elm-syntax reject
/// these.
fn shared_rules() -> Array[Rule] {
  [
    IndentedContinuation,
    LetDeclarationColumn,
    ModuleLevelColumn,
    CharLength,
    EmptyHex,
    SpacedOperatorName,
  ]
}

///|
fn standard(name : String, rules : Array[Rule]) -> Dialect {
  {
    name,
    rules: @hashset.HashSet(rules),
    operators: standard_operators(),
    reserved_words: [],
    operator_symbols: [],
    attributes: DocComment,
  }
}

///|
/// The default dialect: rejects what `elm make` 0.19.1 rejects as syntax.
pub fn Dialect::elm_0_19_1() -> Dialect {
  standard(
    "elm-0.19.1",
    [
      ..shared_rules(),
      LeadingZero,
      UppercaseHexPrefix,
      ExponentWithoutDigits,
      BadUnicodeEscape,
    ],
  )
}

///|
/// Rejects exactly what elm-syntax 7.3.9 rejects.
pub fn Dialect::elm_syntax_7_3_9() -> Dialect {
  standard("elm-syntax-7.3.9", shared_rules())
}

///|
/// Whether the dialect enables `rule`.
pub fn Dialect::has(self : Dialect, rule : Rule) -> Bool {
  self.rules.contains(rule)
}

///|
/// The operator table entry for `symbol`, if the dialect has one.
pub fn Dialect::operator(self : Dialect, symbol : String) -> OperatorDef? {
  for op in self.operators {
    if op.symbol == symbol {
      return Some(op)
    }
  }
  None
}
