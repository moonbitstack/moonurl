// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Which component an octet is going into, and so which octets may stand for
/// themselves (RFC 3986 §2.2, §3).
///
/// `&` is ordinary inside a path and a separator inside a query. The grammar
/// answers that, not the caller.
pub(all) enum Kind {
  /// Unreserved only — everything else is escaped. This is what one piece of a
  /// query goes out as, since `&` and `=` inside a value must not read as the
  /// separators they look like.
  Bare
  /// `reg-name` (§3.2.2): unreserved and sub-delims.
  Host
  /// `userinfo` (§3.2.1): `reg-name` and `:`.
  Userinfo
  /// One `segment` (§3.3): `pchar`, so `/` is escaped and stays one segment.
  Segment
  /// A whole `path` (§3.3): `pchar` and `/`.
  Path
  /// `query` (§3.4): `pchar`, `/` and `?`.
  Query
  /// `fragment` (§3.5): the same set as `query`.
  Fragment
  /// A whole URI reference: everything the grammar allows anywhere, `%`
  /// included. What a `Location` header carries — the value is already a URI,
  /// and only the octets no URI may contain need escaping.
  Whole
} derive(Eq, Debug)

///|
pub extend Kind with Eq::{equal, not_equal}

///|
pub extend Kind with Debug::{to_repr}

///|
/// The strictest component, for when nothing says. Escaping an octet that did
/// not need it changes nothing; leaving one that did changes where the
/// component ends.
pub let kind : Kind = Bare

///|
/// A URI reference taken apart (RFC 3986 §3).
///
/// No `scheme` makes it relative (§4.2). No `host` means no authority, which is
/// not an empty host — `file:///tmp` has one, `mailto:x@y` has none.
///
/// Fields stay percent-encoded. Decoding on the way in would lose the difference
/// between a `/` that separates two segments and a `%2F` inside one.
pub(all) struct Url {
  scheme : String?
  userinfo : String?
  host : String?
  port : Int32?
  path : String
  query : String?
  fragment : String?
} derive(Eq, Debug)

///|
pub extend Url with Eq::{equal, not_equal}

///|
pub extend Url with Debug::{to_repr}

///|
/// Why a string is not a URI reference. Only the authority can fail: §B splits
/// any string at all into the five top-level components, and does not split
/// that one.
pub(all) suberror Refused {
  /// A port that is not digits, at this offset.
  Port(at~ : Int32)
  /// An IP-literal with no closing bracket, at the opening one's offset.
  Host(at~ : Int32)
  /// A host that is not a host: an empty one where one is needed, a code point
  /// the grammar forbids in one, or a name the IDNA rules refuse.
  Name(at~ : Int32)
  /// A number that reads as an IP address and is not one.
  Address(at~ : Int32)
  /// Input with no scheme, and no base to take one from.
  Scheme(at~ : Int32)
  /// A form-encoded string with more pairs than the limit.
  Pairs(limit~ : Int32)
  /// One form-encoded pair longer than the limit, in octets.
  Pair(limit~ : Int32, got~ : Int32)
} derive(Eq, Debug)

///|
pub extend Refused with Eq::{equal, not_equal}

///|
pub extend Refused with Debug::{to_repr}

// ------------------------------------------------------------ percent coding

///|
/// Percent-encode octets for `kind` (RFC 3986 §2.1).
///
/// Octets, not text: what travels inside a URI is whatever the caller encoded it
/// as. [`escape_text`] is the one that assumes UTF-8.
///
/// `spare` is for percent coding that is not going into a URI at all — gRPC's
/// `grpc-message` keeps all of printable ASCII but `%`, which is no component of
/// RFC 3986's. A URI component names its `kind` and leaves `spare` alone.
pub fn escape(
  raw : BytesView,
  kind~ : Kind = kind,
  spare~ : StringView = ""[:],
) -> String {
  let digits = "0123456789ABCDEF"
  let out = StringBuilder()
  for i = 0; i < raw.length(); i = i + 1 {
    let b = raw[i].to_int()
    if allowed(kind, b) || spared(spare, b) {
      out.write_char(b.unsafe_to_char())
    } else {
      out.write_char('%')
      out.write_char(digits[b / 16].unsafe_to_char())
      out.write_char(digits[b % 16].unsafe_to_char())
    }
  }
  out.to_string()
}

///|
/// Percent-encode text as UTF-8 (RFC 3986 §2.5).
pub fn escape_text(
  text : StringView,
  kind~ : Kind = kind,
  spare~ : StringView = ""[:],
) -> String {
  escape(@utf8.encode(text)[:], kind~, spare~)
}

///|
/// Undo percent-encoding (RFC 3986 §2.1).
///
/// A `%` without two hex digits after it stands for itself. This runs on request
/// targets and form bodies, where refusing the whole message over one stray `%`
/// helps nobody; [`escaped`] is for the caller who would rather be told.
pub fn unescape(raw : BytesView) -> Bytes {
  let out : Array[Byte] = []
  let mut i = 0
  while i < raw.length() {
    if raw[i] == b'%' && i + 2 < raw.length() {
      let hi = nibble(raw[i + 1])
      let lo = nibble(raw[i + 2])
      if hi >= 0 && lo >= 0 {
        out.push(((hi << 4) | lo).to_byte())
        i += 3
        continue
      }
    }
    out.push(raw[i])
    i += 1
  }
  Bytes::from_array(out)
}

///|
/// Undo percent-encoding and read the result as UTF-8, replacing what is not.
pub fn unescape_text(text : StringView) -> String {
  @utf8.decode_lossy(unescape(@utf8.encode(text)[:]))
}

///|
/// Whether every `%` is a complete escape and nothing outside `kind`'s set is
/// there unescaped — the check [`unescape`] does not make.
pub fn escaped(
  text : StringView,
  kind~ : Kind = kind,
  spare~ : StringView = ""[:],
) -> Bool {
  let raw = @utf8.encode(text)
  let mut i = 0
  while i < raw.length() {
    let b = raw[i].to_int()
    if b == 0x25 {
      if i + 2 >= raw.length() ||
        nibble(raw[i + 1]) < 0 ||
        nibble(raw[i + 2]) < 0 {
        return false
      }
      i += 3
    } else {
      if !allowed(kind, b) && !spared(spare, b) {
        return false
      }
      i += 1
    }
  }
  true
}

///|
/// Percent-encoding normalised (RFC 3986 §6.2.2.2): hex digits in upper case,
/// and escapes of unreserved octets written out plainly.
pub fn normalize_escapes(text : StringView) -> String {
  let digits = "0123456789ABCDEF"
  let raw = @utf8.encode(text)
  let out = StringBuilder()
  let mut i = 0
  while i < raw.length() {
    if raw[i] == b'%' && i + 2 < raw.length() {
      let hi = nibble(raw[i + 1])
      let lo = nibble(raw[i + 2])
      if hi >= 0 && lo >= 0 {
        let b = (hi << 4) | lo
        if unreserved(b) {
          out.write_char(b.unsafe_to_char())
        } else {
          out.write_char('%')
          out.write_char(digits[b / 16].unsafe_to_char())
          out.write_char(digits[b % 16].unsafe_to_char())
        }
        i += 3
        continue
      }
    }
    out.write_char(raw[i].to_int().unsafe_to_char())
    i += 1
  }
  out.to_string()
}

// ------------------------------------------------------------------- reading

///|
/// Take a URI reference apart (RFC 3986 §3, by the split §B states).
///
/// Any string splits, so what comes back is a reference even when it is one
/// nobody would write. Only the authority can be malformed.

///|
/// Which grammar decides what a string means. The two disagree about almost
/// everything a browser has to get right, and both are in the standard library
/// of every language that talks to the web.
pub(all) enum Syntax {
  /// RFC 3986: the generic grammar, where `http://h:80/` keeps its port and
  /// `http:g` is a URI with scheme `http`.
  Rfc3986
  /// The WHATWG URL Standard: special schemes with their default ports,
  /// backslashes as soliduses, IPv4 in any of its spellings, and a host name
  /// run through IDNA.
  Whatwg
} derive(Eq, Debug)

///|
pub extend Syntax with Eq::{equal, not_equal}

///|
pub extend Syntax with Debug::{to_repr}

///|
/// The grammar [`Url::decode`] uses when nothing says.
pub let rfc3986 : Syntax = Rfc3986

///|
/// Take a reference apart.
///
/// Under `Rfc3986` any string splits (§3), and only the authority can be
/// malformed. Under `Whatwg` the string is what a browser would make of it: a
/// reference that does not parse is refused rather than guessed at.
///
/// `base` resolves a relative reference against one, in whichever grammar is
/// asked for. The WHATWG algorithm takes the base as text and parses it again,
/// so a base that is itself not a URL is refused here too.
///
/// ```mbt check
/// test {
///   // RFC 3986 keeps the reference as it was written.
///   let url = @moonurl.Url::decode("HTTP://EXAMPLE.test:80/a/../b?q#f")
///   assert_eq(url.encode(), "HTTP://EXAMPLE.test:80/a/../b?q#f")
///   let whatwg = @moonurl.Url::decode(
///     "HTTP://EXAMPLE.test:80/a/../b",
///     syntax=@moonurl.Whatwg,
///   )
///   assert_eq(whatwg.encode(), "http://example.test/b")
/// }
/// ```
pub fn Url::decode(
  text : StringView,
  syntax~ : Syntax = rfc3986,
  base? : Url,
) -> Url raise Refused {
  match syntax {
    Rfc3986 => {
      let reference = split(text)
      match base {
        Some(base) => base.resolve(reference)
        None => reference
      }
    }
    Whatwg => whatwg_decode(text, base)
  }
}

///|
/// The RFC 3986 reading of a reference: the five components, split where §B
/// says to split them.
fn split(text : StringView) -> Url raise Refused {
  let n = text.length()
  let mut i = 0
  let scheme = scheme_of(text)
  match scheme {
    Some(name) => i = name.length() + 1
    None => ()
  }
  let mut userinfo = None
  let mut host = None
  let mut port = None
  if i + 1 < n && text[i].to_int() == 0x2F && text[i + 1].to_int() == 0x2F {
    i += 2
    let start = i
    while i < n && not_in(text[i].to_int(), [0x2F, 0x3F, 0x23]) {
      i += 1
    }
    let (u, h, p) = authority(text[start:i], start)
    userinfo = u
    host = Some(h)
    port = p
  }
  let start = i
  while i < n && not_in(text[i].to_int(), [0x3F, 0x23]) {
    i += 1
  }
  let path = text[start:i].to_owned()
  let mut query = None
  if i < n && text[i].to_int() == 0x3F {
    i += 1
    let start = i
    while i < n && text[i].to_int() != 0x23 {
      i += 1
    }
    query = Some(text[start:i].to_owned())
  }
  let mut fragment = None
  if i < n && text[i].to_int() == 0x23 {
    fragment = Some(text[i + 1:].to_owned())
  }
  { scheme, userinfo, host, port, path, query, fragment, }
}

///|
/// The scheme, if the reference has one (§3.1).
///
/// A colon alone does not make one: `2026:a` has none because a scheme starts
/// with a letter, `a/b:c` because the colon is inside the path. Get this wrong
/// and a relative reference becomes an absolute one with a made-up scheme.
fn scheme_of(text : StringView) -> String? {
  let n = text.length()
  if n == 0 || !alpha(text[0].to_int()) {
    return None
  }
  for i = 1; i < n; i = i + 1 {
    let b = text[i].to_int()
    if b == 0x3A {
      return Some(text[:i].to_owned())
    }
    let ok = alpha(b) || digit(b) || b == 0x2B || b == 0x2D || b == 0x2E
    if !ok {
      return None
    }
  }
  None
}

///|
/// Split an authority into userinfo, host and port (§3.2).
///
/// The last `@` divides, not the first: a userinfo may not hold an unescaped
/// one, so a second `@` is in the host.
///
/// The host is kept without its brackets — those are IP-literal syntax, not
/// address — and [`Url::encode`] puts them back when it sees a colon.
fn authority(
  text : StringView,
  at : Int32,
) -> (String?, String, Int32?) raise Refused {
  let n = text.length()
  let mut cut = -1
  for i = 0; i < n; i = i + 1 {
    if text[i].to_int() == 0x40 {
      cut = i
    }
  }
  let userinfo = if cut >= 0 { Some(text[:cut].to_owned()) } else { None }
  let rest = text[cut + 1:]
  let base = at + cut + 1
  let m = rest.length()
  let mut end = 0
  if m > 0 && rest[0].to_int() == 0x5B {
    let mut close = -1
    for i = 1; i < m; i = i + 1 {
      if rest[i].to_int() == 0x5D {
        close = i
        break
      }
    }
    guard close >= 0 else { raise Host(at=base) }
    end = close + 1
  } else {
    while end < m && rest[end].to_int() != 0x3A {
      end += 1
    }
  }
  let host = if m > 0 && rest[0].to_int() == 0x5B {
    rest[1:end - 1].to_owned()
  } else {
    rest[:end].to_owned()
  }
  if end >= m {
    return (userinfo, host, None)
  }
  guard rest[end].to_int() == 0x3A else { raise Port(at=base + end) }
  let text = rest[end + 1:]
  if text.length() == 0 {
    return (userinfo, host, None)
  }
  let mut value = 0
  for i = 0; i < text.length(); i = i + 1 {
    let b = text[i].to_int()
    guard digit(b) else { raise Port(at=base + end + 1 + i) }
    value = value * 10 + (b - 0x30)
  }
  (userinfo, host, Some(value))
}

// ------------------------------------------------------------------- writing

///|
/// A reference this shape, for building one rather than reading one.
pub fn Url::new(
  scheme? : String,
  userinfo? : String,
  host? : String,
  port? : Int32,
  path~ : String = "",
  query? : String,
  fragment? : String,
) -> Url {
  { scheme, userinfo, host, port, path, query, fragment, }
}

///|
/// Put the reference back together (RFC 3986 §5.3).
pub fn Url::encode(self : Url) -> String {
  let out = StringBuilder()
  match self.scheme {
    Some(scheme) => {
      out.write_string(scheme)
      out.write_char(':')
    }
    None => ()
  }
  match self.authority() {
    Some(authority) => {
      out.write_string("//")
      out.write_string(authority)
    }
    None => ()
  }
  // A path that begins with two soliduses, under no authority, would read
  // back as one: `./` in front of it keeps it a path (§4.5).
  if self.host is None && starts(self.path[:], "//") {
    out.write_string("/.")
  }
  out.write_string(self.path)
  match self.query {
    Some(query) => {
      out.write_char('?')
      out.write_string(query)
    }
    None => ()
  }
  match self.fragment {
    Some(fragment) => {
      out.write_char('#')
      out.write_string(fragment)
    }
    None => ()
  }
  out.to_string()
}

///|
/// The authority as one string, brackets restored around an IP-literal (§3.2).
pub fn Url::authority(self : Url) -> String? {
  match self.host {
    None => None
    Some(host) => {
      let out = StringBuilder()
      match self.userinfo {
        Some(userinfo) => {
          out.write_string(userinfo)
          out.write_char('@')
        }
        None => ()
      }
      if literal(host) {
        out.write_char('[')
        out.write_string(host)
        out.write_char(']')
      } else {
        out.write_string(host)
      }
      match self.port {
        Some(port) => {
          out.write_char(':')
          out.write_string(port.to_string())
        }
        None => ()
      }
      Some(out.to_string())
    }
  }
}

///|
/// A reference with a scheme and no fragment is a URI (§3); anything else is a
/// relative reference or a same-document one.
pub fn Url::is_absolute(self : Url) -> Bool {
  self.scheme is Some(_) && self.fragment is None
}

// ----------------------------------------------------------------- resolving

///|
/// Resolve `reference` against this base (RFC 3986 §5.2.2, strict).
///
/// Strict: a reference that repeats the base's scheme stays absolute. The
/// non-strict reading is for pre-1998 parsers and turns `http:g` into something
/// it does not say.
pub fn Url::resolve(self : Url, reference : Url) -> Url {
  if reference.scheme is Some(_) {
    return { ..reference, path: remove_dots(reference.path), }
  }
  if reference.host is Some(_) {
    return {
      ..reference,
      scheme: self.scheme,
      path: remove_dots(reference.path),
    }
  }
  if reference.path == "" {
    let query = match reference.query {
      Some(_) => reference.query
      None => self.query
    }
    return { ..self, query, fragment: reference.fragment, }
  }
  let path = if reference.path.length() > 0 &&
    reference.path[0].to_int() == 0x2F {
    remove_dots(reference.path)
  } else {
    remove_dots(merge(self, reference.path))
  }
  {
    scheme: self.scheme,
    userinfo: self.userinfo,
    host: self.host,
    port: self.port,
    path,
    query: reference.query,
    fragment: reference.fragment,
  }
}

///|
/// Graft a relative path onto the base's (§5.2.3).
fn merge(base : Url, path : String) -> String {
  if base.host is Some(_) && base.path == "" {
    return "/" + path
  }
  let mut cut = -1
  for i = 0; i < base.path.length(); i = i + 1 {
    if base.path[i].to_int() == 0x2F {
      cut = i
    }
  }
  if cut < 0 {
    path
  } else {
    base.path[:cut + 1].to_owned() + path
  }
}

///|
/// Take out the `.` and `..` segments (RFC 3986 §5.2.4).
///
/// The section's loop rather than a split-and-rejoin: the two differ at exactly
/// the inputs that matter — a trailing `..`, a path that climbs above its own
/// root, `/..//`.
pub fn remove_dots(path : String) -> String {
  let out : Array[String] = []
  let mut rest = path[:]
  while rest.length() > 0 {
    if starts(rest, "../") {
      rest = rest[3:]
    } else if starts(rest, "./") {
      rest = rest[2:]
    } else if starts(rest, "/./") {
      rest = rest[2:]
    } else if rest == "/." {
      rest = "/"[:]
    } else if starts(rest, "/../") {
      rest = rest[3:]
      let _ = out.pop()
    } else if rest == "/.." {
      rest = "/"[:]
      let _ = out.pop()
    } else if rest == "." || rest == ".." {
      rest = ""[:]
    } else {
      let mut i = if rest[0].to_int() == 0x2F { 1 } else { 0 }
      while i < rest.length() && rest[i].to_int() != 0x2F {
        i += 1
      }
      out.push(rest[:i].to_owned())
      rest = rest[i:]
    }
  }
  let joined = StringBuilder()
  for segment in out {
    joined.write_string(segment)
  }
  joined.to_string()
}

///|
/// Syntax-based normalisation (RFC 3986 §6.2.2): scheme and host to lower case,
/// escapes normalised, dot segments out.
///
/// Not §6.2.3: dropping `:80` is true of `http` and false in general, and this
/// package holds no register of schemes.
pub fn Url::normalize(self : Url) -> Url {
  {
    scheme: match self.scheme {
      Some(scheme) => Some(lower(scheme))
      None => None
    },
    userinfo: match self.userinfo {
      Some(userinfo) => Some(normalize_escapes(userinfo))
      None => None
    },
    host: match self.host {
      Some(host) => Some(lower(normalize_escapes(host)))
      None => None
    },
    port: self.port,
    path: remove_dots(normalize_escapes(self.path)),
    query: match self.query {
      Some(query) => Some(normalize_escapes(query))
      None => None
    },
    fragment: match self.fragment {
      Some(fragment) => Some(normalize_escapes(fragment))
      None => None
    },
  }
}

// ------------------------------------------------------------------ plumbing

///|
fn allowed(kind : Kind, b : Int32) -> Bool {
  if unreserved(b) {
    return true
  }
  match kind {
    Bare => false
    Host => sub_delim(b)
    Userinfo => sub_delim(b) || b == 0x3A
    Segment => sub_delim(b) || b == 0x3A || b == 0x40
    Path => sub_delim(b) || b == 0x3A || b == 0x40 || b == 0x2F
    Query | Fragment =>
      sub_delim(b) || b == 0x3A || b == 0x40 || b == 0x2F || b == 0x3F
    Whole => sub_delim(b) || gen_delim(b) || b == 0x25
  }
}

///|
fn spared(spare : StringView, b : Int32) -> Bool {
  if b >= 0x80 {
    return false
  }
  for c in spare {
    if c.to_int() == b {
      return true
    }
  }
  false
}

///|
fn alpha(b : Int32) -> Bool {
  (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
}

///|
fn digit(b : Int32) -> Bool {
  b >= 0x30 && b <= 0x39
}

///|
fn unreserved(b : Int32) -> Bool {
  alpha(b) || digit(b) || b == 0x2D || b == 0x2E || b == 0x5F || b == 0x7E
}

///|
fn sub_delim(b : Int32) -> Bool {
  b == 0x21 ||
  b == 0x24 ||
  b == 0x26 ||
  b == 0x27 ||
  b == 0x28 ||
  b == 0x29 ||
  b == 0x2A ||
  b == 0x2B ||
  b == 0x2C ||
  b == 0x3B ||
  b == 0x3D
}

///|
fn gen_delim(b : Int32) -> Bool {
  b == 0x3A ||
  b == 0x2F ||
  b == 0x3F ||
  b == 0x23 ||
  b == 0x5B ||
  b == 0x5D ||
  b == 0x40
}

///|
fn nibble(b : Byte) -> Int32 {
  let c = b.to_int()
  if c >= 0x30 && c <= 0x39 {
    c - 0x30
  } else if c >= 0x41 && c <= 0x46 {
    c - 0x37
  } else if c >= 0x61 && c <= 0x66 {
    c - 0x57
  } else {
    -1
  }
}

///|
fn not_in(b : Int32, set : Array[Int32]) -> Bool {
  for c in set {
    if b == c {
      return false
    }
  }
  true
}

///|
fn starts(text : StringView, prefix : String) -> Bool {
  if text.length() < prefix.length() {
    return false
  }
  for i = 0; i < prefix.length(); i = i + 1 {
    if text[i].to_int() != prefix[i].to_int() {
      return false
    }
  }
  true
}

///|
/// A colon in a host can only be an IP-literal; `reg-name` has none.
fn literal(host : String) -> Bool {
  for i = 0; i < host.length(); i = i + 1 {
    if host[i].to_int() == 0x3A {
      return true
    }
  }
  false
}

///|
fn lower(text : String) -> String {
  let out = StringBuilder()
  for i = 0; i < text.length(); i = i + 1 {
    let b = text[i].to_int()
    if b >= 0x41 && b <= 0x5A {
      out.write_char((b + 32).unsafe_to_char())
    } else {
      out.write_char(b.unsafe_to_char())
    }
  }
  out.to_string()
}
