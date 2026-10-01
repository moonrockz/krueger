///|
/// A visitor over the node model: one method per group of node types (see
/// `accept` for which method sees which node). Every method has a default:
/// `visit_*` returns `Continue` and `leave` does nothing, so a visitor
/// implements only what it needs. The visitor's state belongs to the caller.
/// See `accept` for an example.
pub(open) trait Visitor {
  /// Declarations other than functions: type aliases, custom types, ports,
  /// infix declarations and destructurings (top-level or in a `let`).
  fn visit_declaration(Self, NodeRef) -> Control = _
  /// Function declarations, top-level or in a `let`.
  fn visit_function(Self, NodeRef) -> Control = _
  /// Expressions, the `case`, `let` and `if` expressions included.
  fn visit_expression(Self, NodeRef) -> Control = _
  /// Patterns, in arguments, case branches, lambdas and destructurings.
  fn visit_pattern(Self, NodeRef) -> Control = _
  /// Type annotations, in signatures, ports, aliases and constructors.
  fn visit_type(Self, NodeRef) -> Control = _
  /// Case branches (the `case` expression itself goes to `visit_expression`).
  fn visit_case(Self, NodeRef) -> Control = _
  /// Import declarations.
  fn visit_import(Self, NodeRef) -> Control = _
  /// Regular comments, `--` and `{- -}` (doc comments go to `visit_other`).
  fn visit_comment(Self, NodeRef) -> Control = _
  /// Doc attributes, `@name …` and `@docs`.
  fn visit_attribute(Self, NodeRef) -> Control = _
  /// Every other node: file, module, names, signatures, implementations, doc
  /// comments (`documentation`), …
  fn visit_other(Self, NodeRef) -> Control = _
  /// Runs after a node's children, as in `walk`.
  fn leave(Self, NodeRef) -> Unit = _
}

///|
impl Visitor with fn visit_declaration(_self, _node) {
  Continue
}

///|
impl Visitor with fn visit_function(_self, _node) {
  Continue
}

///|
impl Visitor with fn visit_expression(_self, _node) {
  Continue
}

///|
impl Visitor with fn visit_pattern(_self, _node) {
  Continue
}

///|
impl Visitor with fn visit_type(_self, _node) {
  Continue
}

///|
impl Visitor with fn visit_case(_self, _node) {
  Continue
}

///|
impl Visitor with fn visit_import(_self, _node) {
  Continue
}

///|
impl Visitor with fn visit_comment(_self, _node) {
  Continue
}

///|
impl Visitor with fn visit_attribute(_self, _node) {
  Continue
}

///|
impl Visitor with fn visit_other(_self, _node) {
  Continue
}

///|
impl Visitor with fn leave(_self, _node) {
  ()
}

///|
fn[V : Visitor] dispatch(visitor : V, n : NodeRef) -> Control {
  match n {
    Declaration(_, _) | LetDeclaration(_) =>
      if n.kind() == "function" {
        visitor.visit_function(n)
      } else {
        visitor.visit_declaration(n)
      }
    Expression(_) => visitor.visit_expression(n)
    Pattern(_) => visitor.visit_pattern(n)
    TypeAnnotation(_) => visitor.visit_type(n)
    Case(_) => visitor.visit_case(n)
    Import(_) => visitor.visit_import(n)
    Comment(_) => visitor.visit_comment(n)
    Attribute(_) => visitor.visit_attribute(n)
    _ => visitor.visit_other(n)
  }
}

///|
/// Walk `root` (see `walk`) and call one `visitor` method per node:
/// functions (top-level or `let`) → `visit_function`; other declarations →
/// `visit_declaration`; expressions, patterns, types → `visit_expression`,
/// `visit_pattern`, `visit_type`; case branches → `visit_case`; imports,
/// comments, doc attributes → `visit_import`, `visit_comment`,
/// `visit_attribute`; every other node (doc comments included) →
/// `visit_other`. The method's `Control` steers the walk; `leave` runs after
/// each node's children.
///
/// A visitor needs its own type, so this example is not a doc test (a doc
/// test holds only `test` blocks). The cookbook article "Choose a traversal"
/// has a tested visitor:
/// https://github.com/moonrockz/krueger/blob/main/docs/cookbook/traversal.mbt.md
///
/// ```mbt nocheck
/// struct Names {
///   functions : Array[String]
///   mut patterns : Int
/// }
///
/// impl @syntax.Visitor for Names with fn visit_function(self, n) {
///   match n {
///     Declaration({ value: FunctionDeclaration(f), .. }, _) =>
///       self.functions.push(f.declaration.value.name.value)
///     _ => ()
///   }
///   Continue
/// }
///
/// impl @syntax.Visitor for Names with fn visit_pattern(self, _) {
///   self.patterns += 1
///   Continue
/// }
///
/// test {
///   let src = "module Main exposing (..)\n\nadd x y =\n    x + y\n\nz = 0\n"
///   let result = @parser.parse_module(
///     @scanner.SourceText::new(src),
///     @scanner.DefaultScanner::new(),
///   )
///   let root = @syntax.NodeRef::of_result(result).unwrap()
///   let names = { functions: [], patterns: 0, }
///   @syntax.accept(root, names)
///   debug_inspect(names.functions, content="[\"add\", \"z\"]")
///   inspect(names.patterns, content="2")
/// }
/// ```
pub fn[V : Visitor] accept(root : NodeRef, visitor : V) -> Unit {
  walk(root, n => dispatch(visitor, n), leave=n => visitor.leave(n))
}
