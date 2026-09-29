///|
fn location(row : Int, column : Int) -> @syntax.Location {
  { row, column, }
}

///|
test "parse result holds an elm-syntax file" {
  let range : @syntax.Range = { start: location(1, 1), end: location(1, 26), }
  let file : @syntax.File = {
    module_definition: {
      range,
      value: NormalModule({
        module_name: { range, value: ["Main"], },
        exposing_list: { range, value: All(range), },
      }),
    },
    imports: [],
    declarations: [],
    comments: [],
  }
  let result = @parser.ParseResult::{
    ast: Some(file),
    cst: None,
    diagnostics: [],
  }
  @expect.expect(result.ast.map(f => f.imports.length())).to_equal(Some(0))
}

///|
test "parse result cst uses dedicated cst package module type" {
  let module_cst = @cst.ModuleCst::{
    tokens: [],
    header: None,
    imports: [],
    declarations: [],
    span: None,
  }
  let result = @parser.ParseResult::{
    ast: None,
    cst: Some(module_cst),
    diagnostics: [],
  }
  guard result.cst is Some(cst) else { fail("expected a CST") }
  @expect.expect(cst.declarations.length()).to_equal(0)
}
