///|
/// A Markdown inline, as elm-format's Markdown parser (its fork of
/// Cheapskate, `Cheapskate.Types.Inline`) reads it.
priv enum Inline {
  Str(String)
  Space
  SoftBreak
  LineBreak
  Emph(Array[Inline])
  Strong(Array[Inline])
  Code(String)
  Link(Array[Inline], Target, String)
  Image(Array[Inline], String, String)
  Entity(String)
  RawHtml(String)
}

///|
/// The target of a link: a URL, or the label of a reference.
priv enum Target {
  Url(String)
  Ref(String)
}

///|
/// Raised when inlines nest deeper than `max_inline_depth`. `format_doc`
/// then keeps the doc comment as it is.
priv suberror TooDeep

///|
/// The deepest nesting of inlines (emphasis, links, link titles and
/// parentheses in URLs) that the inline parser reads. It recurses once per
/// level, so this limit keeps the stack small on every target.
let max_inline_depth : Int = 32

///|
/// A port of Cheapskate's inline parser (`Cheapskate.Inlines`), which
/// backtracks: a parse function that fails returns `None` and leaves the
/// position where it was.
priv struct InlineParser {
  chars : Array[Char]
  mut pos : Int
  mut depth : Int
}

///|
fn InlineParser::new(text : String, depth : Int) -> InlineParser {
  { chars: text.to_array(), pos: 0, depth, }
}

///|
fn InlineParser::enter(self : InlineParser) -> Unit raise TooDeep {
  self.depth += 1
  if self.depth > max_inline_depth {
    raise TooDeep
  }
}

///|
fn InlineParser::leave(self : InlineParser) -> Unit {
  self.depth -= 1
}

///|
fn InlineParser::peek(self : InlineParser) -> Char? {
  self.chars.get(self.pos)
}

///|
/// The character before the position, in this parse.
fn InlineParser::last_char(self : InlineParser) -> Char? {
  if self.pos > 0 {
    self.chars.get(self.pos - 1)
  } else {
    None
  }
}

///|
fn InlineParser::at_end(self : InlineParser) -> Bool {
  self.pos >= self.chars.length()
}

///|
/// Consume `c` when it is next.
fn InlineParser::char(self : InlineParser, c : Char) -> Bool {
  if self.peek() == Some(c) {
    self.pos += 1
    true
  } else {
    false
  }
}

///|
/// Consume the next character when it satisfies `f`.
fn InlineParser::satisfy(self : InlineParser, f : (Char) -> Bool) -> Char? {
  match self.peek() {
    Some(c) if f(c) => {
      self.pos += 1
      Some(c)
    }
    _ => None
  }
}

///|
/// Whether `s` comes next (nothing is consumed).
fn InlineParser::looking_at(self : InlineParser, s : String) -> Bool {
  let mut i = self.pos
  for c in s {
    guard self.chars.get(i) == Some(c) else { return false }
    i += 1
  }
  true
}

///|
/// Consume `s` when it comes next.
fn InlineParser::string(self : InlineParser, s : String) -> Bool {
  if self.looking_at(s) {
    self.pos += s.char_length()
    true
  } else {
    false
  }
}

///|
fn InlineParser::take_while(self : InlineParser, f : (Char) -> Bool) -> String {
  let sb = StringBuilder()
  while self.peek() is Some(c) && f(c) {
    sb.write_char(c)
    self.pos += 1
  }
  sb.to_string()
}

///|
fn InlineParser::take_while1(
  self : InlineParser,
  f : (Char) -> Bool,
) -> String? {
  let t = self.take_while(f)
  if t.is_empty() {
    None
  } else {
    Some(t)
  }
}

///|
/// Cheapskate `isWhitespace`.
fn is_md_whitespace(c : Char) -> Bool {
  c is (' ' | '\t' | '\n' | '\r')
}

///|
fn is_ascii_alnum(c : Char) -> Bool {
  c is ('a'..='z' | 'A'..='Z' | '0'..='9')
}

///|
/// Cheapskate `isEscapable`: ASCII punctuation and symbols.
fn is_escapable(c : Char) -> Bool {
  c is ('!'..='/' | ':'..='@' | '['..='`' | '{'..='~')
}

///|
fn in_ranges(ranges : FixedArray[Int], c : Char) -> Bool {
  let n = c.to_int()
  let mut lo = 0
  let mut hi = ranges.length() / 2 - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    if n < ranges[mid * 2] {
      hi = mid - 1
    } else if n > ranges[mid * 2 + 1] {
      lo = mid + 1
    } else {
      return true
    }
  }
  false
}

///|
/// Haskell `isSpace`.
fn is_space(c : Char) -> Bool {
  in_ranges(space_ranges, c)
}

///|
/// Haskell `isLetter`.
fn is_letter(c : Char) -> Bool {
  in_ranges(letter_ranges, c)
}

///|
/// Haskell `isAlphaNum`.
fn is_alnum(c : Char) -> Bool {
  in_ranges(alnum_ranges, c)
}

///|
/// `text` without the characters at its start that satisfy `f`.
fn strip_start_by(text : String, f : (Char) -> Bool) -> String {
  let chars = text.to_array()
  let mut i = 0
  while i < chars.length() && f(chars[i]) {
    i += 1
  }
  String::from_array(chars[i:])
}

///|
/// `text` without the characters at its end that satisfy `f`.
fn strip_end_by(text : String, f : (Char) -> Bool) -> String {
  let chars = text.to_array()
  let mut n = chars.length()
  while n > 0 && f(chars[n - 1]) {
    n -= 1
  }
  String::from_array(chars[:n])
}

///|
/// Data.Text `strip`.
fn strip(text : String) -> String {
  strip_end_by(strip_start_by(text, is_space), is_space)
}

///|
/// The URI schemes that Cheapskate links without angle brackets, in lower
/// and upper case.
let schemes : Array[String] = [
  "coap", "doi", "javascript", "aaa", "aaas", "about", "acap", "cap", "cid", "crid",
  "data", "dav", "dict", "dns", "file", "ftp", "geo", "go", "gopher", "h323", "http",
  "https", "iax", "icap", "im", "imap", "info", "ipp", "iris", "iris.beep", "iris.xpc",
  "iris.xpcs", "iris.lwz", "ldap", "mailto", "mid", "msrp", "msrps", "mtqp", "mupdate",
  "news", "nfs", "ni", "nih", "nntp", "opaquelocktoken", "pop", "pres", "rtsp", "service",
  "session", "shttp", "sieve", "sip", "sips", "sms", "snmp", "soap.beep", "soap.beeps",
  "tag", "tel", "telnet", "tftp", "thismessage", "tn3270", "tip", "tv", "urn", "vemmi",
  "ws", "wss", "xcon", "xcon-userid", "xmlrpc.beep", "xmlrpc.beeps", "xmpp", "z39.50r",
  "z39.50s", "adiumxtra", "afp", "afs", "aim", "apt", "attachment", "aw", "beshare",
  "bitcoin", "bolo", "callto", "chrome", "chrome-extension", "com-eventbrite-attendee",
  "content", "cvs", "dlna-playsingle", "dlna-playcontainer", "dtn", "dvb", "ed2k",
  "facetime", "feed", "finger", "fish", "gg", "git", "gizmoproject", "gtalk", "hcp",
  "icon", "ipn", "irc", "irc6", "ircs", "itms", "jar", "jms", "keyparc", "lastfm",
  "ldaps", "magnet", "maps", "market", "message", "mms", "ms-help", "msnim", "mumble",
  "mvn", "notes", "oid", "palm", "paparazzi", "platform", "proxy", "psyc", "query",
  "res", "resource", "rmi", "rsync", "rtmp", "secondlife", "sftp", "sgn", "skype",
  "smb", "soldat", "spotify", "ssh", "steam", "svn", "teamspeak", "things", "udp",
  "unreal", "ut2004", "ventrilo", "view-source", "webcal", "wtai", "wyciwyg", "xfire",
  "xri", "ymsgr",
]

///|
fn is_scheme(t : String) -> Bool {
  schemes.contains(t) || (t == t.to_upper() && schemes.contains(t.to_lower()))
}

///|
/// Parse `text` into inlines (Cheapskate `parseInlines`). `depth` is the
/// nesting depth of the parse that reads `text`.
fn parse_inlines(
  text : String,
  depth? : Int = 0,
) -> Array[Inline] raise TooDeep {
  let p = InlineParser::new(text, depth)
  let out = []
  while !p.at_end() {
    guard p.inline() is Some(xs) else { break }
    out.append(xs)
  }
  out
}

///|
/// Cheapskate `pInline`: the first of the inline parsers that succeeds.
fn InlineParser::inline(self : InlineParser) -> Array[Inline]? raise TooDeep {
  self.enter()
  let start = self.pos
  let result = if self.ascii_str() is Some(r) {
    Some(r)
  } else if self.space() is Some(r) {
    Some([r])
  } else if self.enclosure('*') is Some(r) {
    Some(r)
  } else if !(self.last_char() is Some(c) && is_alnum(c)) &&
    self.enclosure('_') is Some(r) {
    Some(r)
  } else if self.code() is Some((r, _)) {
    Some([r])
  } else if self.link() is Some(r) {
    Some(r)
  } else if self.image() is Some(r) {
    Some(r)
  } else if self.raw_html() is Some(r) {
    Some([RawHtml(r)])
  } else if self.autolink() is Some(r) {
    Some([r])
  } else if self.entity() is Some(r) {
    Some([Entity(r)])
  } else {
    self.sym()
  }
  if result is None {
    self.pos = start
  }
  self.leave()
  result
}

///|
/// Cheapskate `pAsciiStr`: ASCII letters and digits, or a URI when they
/// name a scheme and a `:` follows.
fn InlineParser::ascii_str(self : InlineParser) -> Array[Inline]? {
  let start = self.pos
  guard self.take_while1(is_ascii_alnum) is Some(t) else { return None }
  if self.peek() == Some(':') && is_scheme(t) {
    match self.uri(t) {
      Some(r) => Some(r)
      None => {
        self.pos = start
        None
      }
    }
  } else {
    Some([Str(t)])
  }
}

///|
/// Cheapskate `pSpace`.
fn InlineParser::space(self : InlineParser) -> Inline? {
  guard self.take_while1(is_md_whitespace) is Some(ss) else { return None }
  if ss.contains("\n") {
    if ss.has_prefix("  ") {
      Some(LineBreak)
    } else {
      Some(SoftBreak)
    }
  } else {
    Some(Space)
  }
}

///|
/// Cheapskate `pUri`: the URI after `scheme`, without one closing
/// punctuation character.
fn InlineParser::uri(self : InlineParser, scheme : String) -> Array[Inline]? {
  let start = self.pos
  guard self.char(':') else { return None }
  let sb = StringBuilder()
  let mut open = 0
  while self.peek() is Some(c) {
    let go = match c {
      ' ' | '\n' => false
      '(' => {
        open += 1
        true
      }
      ')' =>
        if open > 0 {
          open -= 1
          true
        } else {
          false
        }
      '+' | '/' => true
      _ => !is_space(c)
    }
    guard go else { break }
    sb.write_char(c)
    self.pos += 1
  }
  let x = sb.to_string().to_array()
  guard x.length() > 0 else {
    self.pos = start
    return None
  }
  let last = x[x.length() - 1]
  if last is ('.' | ';' | '?' | '!' | ':' | ',') {
    let raw = scheme + ":" + String::from_array(x[:x.length() - 1])
    Some([auto_link(raw), Str(last.to_string())])
  } else {
    Some([auto_link(scheme + ":" + String::from_array(x))])
  }
}

///|
/// Cheapskate `pEnclosure`: text in `*`, `**`, `_` or `__`.
fn InlineParser::enclosure(
  self : InlineParser,
  c : Char,
) -> Array[Inline]? raise TooDeep {
  guard self.take_while1(x => x == c) is Some(cs) else { return None }
  if self.space() is Some(s) {
    return Some([Str(cs), s])
  }
  match cs.char_length() {
    3 => Some(self.three(c))
    2 => Some(self.two(c, []))
    1 => Some(self.one(c, []))
    _ => Some([Str(cs)])
  }
}

///|
/// `[f(xs)]`, or nothing when `xs` is empty (Cheapskate `single`).
fn single(f : (Array[Inline]) -> Inline, xs : Array[Inline]) -> Array[Inline] {
  if xs.is_empty() {
    []
  } else {
    [f(xs)]
  }
}

///|
fn concat_inlines(a : Array[Inline], b : Array[Inline]) -> Array[Inline] {
  let out = a.copy()
  out.append(b)
  out
}

///|
/// Cheapskate `pOne`: inlines until one `c`, as emphasis.
fn InlineParser::one(
  self : InlineParser,
  c : Char,
  prefix : Array[Inline],
) -> Array[Inline] raise TooDeep {
  let contents = []
  while true {
    let save = self.pos
    if self.peek() != Some(c) && self.inline() is Some(xs) {
      contents.append(xs)
      continue
    }
    self.pos = save
    let pair = String::make(2, c)
    if self.string(pair) && self.peek() != Some(c) {
      contents.append(self.two(c, []))
      continue
    }
    self.pos = save
    break
  }
  let inner = concat_inlines(prefix, contents)
  if self.char(c) {
    single(xs => Emph(xs), inner)
  } else {
    concat_inlines([Str(c.to_string())], inner)
  }
}

///|
/// Cheapskate `pTwo`: inlines until two `c`, as strong emphasis.
fn InlineParser::two(
  self : InlineParser,
  c : Char,
  prefix : Array[Inline],
) -> Array[Inline] raise TooDeep {
  let pair = String::make(2, c)
  let contents = []
  while !self.looking_at(pair) {
    guard self.inline() is Some(xs) else { break }
    contents.append(xs)
  }
  let inner = concat_inlines(prefix, contents)
  if self.string(pair) {
    single(xs => Strong(xs), inner)
  } else {
    concat_inlines([Str(pair)], inner)
  }
}

///|
/// Cheapskate `pThree`: inlines after three `c`.
fn InlineParser::three(
  self : InlineParser,
  c : Char,
) -> Array[Inline] raise TooDeep {
  let contents = []
  while self.peek() != Some(c) {
    guard self.inline() is Some(xs) else { break }
    contents.append(xs)
  }
  if self.string(String::make(2, c)) {
    self.one(c, single(xs => Strong(xs), contents))
  } else if self.char(c) {
    self.two(c, single(xs => Emph(xs), contents))
  } else {
    concat_inlines([Str(String::make(3, c))], contents)
  }
}

///|
/// Cheapskate `pCode'`: a code span, and its text as written.
fn InlineParser::code(self : InlineParser) -> (Inline, String)? {
  let start = self.pos
  guard self.take_while1(x => x == '`') is Some(ticks) else { return None }
  let contents = StringBuilder()
  while true {
    let save = self.pos
    if self.string(ticks) && self.peek() != Some('`') {
      let text = contents.to_string()
      return Some((Code(strip(text)), ticks + text + ticks))
    }
    self.pos = save
    if self.take_while1(x => x != '`') is Some(t) {
      contents.write_string(t)
    } else if self.take_while1(x => x == '`') is Some(t) {
      contents.write_string(t)
    } else {
      break
    }
  }
  self.pos = start
  None
}

///|
/// Cheapskate `pEscaped`: a backslash and an escapable character, as that
/// character.
fn InlineParser::escaped(self : InlineParser) -> Char? {
  let start = self.pos
  if self.char('\\') && self.satisfy(is_escapable) is Some(c) {
    Some(c)
  } else {
    self.pos = start
    None
  }
}

///|
/// Cheapskate `pLinkLabel`: the text in `[` and `]`, without escapes.
fn InlineParser::label(self : InlineParser) -> String? raise TooDeep {
  let start = self.pos
  guard self.char('[') else { return None }
  self.enter()
  let sb = StringBuilder()
  let mut ok = false
  while true {
    if self.char(']') {
      ok = true
      break
    }
    if self.take_while1(c => !(c is ('`' | '[' | ']' | '\\'))) is Some(t) {
      sb.write_string(t)
    } else if self.escaped() is Some(c) {
      sb.write_char(c)
    } else if self.label() is Some(t) {
      sb.write_string("[" + t + "]")
    } else if self.code() is Some((_, raw)) {
      sb.write_string(raw)
    } else {
      break
    }
  }
  self.leave()
  if ok {
    Some(sb.to_string())
  } else {
    self.pos = start
    None
  }
}

///|
/// Cheapskate `scanSpaces`.
fn InlineParser::scan_spaces(self : InlineParser) -> Unit {
  ignore(self.take_while(c => c == ' '))
}

///|
/// Cheapskate `scanSpnl`: spaces, and a line break with spaces after it.
fn InlineParser::scan_spnl(self : InlineParser) -> Unit {
  self.scan_spaces()
  if self.char('\n') {
    self.scan_spaces()
  }
}

///|
/// Cheapskate `pLink`: a link, or text in brackets as a reference link.
fn InlineParser::link(self : InlineParser) -> Array[Inline]? raise TooDeep {
  guard self.label() is Some(raw) else { return None }
  let text = parse_inlines(raw, depth=self.depth)
  if self.inline_link(text) is Some(l) {
    return Some([l])
  }
  let save = self.pos
  self.scan_spnl()
  let reference = match self.label() {
    Some(r) => r
    None => {
      self.pos = save
      raw
    }
  }
  Some([Link(text, Ref(reference), "")])
}

///|
/// Cheapskate `pInlineLink`: `(url "title")` after a label.
fn InlineParser::inline_link(
  self : InlineParser,
  text : Array[Inline],
) -> Inline? raise TooDeep {
  let start = self.pos
  guard self.char('(') else { return None }
  self.scan_spaces()
  guard self.link_url() is Some(url) else {
    self.pos = start
    return None
  }
  let save = self.pos
  self.scan_spnl()
  let title = match self.link_title() {
    Some(t) => {
      self.scan_spaces()
      t
    }
    None => {
      self.pos = save
      ""
    }
  }
  guard self.char(')') else {
    self.pos = start
    return None
  }
  Some(Link(text, Url(url), title))
}

///|
/// Cheapskate `pSatisfy`: a character that satisfies `f`, or a backslash
/// and an escapable character that does.
fn InlineParser::satisfy_escaped(
  self : InlineParser,
  f : (Char) -> Bool,
) -> Char? {
  if self.satisfy(c => c != '\\' && f(c)) is Some(c) {
    return Some(c)
  }
  let start = self.pos
  if self.char('\\') && self.satisfy(c => is_escapable(c) && f(c)) is Some(c) {
    Some(c)
  } else {
    self.pos = start
    None
  }
}

///|
/// Cheapskate `pLinkUrl`: a URL in `<` and `>`, or a URL with balanced
/// parentheses and no spaces.
fn InlineParser::link_url(self : InlineParser) -> String? raise TooDeep {
  let start = self.pos
  if self.char('<') {
    let sb = StringBuilder()
    while !self.char('>') {
      guard self.satisfy_escaped(c => c != '\r' && c != '\n') is Some(c) else {
        self.pos = start
        return None
      }
      sb.write_char(c)
    }
    return Some(sb.to_string())
  }
  Some(self.url_chunks())
}

///|
/// The chunks of a URL without angle brackets (Cheapskate `regChunk` and
/// `parenChunk`).
fn InlineParser::url_chunks(self : InlineParser) -> String raise TooDeep {
  let sb = StringBuilder()
  while true {
    if self.url_chunk() is Some(t) {
      sb.write_string(t)
    } else if self.paren_chunk() is Some(t) {
      sb.write_string(t)
    } else {
      break
    }
  }
  sb.to_string()
}

///|
fn InlineParser::url_chunk(self : InlineParser) -> String? {
  if self.take_while1(c => !(c is (' ' | '\n' | '(' | ')' | '\\'))) is Some(t) {
    Some(t)
  } else if self.escaped() is Some(c) {
    Some(c.to_string())
  } else {
    None
  }
}

///|
/// Cheapskate `parenChunk`: URL chunks in parentheses.
fn InlineParser::paren_chunk(self : InlineParser) -> String? raise TooDeep {
  let start = self.pos
  guard self.char('(') else { return None }
  self.enter()
  let sb = StringBuilder()
  let mut ok = false
  while true {
    if self.char(')') {
      ok = true
      break
    }
    if self.url_chunk() is Some(t) {
      sb.write_string(t)
    } else if self.paren_chunk() is Some(t) {
      sb.write_string(t)
    } else {
      break
    }
  }
  self.leave()
  if ok {
    Some("(" + sb.to_string() + ")")
  } else {
    self.pos = start
    None
  }
}

///|
/// Cheapskate `pLinkTitle`: a title in `"`, `'` or parentheses.
fn InlineParser::link_title(self : InlineParser) -> String? raise TooDeep {
  let start = self.pos
  guard self.satisfy(c => c is ('"' | '\'' | '(')) is Some(c) else {
    return None
  }
  match self.peek() {
    None => {
      self.pos = start
      return None
    }
    Some(next) if is_md_whitespace(next) || next == ')' => {
      self.pos = start
      return None
    }
    Some(_) => ()
  }
  let ender = if c == '(' { ')' } else { c }
  self.enter()
  let sb = StringBuilder()
  let mut ok = false
  while true {
    let save = self.pos
    if self.char(ender) && !(self.peek() is Some(x) && is_alnum(x)) {
      ok = true
      break
    }
    self.pos = save
    if self.take_while1(x => x != ender && x != '\\') is Some(t) {
      sb.write_string(t)
    } else if self.escaped() is Some(x) {
      sb.write_char(x)
    } else if self.link_title() is Some(t) {
      sb.write_char(c)
      sb.write_string(t)
      sb.write_char(ender)
    } else {
      break
    }
  }
  self.leave()
  if ok {
    Some(sb.to_string())
  } else {
    self.pos = start
    None
  }
}

///|
/// Cheapskate `pImage`: `!` and a link.
fn InlineParser::image(self : InlineParser) -> Array[Inline]? raise TooDeep {
  guard self.char('!') else { return None }
  match self.link() {
    Some([Link(text, Url(url), title)]) => Some([Image(text, url, title)])
    Some(xs) => Some(concat_inlines([Str("!")], xs))
    None => Some([Str("!")])
  }
}

///|
/// Cheapskate `pRawHtml`: an HTML tag or comment, as written.
fn InlineParser::raw_html(self : InlineParser) -> String? {
  if self.html_tag() is Some(t) {
    Some(t)
  } else {
    self.html_comment()
  }
}

///|
/// Cheapskate `pHtmlTag`.
fn InlineParser::html_tag(self : InlineParser) -> String? {
  let start = self.pos
  guard self.char('<') else { return None }
  let closing = self.char('/')
  guard self.take_while1(c => is_ascii_alnum(c) || c == '?' || c == '!')
    is Some(name) else {
    self.pos = start
    return None
  }
  let attrs = StringBuilder()
  while self.html_attr() is Some(a) {
    attrs.write_string(a)
  }
  let final_ = self.take_while(c => is_space(c) || c == '/')
  guard self.char('>') else {
    self.pos = start
    return None
  }
  Some(
    "<" +
    (if closing { "/" } else { "" }) +
    name +
    attrs.to_string() +
    final_ +
    ">",
  )
}

///|
/// An attribute of an HTML tag (Cheapskate `attr`): it needs a `=`.
fn InlineParser::html_attr(self : InlineParser) -> String? {
  let start = self.pos
  let ss = self.take_while(is_space)
  guard self.satisfy(is_letter) is Some(x) else {
    self.pos = start
    return None
  }
  let xs = self.take_while(c => is_ascii_alnum(c) || c == ':')
  guard self.char('=') else {
    self.pos = start
    return None
  }
  let v = if self.quoted('"') is Some(q) {
    q
  } else if self.quoted('\'') is Some(q) {
    q
  } else if self.take_while1(is_alnum) is Some(t) {
    t
  } else {
    ""
  }
  Some(ss + x.to_string() + xs + "=" + v)
}

///|
/// Cheapskate `pQuoted`.
fn InlineParser::quoted(self : InlineParser, c : Char) -> String? {
  let start = self.pos
  guard self.char(c) else { return None }
  let contents = self.take_while(x => x != c)
  guard self.char(c) else {
    self.pos = start
    return None
  }
  Some(c.to_string() + contents + c.to_string())
}

///|
/// Cheapskate `pHtmlComment`.
fn InlineParser::html_comment(self : InlineParser) -> String? {
  let start = self.pos
  guard self.string("<!--") else { return None }
  let sb = StringBuilder()
  while !self.string("-->") {
    guard self.peek() is Some(c) else {
      self.pos = start
      return None
    }
    sb.write_char(c)
    self.pos += 1
  }
  Some("<!--" + sb.to_string() + "-->")
}

///|
/// Cheapskate `pAutolink`: `<scheme:...>` or `<name@host>`.
fn InlineParser::autolink(self : InlineParser) -> Inline? {
  let start = self.pos
  guard self.char('<') &&
    self.take_while1(c => c != ':' && c != '@') is Some(s) &&
    self.take_while1(c => c != '>' && c != ' ') is Some(rest) &&
    self.char('>') else {
    self.pos = start
    return None
  }
  if rest.has_prefix("@") {
    let t = s + rest
    Some(Link([Str(t)], Url("mailto:" + t), ""))
  } else if is_scheme(s) {
    Some(auto_link(s + rest))
  } else {
    self.pos = start
    None
  }
}

///|
/// Cheapskate `pEntity`: `&name;`, `&#digits;` or `&#xhex;`, as written.
fn InlineParser::entity(self : InlineParser) -> String? {
  let start = self.pos
  guard self.char('&') else { return None }
  let body = if self.take_while1(c => c.is_ascii_alphabetic()) is Some(t) {
    Some(t)
  } else if self.char('#') {
    if self.take_while1(c => c.is_ascii_digit()) is Some(t) {
      Some("#" + t)
    } else if self.satisfy(c => c is ('x' | 'X')) is Some(x) &&
      self.take_while1(c => c.is_ascii_hexdigit()) is Some(t) {
      Some("#" + x.to_string() + t)
    } else {
      None
    }
  } else {
    None
  }
  guard body is Some(b) && self.char(';') else {
    self.pos = start
    return None
  }
  Some("&" + b + ";")
}

///|
/// Cheapskate `pSym`: one character; a backslash escapes the next
/// character or makes a line break.
fn InlineParser::sym(self : InlineParser) -> Array[Inline]? {
  guard self.peek() is Some(c) else { return None }
  self.pos += 1
  if c != '\\' {
    return Some([Str(c.to_string())])
  }
  if self.satisfy(is_escapable) is Some(e) {
    Some([Str(e.to_string())])
  } else if self.char('\n') {
    Some([LineBreak])
  } else {
    Some([Str("\\")])
  }
}

///|
/// Cheapskate `autoLink`: a link whose text is the URL, entities kept.
fn auto_link(t : String) -> Inline {
  let text = []
  let p = InlineParser::new(t, 0)
  while !p.at_end() {
    if p.take_while1(c => c != '&') is Some(s) {
      text.push(Str(s))
    } else if p.entity() is Some(e) {
      text.push(Entity(e))
    } else {
      p.pos += 1
      text.push(Str("&"))
    }
  }
  Link(text, Url(t), "")
}

///|
/// The length of the longest run of `` ` `` in `text` (elm-format
/// `longestSpanOf`).
fn longest_backtick_run(text : String) -> Int {
  let mut longest = 0
  let mut current = 0
  for c in text {
    if c == '`' {
      current += 1
      if current > longest {
        longest = current
      }
    } else {
      current = 0
    }
  }
  longest
}

///|
/// Whether `url` is an absolute URL (elm-format `absoluteUrlRegex`): a
/// letter, one or more letters, digits, `+`, `.` or `-`, then `:`.
fn is_absolute_url(url : String) -> Bool {
  let chars = url.to_array()
  guard chars.length() >= 3 && chars[0].is_ascii_alphabetic() else {
    return false
  }
  let mut i = 1
  while i < chars.length() &&
        (is_ascii_alnum(chars[i]) || chars[i] is ('+' | '.' | '-')) {
    i += 1
  }
  i >= 2 && i < chars.length() && chars[i] == ':'
}

///|
/// The text of `inlines` as elm-format writes it (`formatMarkdownInline`).
/// With `fix`, the characters `\`, `` ` ``, `_` and `*` in text get a
/// backslash.
fn format_inlines(inlines : Array[Inline], fix : Bool) -> String {
  let sb = StringBuilder()
  for inline in inlines {
    sb.write_string(format_inline(inline, fix))
  }
  sb.to_string()
}

///|
fn format_inline(inline : Inline, fix : Bool) -> String {
  match inline {
    Str(text) =>
      if fix {
        let sb = StringBuilder()
        for c in text {
          if c is ('\\' | '`' | '_' | '*') {
            sb.write_char('\\')
          }
          sb.write_char(c)
        }
        sb.to_string()
      } else {
        text
      }
    Space => " "
    SoftBreak | LineBreak => "\n"
    Emph(xs) => "_" + format_inlines(xs, true) + "_"
    Strong(xs) => "**" + format_inlines(xs, true) + "**"
    Code(text) =>
      match longest_backtick_run(text) {
        0 => "`" + text + "`"
        n => {
          let delimiter = String::make(n + 1, '`')
          delimiter + " " + text + " " + delimiter
        }
      }
    Link(xs, Url(url), title) => {
      let text = format_inlines(xs, fix)
      let raw = format_inlines(xs, false)
      if raw == url && title == "" && is_absolute_url(url) {
        if fix {
          "<" + url + ">"
        } else {
          url
        }
      } else {
        "[" + text + "](" + url + format_title(title) + ")"
      }
    }
    Link(xs, Ref(reference), _) => {
      let text = format_inlines(xs, fix)
      if text == reference || reference == "" {
        "[" + text + "]"
      } else {
        "[" + text + "][" + reference + "]"
      }
    }
    Image(xs, url, title) =>
      "![" + format_inlines(xs, fix) + "](" + url + format_title(title) + ")"
    Entity(text) | RawHtml(text) => text
  }
}

///|
fn format_title(title : String) -> String {
  if title == "" {
    ""
  } else {
    " \"" + title + "\""
  }
}
