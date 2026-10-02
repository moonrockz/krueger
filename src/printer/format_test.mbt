///|
let formatted_module : String =
  #|module A exposing (a)
  #|
  #|
  #|a =
  #|    1
  #|

///|
test "format keeps a module that elm-format accepts" {
  @expect.expect(@printer.format(formatted_module)).to_equal(formatted_module)
}

///|
test "format raises ParseFailed for a source with a syntax error" {
  let failed = try @printer.format("module A exposing (a)\n\na = (\n") catch {
    ParseFailed(_) => true
    _ => false
  } noraise {
    _ => false
  }
  @expect.expect(failed).to_be_true()
}

///|
test "Width layout fits a long list in the width" {
  let source = "module A exposing (a)\n\n\na =\n    [ 1000, 2000, 3000 ]\n"
  @expect.expect(@printer.format(source, layout=Width(22))).to_equal(
    "module A exposing (a)\n\n\na =\n    [ 1000\n    , 2000\n    , 3000\n    ]\n",
  )
}

///|
test "ElmFormat layout does not break a long line" {
  let items = Array::make(60, "1").join(", ")
  let source = "module A exposing (a)\n\n\na =\n    [ \{items} ]\n"
  @expect.expect(@printer.format(source)).to_equal(source)
}
