///|
fn module_span(tokens : Array[@scanner.Token]) -> @scanner.Span? {
  if tokens.length() == 0 {
    None
  } else {
    Some(@scanner.Span::{
      start: tokens[0].span.start,
      end: tokens[tokens.length() - 1].span.end,
    })
  }
}

///|
fn token_slice(
  tokens : Array[@scanner.Token],
  start : Int,
  exclusive_end : Int,
) -> Array[@scanner.Token] {
  let subset = []
  let mut cursor = start
  while cursor < tokens.length() && cursor < exclusive_end {
    subset.push(tokens[cursor])
    cursor = cursor + 1
  }
  subset
}

///|
fn span_from_tokens_or(
  tokens : Array[@scanner.Token],
  fallback : @scanner.Span,
) -> @scanner.Span {
  if tokens.length() == 0 {
    fallback
  } else {
    @scanner.Span::{
      start: tokens[0].span.start,
      end: tokens[tokens.length() - 1].span.end,
    }
  }
}

///|
fn looks_like_function_decl_start(
  tokens : Array[@scanner.Token],
  index : Int,
) -> Bool {
  if index >= tokens.length() ||
    tokens[index].kind != @scanner.TokenKind::Identifier {
    return false
  }
  let mut cursor = index + 1
  while cursor < tokens.length() &&
        tokens[cursor].kind == @scanner.TokenKind::Identifier {
    cursor = cursor + 1
  }
  cursor < tokens.length() && tokens[cursor].kind == @scanner.TokenKind::Equals
}

///|
fn has_newline_trivia(trivia : Array[@scanner.Trivia]) -> Bool {
  trivia.any(fn(item) {
    match item {
      @scanner.Trivia::Newline(_, _) => true
      _ => false
    }
  })
}

///|
fn is_top_level_start(tokens : Array[@scanner.Token], index : Int) -> Bool {
  if index >= tokens.length() {
    return false
  }
  let kind = tokens[index].kind
  if kind == @scanner.TokenKind::module_kw() ||
    kind == @scanner.TokenKind::import_kw() ||
    kind == @scanner.TokenKind::type_kw() {
    return true
  }
  looks_like_function_decl_start(tokens, index) &&
  has_newline_trivia(tokens[index].trivia_before)
}

///|
fn parser_error(
  code : String,
  message : String,
  span : @scanner.Span,
) -> @scanner.Diagnostic {
  @scanner.Diagnostic::{
    code,
    severity: @scanner.Severity::Error,
    message,
    span,
  }
}

///|
fn malformed_module_header(span : @scanner.Span) -> @scanner.Diagnostic {
  parser_error("KR-PARSE-001", "Malformed module header", span)
}

///|
fn malformed_import(span : @scanner.Span) -> @scanner.Diagnostic {
  parser_error("KR-PARSE-002", "Malformed import declaration", span)
}

///|
fn malformed_type_declaration(span : @scanner.Span) -> @scanner.Diagnostic {
  parser_error("KR-PARSE-003", "Malformed type declaration", span)
}

///|
fn malformed_function_declaration(span : @scanner.Span) -> @scanner.Diagnostic {
  parser_error("KR-PARSE-004", "Malformed function declaration", span)
}

///|
fn unsupported_syntax(
  construct : String,
  span : @scanner.Span,
) -> @scanner.Diagnostic {
  parser_error("KR-PARSE-005", "Unsupported syntax: \{construct}", span)
}

///|
fn missing_module_header(span : @scanner.Span) -> @scanner.Diagnostic {
  parser_error("KR-PARSE-006", "Missing module header", span)
}

///|
fn recover_to_top_level(tokens : Array[@scanner.Token], index : Int) -> Int {
  let mut cursor = index
  while cursor < tokens.length() && !is_top_level_start(tokens, cursor) {
    cursor = cursor + 1
  }
  cursor
}

///|
pub fn[S : @scanner.Scanner] parse_module(
  source : @scanner.SourceText,
  scanner : S,
) -> ParseResult {
  match scanner.tokenize(source) {
    Ok(tokens) => parse_tokens(tokens)
    Err(errs) =>
      ParseResult::{ ast: None, cst: None, diagnostics: errs.diagnostics, }
  }
}

///|
/// Parse a token stream into an elm-syntax AST, a CST and diagnostics.
///
/// The AST contains only what the parser can produce exactly: the module
/// header, imports, and custom types with one constructor whose arguments are
/// simple names. Other declarations stay in the CST and are reported with
/// `KR-PARSE-005`. A file without a valid module header has no AST.
pub fn parse_tokens(tokens : @scanner.TokenStream) -> ParseResult {
  let stream = tokens.tokens
  let mut cursor = 0
  let mut module_definition : @syntax.Node[@syntax.Module]? = None
  let imports : Array[@syntax.Node[@syntax.Import]] = []
  let declarations : Array[@syntax.Node[@syntax.Declaration]] = []
  let comments : Array[@syntax.Node[@syntax.Comment]] = []
  let mut module_doc_index = -1
  let mut cst_header : @cst.ModuleHeaderCst? = None
  let cst_imports = []
  let cst_decls : Array[@cst.DeclarationCst] = []
  let diagnostics = []

  if stream.length() > 0 && stream[0].kind == @scanner.TokenKind::module_kw() {
    let module_token = stream[0]
    let parsed = if token_kind_at(stream, 1, @scanner.TokenKind::Identifier) &&
      token_kind_at(stream, 2, @scanner.TokenKind::exposing_kw()) {
      parse_exposing(stream, 2)
    } else {
      None
    }
    match parsed {
      Some(p) => {
        let name_token = stream[1]
        let header_tokens = token_slice(stream, 0, p.next)
        module_definition = Some(
          node(
            range_between(
              module_token.span,
              header_tokens[header_tokens.length() - 1].span,
            ),
            @syntax.Module::NormalModule({
              module_name: node(range_of(name_token.span), [name_token.lexeme]),
              exposing_list: p.exposing,
            }),
          ),
        )
        cst_header = Some(@cst.ModuleHeaderCst::{
          module_name: Some(name_token.lexeme),
          exposing: p.names,
          span: span_from_tokens_or(header_tokens, module_token.span),
          tokens: header_tokens,
        })
        cursor = p.next
        if cursor < stream.length() &&
          module_documentation(stream[cursor].trivia_before) is Some(doc) {
          comments.push(doc)
          module_doc_index = cursor
        }
      }
      None => {
        diagnostics.push(malformed_module_header(module_token.span))
        cursor = recover_to_top_level(stream, 1)
      }
    }
  } else {
    let span = if stream.length() > 0 {
      stream[0].span
    } else {
      {
        start: { offset: 0, line: 1, column: 1, },
        end: { offset: 0, line: 1, column: 1, },
      }
    }
    diagnostics.push(missing_module_header(span))
  }

  while cursor < stream.length() {
    if stream[cursor].kind == @scanner.TokenKind::import_kw() {
      let import_start = cursor
      let start_token = stream[cursor]
      let mut malformed = !token_kind_at(
        stream,
        cursor + 1,
        @scanner.TokenKind::Identifier,
      )
      let mut module_alias : @syntax.Node[@syntax.ModuleName]? = None
      let mut exposing_list : @syntax.Node[@syntax.Exposing]? = None
      let mut cst_exposing : Array[String]? = None
      let mut name_token = start_token
      if !malformed {
        name_token = stream[cursor + 1]
        cursor = cursor + 2
        if cursor < stream.length() &&
          stream[cursor].kind == @scanner.TokenKind::Identifier &&
          stream[cursor].lexeme == "as" {
          if cursor + 1 < stream.length() && is_upper_name(stream[cursor + 1]) {
            let alias_token = stream[cursor + 1]
            module_alias = Some(
              node(range_of(alias_token.span), [alias_token.lexeme]),
            )
            cursor = cursor + 2
          } else {
            malformed = true
          }
        }
        if !malformed &&
          token_kind_at(stream, cursor, @scanner.TokenKind::exposing_kw()) {
          match parse_exposing(stream, cursor) {
            Some(p) => {
              exposing_list = Some(p.exposing)
              cst_exposing = Some(p.names)
              cursor = p.next
            }
            None => malformed = true
          }
        }
      }
      if malformed {
        diagnostics.push(malformed_import(start_token.span))
        cursor = recover_to_top_level(stream, cursor + 1)
        continue
      }
      let import_tokens = token_slice(stream, import_start, cursor)
      let last = import_tokens[import_tokens.length() - 1]
      imports.push(
        node(range_between(start_token.span, last.span), {
          module_name: node(range_of(name_token.span), [name_token.lexeme]),
          module_alias,
          exposing_list,
        }),
      )
      cst_imports.push(@cst.ImportCst::{
        module_name: name_token.lexeme,
        exposing: cst_exposing,
        span: span_from_tokens_or(import_tokens, start_token.span),
        tokens: import_tokens,
      })
      continue
    }

    if stream[cursor].kind == @scanner.TokenKind::type_kw() {
      let type_decl_start = cursor
      let start_token = stream[cursor]
      cursor = cursor + 1
      let is_alias = token_kind_at(
        stream,
        cursor,
        @scanner.TokenKind::alias_kw(),
      )
      if is_alias {
        cursor = cursor + 1
      }
      if !token_kind_at(stream, cursor, @scanner.TokenKind::Identifier) {
        diagnostics.push(malformed_type_declaration(start_token.span))
        cursor = recover_to_top_level(stream, cursor)
        continue
      }
      let name_token = stream[cursor]
      cursor = cursor + 1
      let params = []
      while token_kind_at(stream, cursor, @scanner.TokenKind::Identifier) {
        params.push(stream[cursor])
        cursor = cursor + 1
      }
      if !token_kind_at(stream, cursor, @scanner.TokenKind::Equals) {
        diagnostics.push(malformed_type_declaration(start_token.span))
        cursor = recover_to_top_level(stream, cursor)
        continue
      }
      cursor = cursor + 1
      let body = []
      while cursor < stream.length() && !is_top_level_start(stream, cursor) {
        body.push(stream[cursor])
        cursor = cursor + 1
      }
      let decl_tokens = token_slice(stream, type_decl_start, cursor)
      let decl_span = span_from_tokens_or(decl_tokens, start_token.span)
      let param_names = params.map(p => p.lexeme)
      if is_alias {
        diagnostics.push(unsupported_syntax("type alias", decl_span))
        cst_decls.push(
          @cst.DeclarationCst::TypeAlias(@cst.TypeAliasCst::{
            name: name_token.lexeme,
            type_params: param_names,
            span: decl_span,
            tokens: decl_tokens,
          }),
        )
      } else {
        match
          custom_type(
            start_token,
            name_token,
            params,
            body,
            type_decl_start == module_doc_index,
          ) {
          Some(decl) => declarations.push(decl)
          None => diagnostics.push(unsupported_syntax("custom type", decl_span))
        }
        cst_decls.push(
          @cst.DeclarationCst::UnionType(@cst.UnionTypeCst::{
            name: name_token.lexeme,
            type_params: param_names,
            span: decl_span,
            tokens: decl_tokens,
          }),
        )
      }
      continue
    }

    if stream[cursor].kind != @scanner.TokenKind::Identifier {
      cursor = cursor + 1
      continue
    }

    if cursor > 0 && !has_newline_trivia(stream[cursor].trivia_before) {
      cursor = cursor + 1
      continue
    }

    let function_decl_start = cursor
    let name_token = stream[cursor]
    cursor = cursor + 1
    let cst_args = []
    while token_kind_at(stream, cursor, @scanner.TokenKind::Identifier) {
      cst_args.push(stream[cursor].lexeme)
      cursor = cursor + 1
    }
    if !token_kind_at(stream, cursor, @scanner.TokenKind::Equals) {
      diagnostics.push(malformed_function_declaration(name_token.span))
      cursor = recover_to_top_level(stream, cursor)
      continue
    }
    cursor = cursor + 1
    while cursor < stream.length() && !is_top_level_start(stream, cursor) {
      cursor = cursor + 1
    }
    let decl_tokens = token_slice(stream, function_decl_start, cursor)
    let decl_span = span_from_tokens_or(decl_tokens, name_token.span)
    diagnostics.push(unsupported_syntax("function declaration", decl_span))
    cst_decls.push(
      @cst.DeclarationCst::Function(@cst.FunctionCst::{
        name: name_token.lexeme,
        args: cst_args,
        span: decl_span,
        tokens: decl_tokens,
      }),
    )
  }

  ParseResult::{
    ast: module_definition.map(m => {
      module_definition: m,
      imports,
      declarations,
      comments,
    }),
    cst: Some(@cst.ModuleCst::{
      tokens: stream,
      header: cst_header,
      imports: cst_imports,
      declarations: cst_decls,
      span: module_span(stream),
    }),
    diagnostics,
  }
}
