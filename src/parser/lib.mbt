///|
fn normalize_doc_comment_text(raw : String) -> String {
  let without_prefix = match raw.strip_prefix("{-|") {
    Some(view) => view.to_string()
    None => raw
  }
  let without_suffix = match without_prefix.strip_suffix("-}") {
    Some(view) => view.to_string()
    None => without_prefix
  }
  without_suffix.trim().to_string()
}

///|
fn extract_doc_comment(trivia : Array[@scanner.Trivia]) -> DocComment? {
  let mut candidate : DocComment? = None
  for item in trivia {
    match item {
      @scanner.Trivia::Comment(comment) =>
        match comment.kind {
          @scanner.CommentKind::Doc =>
            candidate = Some(DocComment::{
              text: normalize_doc_comment_text(comment.text),
              span: comment.span,
            })
          @scanner.CommentKind::Line | @scanner.CommentKind::Block =>
            match candidate {
              Some(_) => return None
              None => ()
            }
        }
      _ => ()
    }
  }
  candidate
}

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
fn to_identifier(value : String) -> @ast.Identifier {
  @ast.Identifier::Identifier(value)
}

///|
fn to_module_name(value : String) -> @ast.ModuleName {
  @ast.ModuleName::ModuleName(to_identifier(value))
}

///|
fn to_value_name(value : String) -> @ast.ValueName {
  @ast.ValueName::ValueName(to_identifier(value))
}

///|
fn to_type_name(value : String) -> @ast.TypeName {
  @ast.TypeName::TypeName(to_identifier(value))
}

///|
fn to_type_var_name(value : String) -> @ast.TypeVarName {
  @ast.TypeVarName::TypeVarName(to_identifier(value))
}

///|
fn to_constructor_name(value : String) -> @ast.ConstructorName {
  @ast.ConstructorName::ConstructorName(to_identifier(value))
}

///|
fn to_exposed_name(value : String) -> @ast.ExposedName {
  @ast.ExposedName::Value(to_value_name(value))
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
      ParseResult::{ ast: None, cst: None, diagnostics: errs.diagnostics }
  }
}

///|
pub fn parse_tokens(tokens : @scanner.TokenStream) -> ParseResult {
  let stream = tokens.tokens
  let mut cursor = 0
  let mut module_name : @ast.ModuleName? = None
  let exposing = []
  let imports = []
  let declarations = []
  let mut cst_header : @cst.ModuleHeaderCst? = None
  let cst_imports = []
  let cst_decls : Array[@cst.DeclarationCst] = []
  let diagnostics = []

  if stream.length() > 0 && stream[0].kind == @scanner.TokenKind::module_kw() {
    let header_start = cursor
    let module_token = stream[0]
    cursor = 1
    let mut module_header_valid = true
    let mut cst_module_name : String? = None
    let cst_exposing = []

    if cursor < stream.length() {
      if stream[cursor].kind == @scanner.TokenKind::Identifier {
        let parsed_module_name = stream[cursor].lexeme
        module_name = Some(to_module_name(parsed_module_name.to_string()))
        cst_module_name = Some(parsed_module_name)
        cursor = cursor + 1
      } else {
        module_header_valid = false
      }
    } else {
      module_header_valid = false
    }

    if module_header_valid &&
      cursor < stream.length() &&
      stream[cursor].kind == @scanner.TokenKind::exposing_kw() {
      cursor = cursor + 1
      if cursor < stream.length() &&
        stream[cursor].kind == @scanner.TokenKind::LParen {
        cursor = cursor + 1
        let mut found_rparen = false
        while cursor < stream.length() {
          if stream[cursor].kind == @scanner.TokenKind::RParen {
            found_rparen = true
            cursor = cursor + 1
            break
          }
          if stream[cursor].kind == @scanner.TokenKind::Identifier {
            let exposed_name = stream[cursor].lexeme
            exposing.push(to_exposed_name(exposed_name.to_string()))
            cst_exposing.push(exposed_name)
          }
          cursor = cursor + 1
        }
        if !found_rparen {
          module_header_valid = false
        }
      } else {
        module_header_valid = false
      }
    } else {
      module_header_valid = false
    }

    if !module_header_valid {
      diagnostics.push(malformed_module_header(module_token.span))
      cursor = recover_to_top_level(stream, cursor)
    } else {
      let header_tokens = token_slice(stream, header_start, cursor)
      cst_header = Some(@cst.ModuleHeaderCst::{
        module_name: cst_module_name,
        exposing: cst_exposing,
        span: span_from_tokens_or(header_tokens, module_token.span),
        tokens: header_tokens,
      })
    }
  }

  while cursor < stream.length() {
    if stream[cursor].kind == @scanner.TokenKind::import_kw() {
      let import_start = cursor
      let start_token = stream[cursor]
      let mut malformed = false
      cursor = cursor + 1
      if cursor >= stream.length() ||
        stream[cursor].kind != @scanner.TokenKind::Identifier {
        malformed = true
      }
      let import_name = if malformed {
        ""
      } else {
        let name = stream[cursor].lexeme
        cursor = cursor + 1
        name
      }

      let mut import_exposing : Array[@ast.ExposedName]? = None
      let mut cst_import_exposing : Array[String]? = None
      if !malformed &&
        cursor < stream.length() &&
        stream[cursor].kind == @scanner.TokenKind::exposing_kw() {
        cursor = cursor + 1
        if cursor < stream.length() &&
          stream[cursor].kind == @scanner.TokenKind::LParen {
          cursor = cursor + 1
          let names = []
          let cst_names = []
          let mut found_rparen = false
          while cursor < stream.length() {
            if stream[cursor].kind == @scanner.TokenKind::RParen {
              found_rparen = true
              cursor = cursor + 1
              break
            }
            if stream[cursor].kind == @scanner.TokenKind::Identifier {
              let exposed_name = stream[cursor].lexeme
              names.push(to_exposed_name(exposed_name.to_string()))
              cst_names.push(exposed_name)
            }
            cursor = cursor + 1
          }
          if !found_rparen {
            malformed = true
          } else {
            import_exposing = Some(names)
            cst_import_exposing = Some(cst_names)
          }
        } else {
          malformed = true
        }
      }

      if malformed {
        diagnostics.push(malformed_import(start_token.span))
        cursor = recover_to_top_level(stream, cursor)
      } else {
        imports.push(ImportDecl::{
          module_name: to_module_name(import_name.to_string()),
          exposing: import_exposing,
          span: start_token.span,
        })
        let import_tokens = token_slice(stream, import_start, cursor)
        cst_imports.push(@cst.ImportCst::{
          module_name: import_name,
          exposing: cst_import_exposing,
          span: span_from_tokens_or(import_tokens, start_token.span),
          tokens: import_tokens,
        })
      }
      continue
    }

    if stream[cursor].kind == @scanner.TokenKind::type_kw() {
      let type_decl_start = cursor
      let start_token = stream[cursor]
      let mut malformed = false
      cursor = cursor + 1
      let is_alias = cursor < stream.length() &&
        stream[cursor].kind == @scanner.TokenKind::alias_kw()
      if is_alias {
        cursor = cursor + 1
      }
      if cursor >= stream.length() ||
        stream[cursor].kind != @scanner.TokenKind::Identifier {
        malformed = true
      }

      let type_name = if malformed {
        ""
      } else {
        let name = stream[cursor].lexeme
        cursor = cursor + 1
        name
      }

      let type_params = []
      let cst_type_params = []
      while !malformed &&
            cursor < stream.length() &&
            stream[cursor].kind == @scanner.TokenKind::Identifier {
        let type_param_name = stream[cursor].lexeme
        type_params.push(to_type_var_name(type_param_name.to_string()))
        cst_type_params.push(type_param_name)
        cursor = cursor + 1
      }
      if !malformed &&
        cursor < stream.length() &&
        stream[cursor].kind == @scanner.TokenKind::Equals {
        cursor = cursor + 1
      } else {
        malformed = true
      }

      if malformed {
        diagnostics.push(malformed_type_declaration(start_token.span))
        cursor = recover_to_top_level(stream, cursor)
        continue
      }

      let raw_tokens = []
      while cursor < stream.length() && !is_top_level_start(stream, cursor) {
        raw_tokens.push(stream[cursor])
        cursor = cursor + 1
      }
      let decl_tokens = token_slice(stream, type_decl_start, cursor)

      let meta = DeclMeta::{
        doc_comment: extract_doc_comment(start_token.trivia_before),
        span: start_token.span,
      }
      if is_alias {
        declarations.push(
          Declaration::TypeAliasDecl(TypeAliasDeclaration::{
            name: to_type_name(type_name.to_string()),
            type_params,
            body: @ast.TypeExpr::Unparsed(@ast.UnparsedTypeExpr::{
              tokens: raw_tokens,
            }),
            meta,
          }),
        )
        cst_decls.push(
          @cst.DeclarationCst::TypeAlias(@cst.TypeAliasCst::{
            name: type_name,
            type_params: cst_type_params,
            span: span_from_tokens_or(decl_tokens, start_token.span),
            tokens: decl_tokens,
          }),
        )
      } else {
        let cases = []
        for token in raw_tokens {
          if token.kind == @scanner.TokenKind::Identifier {
            cases.push(UnionTypeCase::{
              name: to_constructor_name(token.lexeme),
              args: [],
            })
          }
        }
        declarations.push(
          Declaration::UnionTypeDecl(UnionTypeDeclaration::{
            name: to_type_name(type_name.to_string()),
            type_params,
            cases,
            meta,
          }),
        )
        cst_decls.push(
          @cst.DeclarationCst::UnionType(@cst.UnionTypeCst::{
            name: type_name,
            type_params: cst_type_params,
            span: span_from_tokens_or(decl_tokens, start_token.span),
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
    let name = name_token.lexeme
    cursor = cursor + 1

    let args = []
    let cst_args = []
    while cursor < stream.length() &&
          stream[cursor].kind == @scanner.TokenKind::Identifier {
      let arg_name = stream[cursor].lexeme
      args.push(to_value_name(arg_name.to_string()))
      cst_args.push(arg_name)
      cursor = cursor + 1
    }

    if cursor < stream.length() &&
      stream[cursor].kind == @scanner.TokenKind::Equals {
      cursor = cursor + 1
    } else {
      diagnostics.push(malformed_function_declaration(name_token.span))
      cursor = recover_to_top_level(stream, cursor)
      continue
    }

    let body_tokens = []
    while cursor < stream.length() && !is_top_level_start(stream, cursor) {
      body_tokens.push(stream[cursor])
      cursor = cursor + 1
    }
    let decl_tokens = token_slice(stream, function_decl_start, cursor)

    let meta = DeclMeta::{
      doc_comment: extract_doc_comment(name_token.trivia_before),
      span: name_token.span,
    }
    declarations.push(
      Declaration::FunctionDecl(FunctionDeclaration::{
        name: to_value_name(name.to_string()),
        args,
        body: @ast.Expr::Unparsed(@ast.UnparsedExpr::{ tokens: body_tokens }),
        meta,
      }),
    )
    cst_decls.push(
      @cst.DeclarationCst::Function(@cst.FunctionCst::{
        name,
        args: cst_args,
        span: span_from_tokens_or(decl_tokens, name_token.span),
        tokens: decl_tokens,
      }),
    )
  }

  ParseResult::{
    ast: Some(ModuleAst::{
      module_name,
      exposing,
      imports,
      declarations,
      span: module_span(stream),
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
