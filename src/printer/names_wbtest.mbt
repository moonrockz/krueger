///|
let elm : Ctx = { dialect: @dialect.Dialect::elm_0_19_1(), }

///|
test "lower names follow the scanner's rules and skip reserved words" {
  @expect.expect_all(s => {
    for ok in ["x", "élan", "alias", "infix", "effect", "a_1"] {
      s.expect(elm.is_lower(ok)).to_be_true()
    }
    for bad in ["", "X", "if", "type", "port", "where", "x'", "1x", "_x", "a b"] {
      s.expect(elm.is_lower(bad)).to_be_false()
    }
    let custom : Ctx = {
      dialect: { ..@dialect.Dialect::elm_0_19_1(), reserved_words: ["forall"], },
    }
    s.expect(custom.is_lower("forall")).to_be_false()
  })
}

///|
test "upper names, and operator symbols from the dialect's table" {
  @expect.expect_all(s => {
    s.expect(is_upper("Maybe")).to_be_true()
    s.expect(is_upper("Ärger")).to_be_true()
    s.expect(is_upper("maybe")).to_be_false()
    s.expect(is_upper("")).to_be_false()
    let root = @syntax.NodePath::root()
    s
    .expect(problem_of(() => elm.operator_symbol(root, "|>")).map(x => x.0))
    .to_equal(None)
    s
    .expect(problem_of(() => elm.operator_symbol(root, "</>")).map(x => x.0))
    .to_equal(None)
    for bad in ["", "a+", "--", "-->", ".", "=", "<=>"] {
      s
      .expect(problem_of(() => elm.operator_symbol(root, bad)).map(x => x.0))
      .to_equal(Some(InvalidName(Operator, bad)))
    }
  })
}

///|
fn[T] problem_of(
  f : () -> T raise PrintError,
) -> (PrintProblem, @syntax.NodePath)? {
  try {
    ignore(f())
    None
  } catch {
    PrintError(path~, problem~) => Some((problem, path))
  }
}

///|
test "a bad name raises InvalidName at the given path" {
  let path = @syntax.NodePath::root().child("declarations", 2)
  guard problem_of(() => elm.lower_name(path, "if")) is Some((problem, p)) else {
    fail("expected an error")
  }
  @expect.expect_all(s => {
    s.expect(problem).to_equal(InvalidName(Lower, "if"))
    s.expect(p.steps()).to_equal([{ field: "declarations", index: 2, }])
  })
}

///|
test "module names need at least one upper-case segment" {
  let root = @syntax.NodePath::root()
  @expect.expect_all(s => {
    s.expect(module_name(root, ["Html", "Events"][:])).to_equal("Html.Events")
    s
    .expect(problem_of(() => module_name(root, [][:])).map(x => x.0))
    .to_equal(Some(EmptyModuleName))
    s
    .expect(problem_of(() => module_name(root, ["html"][:])).map(x => x.0))
    .to_equal(Some(InvalidName(Upper, "html")))
  })
}
