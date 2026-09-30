///|
fn first_declaration_depth(text : String) -> Int {
  let source = @scanner.SourceText::{ module_name: Some("M"), text, }
  guard @scanner.DefaultScanner::new().tokenize(source) is Ok(tokens) else {
    abort("scan error")
  }
  guard parse_tokens(tokens).ast is Some({ declarations: [d, ..], .. }) else {
    abort("no declaration")
  }
  declaration_depth(d.value)
}

///|
test "parenthesized patterns count in the AST depth" {
  let header = "module M exposing (..)\n\n\n"
  @expect.expect(first_declaration_depth(header + "f ((x)) =\n    1\n")).to_equal(
    first_declaration_depth(header + "f (x) =\n    1\n") + 1,
  )
}
