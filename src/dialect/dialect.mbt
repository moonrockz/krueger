///|
/// A rejection rule: one class of syntax that a dialect rejects. A rule only
/// runs when the dialect enables it.
///
/// A diagnostic from a rule names it as `[rule: <name>]` (see `Rule::name`).
/// `Dialect::has` tells whether a dialect enables a rule.
///
/// ```mbt check
/// test {
///   let elm = @dialect.Dialect::elm_0_19_1()
///   let oracle = @dialect.Dialect::elm_syntax_7_3_9()
///   // Both reject a char literal with two characters.
///   inspect(elm.has(CharLength) && oracle.has(CharLength), content="true")
///   // Only `elm make` rejects `007`.
///   inspect(elm.has(LeadingZero), content="true")
///   inspect(oracle.has(LeadingZero), content="false")
///   inspect(@dialect.Rule::LeadingZero.name(), content="leading-zero")
/// }
/// ```
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
  ImportColumn
  NonAsciiDigitInName
  TitlecaseNameStart
  EffectModule
  InfixDeclaration
  DuplicateEffectKey
  PortInNormalModule
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
    ImportColumn => "import-column"
    NonAsciiDigitInName => "non-ascii-digit-in-name"
    TitlecaseNameStart => "titlecase-name-start"
    EffectModule => "effect-module"
    InfixDeclaration => "infix-declaration"
    DuplicateEffectKey => "duplicate-effect-key"
    PortInNormalModule => "port-in-normal-module"
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
///
/// Build the scanner and the parser with the same dialect. To make a custom
/// dialect, start from a built-in one. This one adds an operator `<=>`. The
/// operator needs an entry in `operators` (for the parser) and in
/// `operator_symbols` (for the lexer, which otherwise reads `<=` and `>`):
///
/// ```mbt check
/// test {
///   let base = @dialect.Dialect::elm_0_19_1()
///   let dialect = {
///     ..base,
///     name: "my-elm",
///     operators: [
///       ..base.operators,
///       { symbol: "<=>", precedence: 4, direction: Non, },
///     ],
///     operator_symbols: ["<=>"],
///   }
///   inspect(dialect.validate().length(), content="0")
///   let source = @scanner.SourceText::new(
///     "module Main exposing (..)\n\nx =\n    a <=> b\n",
///   )
///   let plain = @parser.parse_module(
///     source,
///     @scanner.DefaultScanner::new(dialect=base),
///     dialect=base,
///   )
///   inspect(plain.diagnostics[0].title, content="UNKNOWN OPERATOR")
///   let custom = @parser.parse_module(
///     source,
///     @scanner.DefaultScanner::new(dialect~),
///     dialect~,
///   )
///   inspect(custom.diagnostics.length(), content="0")
/// }
/// ```
///
/// An extra reserved word stops a name from being used. To turn a rule off,
/// give the dialect a new rule set; do not change the set of the base:
///
/// ```mbt check
/// test {
///   let base = @dialect.Dialect::elm_0_19_1()
///   let rules = base.rules.copy()
///   rules.remove(LeadingZero)
///   let dialect = { ..base, rules, reserved_words: ["forall"], }
///   inspect(base.has(LeadingZero), content="true")
///   inspect(dialect.has(LeadingZero), content="false")
///   let parse = (text : String) => {
///     @parser.parse_module(
///       @scanner.SourceText::new(text),
///       @scanner.DefaultScanner::new(dialect~),
///       dialect~,
///     ).diagnostics
///   }
///   inspect(parse("module Main exposing (..)\n\nx = 007\n").length(), content="0")
///   let errors = parse("module Main exposing (..)\n\nforall = 1\n")
///   inspect(
///     errors[0].message,
///     content="Malformed function declaration: expected a function name, found `forall`",
///   )
/// }
/// ```
pub(all) struct Dialect {
  name : String
  rules : @hashset.HashSet[Rule]
  operators : Array[OperatorDef]
  reserved_words : Array[String]
  operator_symbols : Array[String]
  attributes : AttributeSyntax
  /// Whether the file belongs to an `elm/*` or `elm-explorations/*` package.
  /// `elm make` lets only
  /// those declare infix operators and effect modules.
  core_package : Bool
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
    core_package: false,
  }
}

///|
/// The default dialect: rejects what `elm make` 0.19.1 rejects as syntax.
///
/// It enables every rule except `TitlecaseNameStart`, has the standard
/// operator table, and reads doc-comment attributes. `core_package` is
/// `false`, so effect modules and infix declarations are errors.
///
/// ```mbt check
/// test {
///   let dialect = @dialect.Dialect::elm_0_19_1()
///   inspect(dialect.name, content="elm-0.19.1")
///   inspect(dialect.has(PortInNormalModule), content="true")
///   debug_inspect(
///     dialect.operator("|>"),
///     content=(
///       #|Some({ symbol: "|>", precedence: 1, direction: Left })
///     ),
///   )
/// }
/// ```
pub fn Dialect::elm_0_19_1() -> Dialect {
  standard(
    "elm-0.19.1",
    [
      ..shared_rules(),
      LeadingZero,
      UppercaseHexPrefix,
      ExponentWithoutDigits,
      BadUnicodeEscape,
      ImportColumn,
      NonAsciiDigitInName,
      EffectModule,
      InfixDeclaration,
      DuplicateEffectKey,
      PortInNormalModule,
    ],
  )
}

///|
/// Rejects exactly what elm-syntax 7.3.9 rejects.
///
/// Use it to compare output with elm-syntax: the parity harness scores in
/// this dialect. It accepts some syntax that `elm make` rejects, for example
/// `007`, `0X1F` and `1e`.
///
/// ```mbt check
/// test {
///   let source = @scanner.SourceText::new(
///     "module Main exposing (..)\n\nx =\n    0X1F\n",
///   )
///   let parse = (dialect : @dialect.Dialect) => {
///     @parser.parse_module(
///       source,
///       @scanner.DefaultScanner::new(dialect~),
///       dialect~,
///     ).diagnostics.length()
///   }
///   inspect(parse(@dialect.Dialect::elm_syntax_7_3_9()), content="0")
///   inspect(parse(@dialect.Dialect::elm_0_19_1()), content="1")
/// }
/// ```
pub fn Dialect::elm_syntax_7_3_9() -> Dialect {
  standard("elm-syntax-7.3.9", [..shared_rules(), TitlecaseNameStart])
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

///|
/// Problems with the dialect's extension data, as messages (empty when it is
/// valid). The scanner and parser do not check these; call this when a
/// dialect comes from outside (a config file, a CLI flag).
pub fn Dialect::validate(self : Dialect) -> Array[String] {
  let problems = []
  let seen : Array[String] = []
  for op in self.operators {
    if op.symbol == "" {
      problems.push("an operator has an empty symbol")
      continue
    }
    if seen.contains(op.symbol) {
      problems.push("operator `\{op.symbol}` is defined twice")
    }
    seen.push(op.symbol)
    if op.precedence < 1 || op.precedence > 9 {
      problems.push(
        "operator `\{op.symbol}` has precedence \{op.precedence}; precedences are 1 to 9",
      )
    }
  }
  for symbol in self.operator_symbols {
    match symbol.get_char(0) {
      None => problems.push("operator symbol `` is empty")
      Some(c) =>
        if !"+-/*=.<>:&|^?".contains_char(c) {
          problems.push(
            "operator symbol `\{symbol}` does not start with a symbol character",
          )
        } else if symbol.has_prefix("--") {
          problems.push("operator symbol `\{symbol}` starts a line comment")
        }
    }
  }
  for word in self.reserved_words {
    if ["alias", "infix", "effect"].contains(word) {
      problems.push(
        "reserved word `\{word}` is a name the parser reads by its text",
      )
    }
  }
  problems
}
