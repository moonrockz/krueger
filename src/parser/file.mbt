///|
fn parser_error(
  code : String,
  message : String,
  span : @scanner.Span,
  title~ : String,
  report~ : Array[@scanner.Block],
) -> @scanner.Diagnostic {
  { code, severity: Error, message, span, title, report, }
}

///|
fn declaration_error_code(kind : DeclarationKind) -> (String, String) {
  match kind {
    FunctionKind => ("KR-PARSE-004", "Malformed function declaration")
    TypeKind => ("KR-PARSE-003", "Malformed type declaration")
    PortKind | InfixKind => ("KR-PARSE-008", "Syntax error")
  }
}

///|
/// Skip to the next token on column 1 (the next top-level item), moving at
/// least one token.
fn skip_to_top_level(c : Cursor) -> Unit {
  if !c.at_end() {
    c.pos += 1
  }
  while c.peek() is Some(t) && t.span.start.column != 1 {
    c.pos += 1
  }
}

///|
/// The problem for a token `t` that is not at column 1 where a top-level
/// declaration must start.
fn not_at_module_level(c : Cursor, t : @scanner.Token) -> Problem {
  ignore(c)
  let highlight = point(t.span.start)
  if t.kind is Equals {
    make_problem(
      "UNEXPECTED EQUALS",
      [Plain("I was not expecting to see this equals sign:")],
      highlight,
      highlight,
      [
        plain(
          "Maybe this is part of a definition that does not start in the first column? Top-level definitions must start at the very beginning of a line.",
        ),
      ],
    )
  } else {
    make_problem(
      "SYNTAX PROBLEM",
      [Plain("I got stuck here:")],
      highlight,
      highlight,
      [
        plain(
          "I was expecting a new declaration at the start of a line. Is something indented too little or too much above?",
        ),
      ],
    )
  }
}

///|
/// Span of the tokens from `start` up to the cursor.
fn span_since(c : Cursor, start : Int) -> @scanner.Span {
  let first = c.tokens[start]
  let last = if c.pos > start { c.tokens[c.pos - 1] } else { first }
  { start: first.span.start, end: last.span.end, }
}

///|
/// The last doc comment in `trivia`.
fn last_doc_comment(trivia : Array[@scanner.Trivia]) -> @scanner.Comment? {
  let mut last : @scanner.Comment? = None
  for item in trivia {
    if item is Comment({ kind: Doc, .. } as comment) {
      last = Some(comment)
    }
  }
  last
}

///|
/// The first doc comment in `trivia`.
fn first_doc_comment(trivia : Array[@scanner.Trivia]) -> @scanner.Comment? {
  for item in trivia {
    if item is Comment({ kind: Doc, .. } as comment) {
      return Some(comment)
    }
  }
  None
}

///|
/// All comments for `File.comments` in source order: regular comments, plus
/// the doc comments in `listed` (module documentation, docs before ports).
/// Doc comments in `attached` belong to declarations. Any other doc comment
/// is stray: elm-syntax rejects the file.
fn collect_comments(
  tokens : Array[@scanner.Token],
  attached : Array[@scanner.Span],
  listed : Array[@scanner.Span],
) -> (Array[@ast.Node[@ast.Comment]], Array[@scanner.Span]) {
  let comments : Array[@ast.Node[@ast.Comment]] = []
  let stray = []
  for token in tokens {
    for trivia in [..token.trivia_before, ..token.trivia_after] {
      guard trivia is Comment(comment) else { continue }
      let range : @ast.Range = {
        start: location(comment.span.start),
        end: location(comment.span.end),
      }
      match comment.kind {
        Line | Block => comments.push(node(range, comment.text))
        Doc =>
          if listed.contains(comment.span) {
            comments.push(node(range, comment.text))
          } else if !attached.contains(comment.span) {
            stray.push(comment.span)
          }
      }
    }
  }
  (comments, stray)
}

///|
/// CST entry for a top-level declaration from its AST (ports and infix
/// declarations have no CST form).
fn declaration_cst(
  decl : @ast.Node[@ast.Declaration],
  tokens : Array[@scanner.Token],
  span : @scanner.Span,
) -> @cst.DeclarationCst? {
  match decl.value {
    FunctionDeclaration(f) =>
      Some(
        Function({
          name: f.declaration.value.name.value,
          args: f.declaration.value.arguments.map(pattern_text),
          tokens,
          span,
        }),
      )
    AliasDeclaration(a) =>
      Some(
        TypeAlias({
          name: a.name.value,
          type_params: a.generics.map(g => g.value),
          tokens,
          span,
        }),
      )
    CustomTypeDeclaration(t) =>
      Some(
        UnionType({
          name: t.name.value,
          type_params: t.generics.map(g => g.value),
          tokens,
          span,
        }),
      )
    _ => None
  }
}

///|
/// Short text for a pattern in the CST.
fn pattern_text(p : @ast.Node[@ast.Pattern]) -> String {
  match p.value {
    VarPattern(name) => name
    AllPattern => "_"
    UnitPattern => "()"
    NamedPattern(name_ref, _) => name_ref.name
    _ => "_"
  }
}

///|
fn header_module_name(m : @ast.Module) -> Array[String] {
  match m {
    NormalModule(d) | PortModule(d) => d.module_name.value
    EffectModule(d) => d.module_name.value
  }
}

///|
fn header_exposing(m : @ast.Module) -> @ast.Node[@ast.Exposing] {
  match m {
    NormalModule(d) | PortModule(d) => d.exposing_list
    EffectModule(d) => d.exposing_list
  }
}

///|
/// Exposed names as the CST records them (empty for `(..)`).
fn exposed_names(e : @ast.Node[@ast.Exposing]) -> Array[String] {
  match e.value {
    All(_) => []
    Explicit(items) =>
      items.map(i => {
        match i.value {
          InfixExpose(n) | FunctionExpose(n) | TypeOrAliasExpose(n) => n
          TypeExpose(t) => t.name
        }
      })
  }
}

///|
/// Parse a token stream into an elm-syntax AST, a CST and diagnostics,
/// following stil4m/elm-syntax 7.3.9.
pub fn parse_tokens(
  tokens : @scanner.TokenStream,
  dialect? : @dialect.Dialect = @dialect.Dialect::elm_0_19_1(),
) -> ParseResult {
  let stream = tokens.tokens
  let c = Cursor::new(stream, dialect)
  let diagnostics = []
  let attached = []
  let listed = []
  let mut module_definition : @ast.Node[@ast.Module]? = None
  let mut cst_header : @cst.ModuleHeaderCst? = None
  let imports : Array[@ast.Node[@ast.Import]] = []
  let cst_imports = []
  let declarations : Array[@ast.Node[@ast.Declaration]] = []
  let cst_decls = []
  let starts_header = match c.peek() {
    Some({ kind: Keyword(Module | Port), .. }) => true
    Some({ kind: Identifier, lexeme: "effect", .. }) => true
    _ => false
  }
  if starts_header {
    c.start_item()
    let start = c.pos
    try module_header(c) catch {
      SyntaxError(message, span, problem) => {
        diagnostics.push(
          parser_error(
            "KR-PARSE-001",
            "Malformed module header: \{message}",
            span,
            title=problem.title,
            report=problem.report,
          ),
        )
        skip_to_top_level(c)
      }
    } noraise {
      header => {
        module_definition = Some(header)
        let header_tokens = stream[start:c.pos].to_owned()
        cst_header = Some({
          module_name: Some(header_module_name(header.value).join(".")),
          exposing: exposed_names(header_exposing(header.value)),
          tokens: header_tokens,
          span: span_since(c, start),
        })
        if c.peek() is Some(next) &&
          first_doc_comment(next.trivia_before) is Some(doc) {
          listed.push(doc.span)
        }
      }
    }
  } else {
    diagnostics.push(
      parser_error(
        "KR-PARSE-006",
        "Missing module header",
        c.here(),
        title="MODULE NAME MISSING",
        report=[
          Text([
            Plain(
              "I need the module name to be declared at the top of this file, like this:",
            ),
          ]),
          Example("module Fixture exposing (..)"),
          plain("Try adding that as the first line of your file!"),
        ],
      ),
    )
  }
  while c.is_keyword(Import) {
    c.start_item()
    let start = c.pos
    try import_declaration(c) catch {
      SyntaxError(message, span, problem) => {
        diagnostics.push(
          parser_error(
            "KR-PARSE-002",
            "Malformed import declaration: \{message}",
            span,
            title=problem.title,
            report=problem.report,
          ),
        )
        skip_to_top_level(c)
      }
    } noraise {
      imp => {
        imports.push(imp)
        cst_imports.push(@cst.ImportCst::{
          module_name: imp.value.module_name.value.join("."),
          exposing: imp.value.exposing_list.map(exposed_names),
          tokens: stream[start:c.pos].to_owned(),
          span: span_since(c, start),
        })
      }
    }
  }
  while c.peek() is Some(t) {
    if t.span.start.column != 1 {
      let start = c.pos
      let problem = not_at_module_level(c, t)
      skip_to_top_level(c)
      diagnostics.push(
        parser_error(
          "KR-PARSE-007",
          "Unexpected syntax: token not at module level",
          span_since(c, start),
          title=problem.title,
          report=problem.report,
        ),
      )
      continue
    }
    let kind = declaration_kind(c)
    let doc = match kind {
      FunctionKind | TypeKind =>
        match last_doc_comment(t.trivia_before) {
          Some(d) if !listed.contains(d.span) => Some(d)
          _ => None
        }
      PortKind =>
        match last_doc_comment(t.trivia_before) {
          Some(d) if !listed.contains(d.span) => {
            listed.push(d.span)
            None
          }
          _ => None
        }
      InfixKind => None
    }
    let documentation = doc.map(d => {
      node(
        { start: location(d.span.start), end: location(d.span.end), },
        d.text,
      )
    })
    let start = c.pos
    c.start_item()
    try declaration(c, documentation) catch {
      SyntaxError(message, span, problem) => {
        let (code, what) = declaration_error_code(kind)
        diagnostics.push(
          parser_error(
            code,
            "\{what}: \{message}",
            span,
            title=problem.title,
            report=problem.report,
          ),
        )
        skip_to_top_level(c)
      }
    } noraise {
      decl => {
        if doc is Some(d) {
          attached.push(d.span)
        }
        declarations.push(decl)
        let decl_tokens = stream[start:c.pos].to_owned()
        if declaration_cst(decl, decl_tokens, span_since(c, start))
          is Some(entry) {
          cst_decls.push(entry)
        }
      }
    }
  }
  let (comments, stray) = collect_comments(stream, attached, listed)
  for span in stray {
    diagnostics.push(
      parser_error(
        "KR-PARSE-007",
        "Unexpected syntax: doc comment not attached to a declaration",
        span,
        title="WEIRD DECLARATION",
        report=[
          plain("I was not expecting this documentation comment here:"),
          Excerpt(context=point(span.start), highlight=point(span.start)),
          Text([
            Plain("A documentation comment ("),
            @scanner.Chunk::code("{-| ... -}"),
            Plain(
              ") must come right before the declaration it documents, or right after the module header.",
            ),
          ]),
        ],
      ),
    )
  }
  ParseResult::{
    ast: module_definition.map(m => {
      module_definition: m,
      imports,
      declarations,
      comments,
    }),
    cst: Some({
      tokens: stream,
      header: cst_header,
      imports: cst_imports,
      declarations: cst_decls,
      span: match (stream.get(0), stream.last()) {
        (Some(first), Some(last)) =>
          Some({ start: first.span.start, end: last.span.end, })
        _ => None
      },
    }),
    diagnostics,
  }
}

///|
/// Tokenize `source` with `scanner` and parse it in `dialect`. The caller
/// builds `scanner` for the same dialect.
pub fn[S : @scanner.Scanner] parse_module(
  source : @scanner.SourceText,
  scanner : S,
  dialect? : @dialect.Dialect = @dialect.Dialect::elm_0_19_1(),
) -> ParseResult {
  match scanner.tokenize(source) {
    Ok(tokens) => parse_tokens(tokens, dialect~)
    Err(errs) => { ast: None, cst: None, diagnostics: errs.diagnostics, }
  }
}
