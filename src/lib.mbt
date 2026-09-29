///|
/// elm-syntax 7.3.9 model. `Elm.Syntax.Comments.Comment` is not re-exported
/// because the scanner's `Comment` type uses the same name.
pub using @ast {
  type Location,
  type Range,
  type Node,
  type ModuleName,
  type File,
  type Module,
  type DefaultModuleData,
  type EffectModuleData,
  type Exposing,
  type TopLevelExpose,
  type ExposedType,
  type Import,
  type Declaration,
  type Function,
  type FunctionImplementation,
  type Signature,
  type Documentation,
  type TypeAlias,
  type Type,
  type ValueConstructor,
  type TypeAnnotation,
  type RecordField,
  type RecordDefinition,
  type Pattern,
  type QualifiedNameRef,
  type Expression,
  type RecordSetter,
  type LetBlock,
  type LetDeclaration,
  type Lambda,
  type CaseBlock,
  type Case,
  type Cases,
  type Infix,
  type InfixDirection,
  type DecodeError,
}

///|
pub using @scanner {
  trait Scanner,
  type Severity,
  type Position,
  type Span,
  type SourceText,
  type Diagnostic,
  type CommentKind,
  type KeywordKind,
  type Comment,
  type Trivia,
  type TokenKind,
  type Token,
  type TokenStream,
  type ScanErrorList,
}

///|
pub using @cst {
  type ModuleHeaderCst,
  type ImportCst,
  type FunctionCst,
  type TypeAliasCst,
  type UnionTypeCst,
  type DeclarationCst,
  type ModuleCst,
}

///|
pub using @parser {type ParseResult}

///|
/// Krueger — Parser and parsing utilities for Elm and Elm-like dialects (e.g. Morphir).
///
/// This module will provide scanner, parser, AST, and visitor interfaces
/// with flexibility similar to moonrockz/gherkin. Project setup only;
/// scanner/parser/AST/visitor design in a follow-up.
pub fn version() -> String {
  "0.1.0"
}

///|
pub fn tokenize(source : SourceText) -> Result[TokenStream, ScanErrorList] {
  @scanner.DefaultScanner::new().tokenize(source)
}

///|
pub fn parse_module(source : SourceText) -> ParseResult {
  @parser.parse_module(source, @scanner.DefaultScanner::new())
}

///|
pub fn parse_tokens(tokens : TokenStream) -> ParseResult {
  @parser.parse_tokens(tokens)
}
