///|
test "a comment that no printer path takes raises UnplacedComment" {
  let source = "module Abc exposing (a)\n\n\na =\n    1\n"
  let result = @parser.parse_module(
    @scanner.SourceText::new(source),
    @scanner.DefaultScanner::new(),
  )
  guard result.ast is Some(file) else { fail("no AST") }
  // A comment inside the module name is inner to that name: no printer
  // path takes the inner comments of a name.
  let inside : @ast.Range = {
    start: { row: 1, column: 9, },
    end: { row: 1, column: 10, },
  }
  let comments = [..file.comments, { range: inside, value: "{--}", }]
  let changed = { ..result, ast: Some({ ..file, comments: comments[:], }), }
  let problem = try format_parsed(changed) catch {
    Unprintable(PrintError(problem~, ..)) => Some(problem)
    _ => None
  } noraise {
    _ => None
  }
  @expect.expect(problem).to_equal(Some(UnplacedComment(inside)))
}
