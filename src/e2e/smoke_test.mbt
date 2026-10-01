///|
test "e2e: a small module parses without diagnostics" {
  let result = @krueger.parse_module(
    @krueger.SourceText::new("module Main exposing (main)\n\nmain = 1\n"),
  )
  assert_eq(result.diagnostics.length(), 0)
  assert_true(result.ast is Some(_))
}
