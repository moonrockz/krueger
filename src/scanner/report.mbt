///|
/// Colours of `elm make` reports. `Vivid*` are the bright variants; in the
/// `--report=json` output they are upper case (`"RED"`), the others lower case.
pub(all) enum Color {
  Red
  Yellow
  Green
  Cyan
  Magenta
  Blue
  Black
  White
  VividRed
  VividYellow
  VividGreen
  VividCyan
  VividMagenta
  VividBlue
  VividBlack
  VividWhite
} derive(Eq, Debug)

///|
/// A piece of report text: plain, or styled like `elm make` styles code and
/// keywords.
pub(all) enum Chunk {
  Plain(String)
  Styled(text~ : String, color~ : Color?, bold~ : Bool, underline~ : Bool)
} derive(Eq, Debug)

///|
/// One block of a report. `Excerpt` shows the source lines of `context` with
/// markers under `highlight`; renderers read the lines from the source.
pub(all) enum Block {
  Text(Array[Chunk])
  Excerpt(context~ : Span, highlight~ : Span)
  Hint(Array[Chunk])
  Note(Array[Chunk])
  Example(String)
} derive(Eq, Debug)

///|
/// Elm code inside a paragraph, in yellow as `elm make` shows it.
pub fn Chunk::code(text : String) -> Chunk {
  Styled(text~, color=Some(Yellow), bold=false, underline=false)
}

///|
/// An Elm keyword inside a paragraph, in bright cyan as `elm make` shows it.
pub fn Chunk::keyword(text : String) -> Chunk {
  Styled(text~, color=Some(VividCyan), bold=false, underline=false)
}

///|
/// The colour name in `elm make --report=json` output.
pub fn Color::json_name(self : Color) -> String {
  match self {
    Red => "red"
    Yellow => "yellow"
    Green => "green"
    Cyan => "cyan"
    Magenta => "magenta"
    Blue => "blue"
    Black => "black"
    White => "white"
    VividRed => "RED"
    VividYellow => "YELLOW"
    VividGreen => "GREEN"
    VividCyan => "CYAN"
    VividMagenta => "MAGENTA"
    VividBlue => "BLUE"
    VividBlack => "BLACK"
    VividWhite => "WHITE"
  }
}
