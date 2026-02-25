test "scanner facade is callable through a scanner implementation" {
  let source = SourceText::{ module_name: Some("Main"), text: "module Main exposing (..)" }
  let scanner = DefaultScanner::new()
  let _ = scanner.tokenize(source)
}
