// Runs on native and wasm-gc only (see `moon.pkg`): their default stacks
// hold the deeper input. On wasm (moonrun) 300 nested parentheses overflow
// a cold process (see the calibration table at `NESTING_COST` in
// `cursor.mbt`); on js they pass warm and are not promised.

///|
test "a higher fuel passes deeper input" {
  for construct in [@lawkit.Construct::Parens, Case] {
    let r = @parser.parse_module(
      @scanner.SourceText::new(@lawkit.nested(construct, 300)),
      @scanner.DefaultScanner::new(),
      fuel=2600,
    )
    @expect.expect((construct, r.diagnostics.length())).to_equal((construct, 0))
  }
}
