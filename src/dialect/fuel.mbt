///|
/// The default fuel of the parser: how deep it goes before it refuses with
/// `TOO MUCH NESTING` (`KR-PARSE-010`).
///
/// Fuel is a nesting counter, as the Scala compiler's `-Xmax-fuel`: a walk
/// spends units when it enters a nested construct and gets them back when
/// it leaves. The costs are internal; the caller sees one number. With the
/// default, the parser accepts 150 nested parentheses, lists, records,
/// lambdas, `let`s or `case`s, and 75 nested constructor patterns or type
/// applications (they count two levels each). More fuel needs more stack,
/// and the stack is the host's setting, not krueger's: see the cookbook
/// article "Set the nesting budget".
pub const DEFAULT_FUEL : Int32 = 1200
