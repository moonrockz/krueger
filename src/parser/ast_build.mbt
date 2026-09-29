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
        // elm-syntax ends the range at the start of `)`.
        @ast.Exposing::All({
          start: location(dots.span.start),
          end: location(close.span.start),
        }),
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
/// The doc comment that documents a declaration: the last doc comment before
/// it. Regular comments between the doc comment and the declaration do not
/// detach it (elm-syntax behavior).
fn doc_comment(trivia : Array[@scanner.Trivia]) -> @scanner.Comment? {
  let mut last : @scanner.Comment? = None
  for item in trivia {
    if item is @scanner.Trivia::Comment({ kind: Doc, .. } as comment) {
      last = Some(comment)
    }
  }
  last
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
/// unsupported. `module_doc` is the module documentation, which is never
/// attached to a declaration.
fn custom_type(
  start : @scanner.Token,
  name : @scanner.Token,
  params : Array[@scanner.Token],
  body : Array[@scanner.Token],
  module_doc : @scanner.Span?,
) -> @ast.Node[@ast.Declaration]? {
  guard body is [ctor, .. args] && is_upper_name(ctor) else { return None }
  let arguments = []
  for arg in args {
    guard simple_type_argument(arg) is Some(a) else { return None }
    arguments.push(a)
  }
  let last = body[body.length() - 1]
  let doc = match doc_comment(start.trivia_before) {
    Some(c) if module_doc != Some(c.span) => Some(c)
    _ => None
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
fn module_documentation(trivia : Array[@scanner.Trivia]) -> @scanner.Comment? {
  for item in trivia {
    if item is @scanner.Trivia::Comment({ kind: Doc, .. } as comment) {
      return Some(comment)
    }
  }
  None
}

///|
/// All comments for `File.comments`, in source order: regular comments and the
/// module documentation. Doc comments attached to a declaration (the last doc
/// comment before a declaration start) are left out. Any other doc comment is
/// stray: elm-syntax rejects the file, so it is returned in `stray`.
fn collect_comments(
  tokens : Array[@scanner.Token],
  declaration_starts : Array[Int],
  module_doc : @scanner.Span?,
) -> (Array[@ast.Node[@ast.Comment]], Array[@scanner.Span]) {
  let comments : Array[@ast.Node[@ast.Comment]] = []
  let stray = []
  for i, token in tokens {
    let attached = if declaration_starts.contains(i) {
      doc_comment(token.trivia_before).map(c => c.span)
    } else {
      None
    }
    for trivia in [..token.trivia_before, ..token.trivia_after] {
      guard trivia is @scanner.Trivia::Comment(c) else { continue }
      match c.kind {
        Line | Block => comments.push(node(range_of(c.span), c.text))
        Doc =>
          if module_doc == Some(c.span) {
            comments.push(node(range_of(c.span), c.text))
          } else if attached != Some(c.span) {
            stray.push(c.span)
          }
      }
    }
  }
  (comments, stray)
}
