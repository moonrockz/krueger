///|
fn core(d : @dialect.Dialect) -> @dialect.Dialect {
  { ..d, core_package: true, }
}

///|
fn both_titles(text : String) -> (String, String) {
  (
    first_in(text, @dialect.Dialect::elm_0_19_1()),
    first_in(text, @dialect.Dialect::elm_syntax_7_3_9()),
  )
}

///|
test "effect modules belong to elm packages" {
  @expect.expect_all(s => {
    let text = "effect module Fixture where { command = C } exposing (..)\n\n\ntype C\n    = C\n"
    s.expect(both_titles(text)).to_equal(("INVALID EFFECT MODULE", "no error"))
    s
    .expect(first_in(text, core(@dialect.Dialect::elm_0_19_1())))
    .to_equal("no error")
  })
}

///|
test "a repeated effect key is rejected by elm make; elm-syntax keeps the first" {
  @expect.expect_all(s => {
    let text = "effect module Fixture where { command = C, command = D } exposing (..)\n\n\ntype C\n    = C\n"
    s.expect(both_titles(text)).to_equal(("BAD MODULE DECLARATION", "no error"))
    s
    .expect(first_in(text, core(@dialect.Dialect::elm_0_19_1())))
    .to_equal("BAD MODULE DECLARATION")
    let source = @scanner.SourceText::{ module_name: Some("Fixture"), text, }
    guard @scanner.DefaultScanner::new().tokenize(source) is Ok(tokens) else {
      fail("scan error")
    }
    let result = parse_tokens(
      tokens,
      dialect=@dialect.Dialect::elm_syntax_7_3_9(),
    )
    guard result.ast
      is Some({ module_definition: { value: EffectModule(data), .. }, .. }) else {
      fail("expected an effect module")
    }
    s.expect(data.command.map(n => n.value)).to_equal(Some("C"))
  })
}

///|
test "infix declarations belong to elm packages" {
  @expect.expect_all(s => {
    let text = "module Fixture exposing (..)\n\n\ninfix left 6 (+) = add\n\n\nadd a b =\n    a\n"
    s.expect(both_titles(text)).to_equal(("UNFINISHED PARENTHESES", "no error"))
    s
    .expect(first_in(text, core(@dialect.Dialect::elm_0_19_1())))
    .to_equal("no error")
  })
}

///|
test "ports need a port module" {
  @expect.expect_all(s => {
    let normal = "module Fixture exposing (..)\n\n\nport out : String -> Cmd msg\n"
    s.expect(both_titles(normal)).to_equal(("UNEXPECTED PORTS", "no error"))
    let port = "port module Fixture exposing (..)\n\n\nport out : String -> Cmd msg\n"
    s.expect(both_titles(port)).to_equal(("no error", "no error"))
  })
}
