///|
/// Convert a scanner position (1-based line and column) to an elm-syntax location.
fn location(position : @scanner.Position) -> @ast.Location {
  { row: position.line, column: position.column, }
}

///|
/// Range from the start of `first` to the end of `last`.
fn range_between(first : @scanner.Span, last : @scanner.Span) -> @ast.Range {
  { start: location(first.start), end: location(last.end), }
}

///|
fn range_of(span : @scanner.Span) -> @ast.Range {
  range_between(span, span)
}

///|
fn[T] node(range : @ast.Range, value : T) -> @ast.Node[T] {
  { range, value, }
}

///|
fn is_upper_name(token : @scanner.Token) -> Bool {
  token.kind == @scanner.TokenKind::Identifier &&
  (match token.lexeme.get_char(0) {
    Some(c) => c.is_ascii_uppercase()
    None => false
  })
}

///|
fn is_lower_name(token : @scanner.Token) -> Bool {
  token.kind == @scanner.TokenKind::Identifier && !is_upper_name(token)
}

///|
/// Result of parsing `exposing ( ... )`.
priv struct ParsedExposing {
  /// The exposing list node, from `exposing` to the closing `)`.
  exposing : @ast.Node[@ast.Exposing]
  /// Exposed names as the CST records them.
  names : Array[String]
  /// Index of the first token after the closing `)`.
  next : Int
}

///|
fn token_kind_at(
  tokens : Array[@scanner.Token],
  index : Int,
  kind : @scanner.TokenKind,
) -> Bool {
  index < tokens.length() && tokens[index].kind == kind
}

///|
/// Parse an exposing list that starts at the `exposing` keyword at `start`.
/// Returns `None` when the list is malformed.
fn parse_exposing(
  tokens : Array[@scanner.Token],
  start : Int,
) -> ParsedExposing? {
  let exposing_token = tokens[start]
  if !token_kind_at(tokens, start + 1, @scanner.TokenKind::LParen) {
    return None
  }
  let mut cursor = start + 2
  // `(..)`
  if token_kind_at(tokens, cursor, @scanner.TokenKind::DotDot) &&
    token_kind_at(tokens, cursor + 1, @scanner.TokenKind::RParen) {
    let dots = tokens[cursor]
    let close = tokens[cursor + 1]
    return Some({
      exposing: node(
        range_between(exposing_token.span, close.span),
        @ast.Exposing::All(range_of(dots.span)),
      ),
      names: [],
      next: cursor + 2,
    })
  }
  let items : Array[@ast.Node[@ast.TopLevelExpose]] = []
  let names = []
  while cursor < tokens.length() {
    let token = tokens[cursor]
    if is_upper_name(token) {
      names.push(token.lexeme)
      if token_kind_at(tokens, cursor + 1, @scanner.TokenKind::LParen) &&
        token_kind_at(tokens, cursor + 2, @scanner.TokenKind::DotDot) &&
        token_kind_at(tokens, cursor + 3, @scanner.TokenKind::RParen) {
        let open = range_between(
          tokens[cursor + 1].span,
          tokens[cursor + 3].span,
        )
        items.push(
          node(
            range_between(token.span, tokens[cursor + 3].span),
            @ast.TopLevelExpose::TypeExpose({
              name: token.lexeme,
              open: Some(open),
            }),
          ),
        )
        cursor = cursor + 4
      } else {
        items.push(
          node(
            range_of(token.span),
            @ast.TopLevelExpose::TypeOrAliasExpose(token.lexeme),
          ),
        )
        cursor = cursor + 1
      }
    } else if is_lower_name(token) {
      names.push(token.lexeme)
      items.push(
        node(
          range_of(token.span),
          @ast.TopLevelExpose::FunctionExpose(token.lexeme),
        ),
      )
      cursor = cursor + 1
    } else {
      return None
    }
    if token_kind_at(tokens, cursor, @scanner.TokenKind::Comma) {
      cursor = cursor + 1
    } else if token_kind_at(tokens, cursor, @scanner.TokenKind::RParen) {
      let close = tokens[cursor]
      return Some({
        exposing: node(
          range_between(exposing_token.span, close.span),
          @ast.Exposing::Explicit(items),
        ),
        names,
        next: cursor + 1,
      })
    } else {
      return None
    }
  }
  None
}

///|
/// The doc comment directly before a declaration, if any. A regular comment
/// between the doc comment and the declaration detaches it.
fn doc_comment(trivia : Array[@scanner.Trivia]) -> @scanner.Comment? {
  let mut candidate : @scanner.Comment? = None
  for item in trivia {
    if item is @scanner.Trivia::Comment(comment) {
      match comment.kind {
        Doc => candidate = Some(comment)
        Line | Block => if candidate is Some(_) { return None }
      }
    }
  }
  candidate
}

///|
/// A simple type argument: a lowercase name is a type variable, an uppercase
/// name is an unqualified type with no arguments.
fn simple_type_argument(
  token : @scanner.Token,
) -> @ast.Node[@ast.TypeAnnotation]? {
  let range = range_of(token.span)
  if is_lower_name(token) {
    Some(node(range, @ast.TypeAnnotation::GenericType(token.lexeme)))
  } else if is_upper_name(token) {
    Some(
      node(
        range,
        @ast.TypeAnnotation::Typed(node(range, ([], token.lexeme)), []),
      ),
    )
  } else {
    None
  }
}

///|
/// Build a custom type with exactly one constructor whose arguments are simple
/// names. Returns `None` for any other body, which the caller reports as
/// unsupported. When `module_documented` is true, the doc comment before
/// `start` documents the module and is not attached to the type.
fn custom_type(
  start : @scanner.Token,
  name : @scanner.Token,
  params : Array[@scanner.Token],
  body : Array[@scanner.Token],
  module_documented : Bool,
) -> @ast.Node[@ast.Declaration]? {
  guard body is [ctor, .. args] && is_upper_name(ctor) else { return None }
  let arguments = []
  for arg in args {
    guard simple_type_argument(arg) is Some(a) else { return None }
    arguments.push(a)
  }
  let last = body[body.length() - 1]
  let doc = if module_documented {
    None
  } else {
    doc_comment(start.trivia_before)
  }
  let documentation = doc.map(c => node(range_of(c.span), c.text))
  let first_span = match doc {
    Some(c) => c.span
    None => start.span
  }
  let value_constructor : @ast.Node[@ast.ValueConstructor] = node(
    range_between(ctor.span, last.span),
    { name: node(range_of(ctor.span), ctor.lexeme), arguments, },
  )
  Some(
    node(
      range_between(first_span, last.span),
      @ast.Declaration::CustomTypeDeclaration({
        documentation,
        name: node(range_of(name.span), name.lexeme),
        generics: params.map(p => node(range_of(p.span), p.lexeme)),
        constructors: [value_constructor],
      }),
    ),
  )
}

///|
/// The module documentation: the first doc comment before the first item after
/// the module header. elm-syntax lists it in `File.comments`.
fn module_documentation(
  trivia : Array[@scanner.Trivia],
) -> @ast.Node[@ast.Comment]? {
  for item in trivia {
    if item is @scanner.Trivia::Comment({ kind: Doc, text, span, }) {
      return Some(node(range_of(span), text))
    }
  }
  None
}
