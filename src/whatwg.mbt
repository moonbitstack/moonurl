// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The WHATWG URL parser (§4.4), the one a browser runs. It reads a string
// into the same [`Url`] the RFC 3986 reader fills in, so the two grammars
// share a type and a caller can keep one.

///|
/// A URL under construction: what the standard's algorithms hold while they
/// are reading, before it is a [`Url`].
priv struct Parts {
  mut scheme : String
  mut username : String
  mut password : String
  /// `None` is the standard's null host, which is not an empty one.
  mut host : String?
  mut port : Int32?
  /// The path's segments. An opaque path is one segment holding all of it,
  /// and `opaque_path` says which of the two this is.
  mut path : Array[String]
  mut opaque_path : Bool
  mut query : String?
  mut fragment : String?
}

///|
fn empty_parts() -> Parts {
  {
    scheme: "",
    username: "",
    password: "",
    host: None,
    port: None,
    path: [],
    opaque_path: false,
    query: None,
    fragment: None,
  }
}

///|
/// The states of the parser, named as the standard names them.
priv enum State {
  SchemeStart
  Scheme
  NoScheme
  SpecialRelativeOrAuthority
  PathOrAuthority
  Relative
  RelativeSlash
  SpecialAuthoritySlashes
  SpecialAuthorityIgnoreSlashes
  Authority
  Host
  Hostname
  Port
  File
  FileSlash
  FileHost
  PathStart
  Path
  OpaquePath
  Query
  Fragment
} derive(Eq)

// --------------------------------------------------------- percent encoding

///|
/// The percent-encode sets of §1.3: which code points a component escapes.
/// Each set contains the one before it, and the C0 control set is the floor.
priv enum Escaping {
  /// C0 controls and everything past `~`.
  C0Control
  /// A fragment, which may carry a `#`.
  Fragment
  /// A query, which may carry a backtick.
  Query
  /// A special scheme's query, where `'` is escaped too.
  SpecialQuery
  /// A path.
  Path
  /// Credentials, the strictest of them.
  Userinfo
}

///|
/// Whether `set` escapes a code point.
fn escapes(set : Escaping, point : Int32) -> Bool {
  if point < 0x20 || point > 0x7E {
    return true
  }
  match set {
    C0Control => false
    Fragment =>
      point == 0x20 ||
      point == 0x22 ||
      point == 0x3C ||
      point == 0x3E ||
      point == 0x60
    Query =>
      point == 0x20 ||
      point == 0x22 ||
      point == 0x23 ||
      point == 0x3C ||
      point == 0x3E
    SpecialQuery =>
      point == 0x20 ||
      point == 0x22 ||
      point == 0x23 ||
      point == 0x27 ||
      point == 0x3C ||
      point == 0x3E
    Path =>
      point == 0x20 ||
      point == 0x22 ||
      point == 0x23 ||
      point == 0x3C ||
      point == 0x3E ||
      point == 0x3F ||
      point == 0x5E ||
      point == 0x60 ||
      point == 0x7B ||
      point == 0x7D
    Userinfo =>
      point == 0x20 ||
      point == 0x22 ||
      point == 0x23 ||
      point == 0x2F ||
      point == 0x3A ||
      point == 0x3B ||
      point == 0x3C ||
      point == 0x3D ||
      point == 0x3E ||
      point == 0x3F ||
      point == 0x40 ||
      point == 0x5B ||
      point == 0x5C ||
      point == 0x5D ||
      point == 0x5E ||
      point == 0x60 ||
      point == 0x7B ||
      point == 0x7C ||
      point == 0x7D
  }
}

///|
/// Percent-encode one code point, as the UTF-8 it is, into `out`.
fn escape_point(out : StringBuilder, character : Char, set : Escaping) -> Unit {
  let point = character.to_int()
  if !escapes(set, point) {
    out.write_char(character)
    return
  }
  for byte in @utf8.encode(one(character)[:]) {
    let value = byte.to_int()
    out.write_char('%')
    out.write_char(hex_char(value >> 4))
    out.write_char(hex_char(value & 0xF))
  }
}

///|
fn escape_each(out : StringBuilder, text : StringView, set : Escaping) -> Unit {
  for character in text {
    escape_point(out, character, set)
  }
}

///|
/// Percent-encode a whole string for `set`.
fn escape_with(text : StringView, set : Escaping) -> String {
  let out = StringBuilder()
  escape_each(out, text, set)
  out.to_string()
}

///|
fn hex_char(value : Int32) -> Char {
  if value < 10 {
    (0x30 + value).unsafe_to_char()
  } else {
    (0x41 + value - 10).unsafe_to_char()
  }
}

///|
/// One character as a string.
fn one(character : Char) -> String {
  let out = StringBuilder()
  out.write_char(character)
  out.to_string()
}

///|
/// The code point at `pointer`, or `None` for the end of the input.
fn code(input : Array[Char], pointer : Int32) -> Char? {
  if pointer >= 0 && pointer < input.length() {
    Some(input[pointer])
  } else {
    None
  }
}

// ------------------------------------------------------------------ schemes

///|
fn letter(point : Int32) -> Bool {
  (point >= 0x41 && point <= 0x5A) || (point >= 0x61 && point <= 0x7A)
}

///|
fn number(character : Char) -> Bool {
  character >= '0' && character <= '9'
}

///|
fn plus_minus_dot(character : Char) -> Bool {
  character == '+' || character == '-' || character == '.'
}

///|
fn down(character : Char) -> Char {
  let point = character.to_int()
  if point >= 0x41 && point <= 0x5A {
    (point + 32).unsafe_to_char()
  } else {
    character
  }
}

///|
/// The six schemes the standard gives a port and a set of rules (its "special
/// schemes").
fn special(scheme : StringView) -> Bool {
  port_of(scheme) is Some(_) || scheme == "file"
}

///|
/// The port a scheme means when none is written.
fn port_of(scheme : StringView) -> Int32? {
  match scheme {
    "ftp" => Some(21)
    "http" => Some(80)
    "https" => Some(443)
    "ws" => Some(80)
    "wss" => Some(443)
    _ => None
  }
}

// ------------------------------------------------------------------ parsing

///|
/// Read `text` as the standard would, optionally against a base.
fn whatwg_decode(text : StringView, base : Url?) -> Url raise Refused {
  let base = match base {
    Some(base) => Some(parts_of(base))
    None => None
  }
  to_url(parse(text, base, None, None))
}

///|
/// The parts of an existing URL, read back the way the standard reads a base:
/// through its serialisation.
fn parts_of(url : Url) -> Parts raise Refused {
  parse(url.encode()[:], None, None, None)
}

///|
/// The basic URL parser (§4.4).
///
/// `seed` and `only` are the state-only arguments the constructors and
/// the setters use: with them, the parser modifies the URL it is given instead
/// of building one, and stops where the setter's value ends.
fn parse(
  text : StringView,
  base : Parts?,
  seed : Parts?,
  only : State?,
) -> Parts raise Refused {
  // Trimming belongs to reading a whole URL; a setter's value is taken as it
  // is, so that a leading space reaches the path as `%20`.
  let input = clean(text, trim=seed is None && only is None)
  let n = input.length()
  let url = match seed {
    Some(seed) => seed
    None => empty_parts()
  }
  let mut state = match only {
    Some(state) => state
    None => SchemeStart
  }
  let mut buffer : Array[Char] = []
  let mut at_sign = false
  let mut in_brackets = false
  let mut password_token = false
  let mut host_at = 0
  let mut pointer = 0
  while true {
    let c = code(input, pointer)
    match state {
      SchemeStart =>
        match c {
          Some(character) if letter(character.to_int()) => {
            buffer.push(down(character))
            state = Scheme
          }
          _ =>
            if only is None {
              state = NoScheme
              pointer -= 1
            } else {
              raise Scheme(at=pointer)
            }
        }
      Scheme =>
        match c {
          Some(character) if letter(character.to_int()) ||
            number(character) ||
            plus_minus_dot(character) => buffer.push(down(character))
          Some(':') => {
            if only is Some(_) {
              let name = text_of(buffer)
              if special(url.scheme) != special(name[:]) {
                return url
              }
              if (credentials(url) || url.port is Some(_)) && name == "file" {
                return url
              }
              if url.scheme == "file" && url.host is Some("") {
                return url
              }
            }
            url.scheme = text_of(buffer)
            if only is Some(_) {
              if url.port == port_of(url.scheme[:]) {
                url.port = None
              }
              return url
            }
            buffer = []
            if url.scheme == "file" {
              state = File
            } else if special(url.scheme[:]) {
              match base {
                Some(base) if base.scheme == url.scheme =>
                  state = SpecialRelativeOrAuthority
                _ => state = SpecialAuthoritySlashes
              }
            } else if code(input, pointer + 1) is Some('/') {
              state = PathOrAuthority
              pointer += 1
            } else {
              // A scheme with no authority and no path: an opaque_path path follows.
              url.path = [""]
              url.opaque_path = true
              state = OpaquePath
            }
          }
          _ =>
            if only is None {
              buffer = []
              state = NoScheme
              pointer = -1
            } else {
              raise Scheme(at=pointer)
            }
        }
      NoScheme =>
        match base {
          None => raise Scheme(at=pointer)
          Some(base) =>
            if base.opaque_path && c != Some('#') {
              raise Scheme(at=pointer)
            } else if base.opaque_path {
              url.scheme = base.scheme
              url.path = base.path.copy()
              url.opaque_path = true
              url.query = base.query
              url.fragment = Some("")
              state = Fragment
            } else if base.scheme != "file" {
              state = Relative
              pointer -= 1
            } else {
              state = File
              pointer -= 1
            }
        }
      SpecialRelativeOrAuthority =>
        if c == Some('/') && code(input, pointer + 1) == Some('/') {
          state = SpecialAuthorityIgnoreSlashes
          pointer += 1
        } else {
          state = Relative
          pointer -= 1
        }
      PathOrAuthority =>
        if c == Some('/') {
          state = Authority
        } else {
          state = Path
          pointer -= 1
        }
      Relative =>
        match base {
          None => raise Scheme(at=pointer)
          Some(base) => {
            url.scheme = base.scheme
            if c == Some('/') || (special(url.scheme[:]) && c == Some('\\')) {
              state = RelativeSlash
            } else {
              url.username = base.username
              url.password = base.password
              url.host = base.host
              url.port = base.port
              url.path = base.path.copy()
              url.query = base.query
              if c == Some('?') {
                url.query = Some("")
                state = Query
              } else if c == Some('#') {
                url.fragment = Some("")
                state = Fragment
              } else if c is Some(_) {
                url.query = None
                shorten(url)
                state = Path
                pointer -= 1
              }
            }
          }
        }
      RelativeSlash =>
        if special(url.scheme[:]) && (c == Some('/') || c == Some('\\')) {
          state = SpecialAuthorityIgnoreSlashes
        } else if c == Some('/') {
          state = Authority
        } else {
          match base {
            None => raise Scheme(at=pointer)
            Some(base) => {
              url.username = base.username
              url.password = base.password
              url.host = base.host
              url.port = base.port
            }
          }
          state = Path
          pointer -= 1
        }
      SpecialAuthoritySlashes =>
        if c == Some('/') && code(input, pointer + 1) == Some('/') {
          state = SpecialAuthorityIgnoreSlashes
          pointer += 1
        } else {
          state = SpecialAuthorityIgnoreSlashes
          pointer -= 1
        }
      SpecialAuthorityIgnoreSlashes =>
        if c != Some('/') && c != Some('\\') {
          state = Authority
          pointer -= 1
        }
      Authority =>
        if c == Some('@') {
          if at_sign {
            buffer = string_chars("%40") + buffer
          }
          at_sign = true
          for character in buffer {
            if character == ':' && !password_token {
              password_token = true
              continue
            }
            let piece = escape_with(one(character)[:], Userinfo)
            if password_token {
              url.password = url.password + piece
            } else {
              url.username = url.username + piece
            }
          }
          buffer = []
        } else if c is None ||
          c == Some('/') ||
          c == Some('?') ||
          c == Some('#') ||
          (special(url.scheme[:]) && c == Some('\\')) {
          if at_sign && buffer.length() == 0 {
            raise Host(at=pointer)
          }
          pointer -= buffer.length() + 1
          host_at = pointer + 1
          buffer = []
          state = Host
        } else if c is Some(character) {
          buffer.push(character)
        }
      Host | Hostname => {
        let is_name = state == Hostname
        if only is Some(_) && url.scheme == "file" {
          pointer -= 1
          state = FileHost
        } else if c == Some(':') && !in_brackets {
          if buffer.length() == 0 {
            raise Host(at=pointer)
          }
          if is_name {
            raise Host(at=pointer)
          }
          url.host = Some(
            host(text_of(buffer)[:], special=special(url.scheme[:]), at=host_at),
          )
          buffer = []
          state = Port
        } else if c is None ||
          c == Some('/') ||
          c == Some('?') ||
          c == Some('#') ||
          (special(url.scheme[:]) && c == Some('\\')) {
          pointer -= 1
          if special(url.scheme[:]) && buffer.length() == 0 {
            raise Host(at=pointer)
          }
          if only is Some(_) &&
            buffer.length() == 0 &&
            (credentials(url) || url.port is Some(_)) {
            raise Host(at=pointer)
          }
          url.host = Some(
            host(text_of(buffer)[:], special=special(url.scheme[:]), at=host_at),
          )
          buffer = []
          state = PathStart
          if only is Some(_) {
            return url
          }
        } else {
          match c {
            Some('[') => in_brackets = true
            Some(']') => in_brackets = false
            _ => ()
          }
          if c is Some(character) {
            buffer.push(character)
          }
        }
      }
      Port =>
        match c {
          Some(character) if number(character) => buffer.push(character)
          _ if c is None ||
            c == Some('/') ||
            c == Some('?') ||
            c == Some('#') ||
            (special(url.scheme[:]) && c == Some('\\')) ||
            only is Some(_) => {
            if buffer.length() > 0 {
              let mut value = 0
              for character in buffer {
                value = value * 10 + (character.to_int() - 0x30)
                guard value <= 0xFFFF else { raise Port(at=pointer) }
              }
              url.port = if Some(value) == port_of(url.scheme[:]) {
                None
              } else {
                Some(value)
              }
              buffer = []
              if only is Some(_) {
                return url
              }
            } else if only is Some(_) {
              raise Port(at=pointer)
            }
            state = PathStart
            pointer -= 1
          }
          _ => raise Port(at=pointer)
        }
      File => {
        url.scheme = "file"
        url.host = Some("")
        if c == Some('/') || c == Some('\\') {
          state = FileSlash
        } else {
          match base {
            Some(base) if base.scheme == "file" => {
              url.host = base.host
              url.path = base.path.copy()
              url.query = base.query
              if c == Some('?') {
                url.query = Some("")
                state = Query
              } else if c == Some('#') {
                url.fragment = Some("")
                state = Fragment
              } else if c is Some(_) {
                url.query = None
                if drive_at(input, pointer) is Some(_) {
                  url.path = []
                } else {
                  shorten(url)
                }
                state = Path
                pointer -= 1
              }
            }
            _ => {
              state = Path
              pointer -= 1
            }
          }
        }
      }
      FileSlash =>
        if c == Some('/') || c == Some('\\') {
          state = FileHost
        } else {
          match base {
            Some(base) if base.scheme == "file" => {
              url.host = base.host
              if drive_at(input, pointer) is None &&
                base.path.length() > 0 &&
                drive(base.path[0][:]) == Some(true) {
                url.path.push(base.path[0])
              }
            }
            _ => ()
          }
          state = Path
          pointer -= 1
        }
      FileHost =>
        if c is None ||
          c == Some('/') ||
          c == Some('\\') ||
          c == Some('?') ||
          c == Some('#') {
          pointer -= 1
          if only is None && drive(text_of(buffer)[:]) is Some(_) {
            // `C:` in the host position is a drive letter, not a host. The
            // buffer is not reset: the path state reads it next.
            state = Path
          } else if buffer.length() == 0 {
            url.host = Some("")
            if only is Some(_) {
              return url
            }
            state = PathStart
          } else {
            let name = host(text_of(buffer)[:], special=true, at=host_at)
            url.host = Some(if name == "localhost" { "" } else { name })
            if only is Some(_) {
              return url
            }
            buffer = []
            state = PathStart
          }
        } else if c is Some(character) {
          buffer.push(character)
        }
      PathStart =>
        if special(url.scheme[:]) {
          state = Path
          if c != Some('/') && c != Some('\\') {
            pointer -= 1
          }
        } else if only is None && c == Some('?') {
          url.query = Some("")
          state = Query
        } else if only is None && c == Some('#') {
          url.fragment = Some("")
          state = Fragment
        } else if c is Some(_) {
          state = Path
          if c != Some('/') {
            pointer -= 1
          }
        } else if only is Some(_) && url.host is None {
          url.path.push("")
        }
      Path =>
        if c is None ||
          c == Some('/') ||
          (special(url.scheme[:]) && c == Some('\\')) ||
          (only is None && (c == Some('?') || c == Some('#'))) {
          let piece = text_of(buffer)
          let slash = c == Some('/') ||
            (special(url.scheme[:]) && c == Some('\\'))
          if dots(piece[:]) == 2 {
            shorten(url)
            if !slash {
              url.path.push("")
            }
          } else if dots(piece[:]) == 1 {
            if !slash {
              url.path.push("")
            }
          } else {
            if url.scheme == "file" &&
              url.path.length() == 0 &&
              drive(piece[:]) is Some(_) {
              // A drive letter is written with a colon, whatever the input
              // said: `file://C|/` and `file://C:/` name the same place.
              buffer[1] = ':'
            }
            url.path.push(text_of(buffer))
          }
          buffer = []
          if c == Some('?') {
            url.query = Some("")
            state = Query
          } else if c == Some('#') {
            url.fragment = Some("")
            state = Fragment
          }
        } else if c is Some(character) {
          push_escaped(buffer, character, Path)
        }
      OpaquePath =>
        if c == Some('?') {
          url.query = Some("")
          state = Query
        } else if c == Some('#') {
          url.fragment = Some("")
          state = Fragment
        } else if c == Some(' ') {
          let next = code(input, pointer + 1)
          if next == Some('?') || next == Some('#') {
            url.path[0] = url.path[0] + "%20"
          } else {
            url.path[0] = url.path[0] + " "
          }
        } else if c is Some(character) {
          let out = StringBuilder()
          out.write_string(url.path[0])
          escape_point(out, character, C0Control)
          url.path[0] = out.to_string()
        }
      Query =>
        if (only is None && c == Some('#')) || c is None {
          let set = if special(url.scheme[:]) { SpecialQuery } else { Query }
          url.query = Some(
            url.query.unwrap_or("") + escape_with(text_of(buffer)[:], set),
          )
          buffer = []
          if c == Some('#') {
            url.fragment = Some("")
            state = Fragment
          }
        } else if c is Some(character) {
          buffer.push(character)
        }
      Fragment =>
        if c is Some(character) {
          push_escaped(buffer, character, Fragment)
        }
    }
    if pointer >= n {
      break
    }
    pointer += 1
  }
  if buffer.length() > 0 && state == Fragment {
    url.fragment = Some(
      url.fragment.unwrap_or("") + escape_with(text_of(buffer)[:], Fragment),
    )
  }
  url
}

///|
/// Percent-encode one code point onto the end of a buffer.
fn push_escaped(buffer : Array[Char], character : Char, set : Escaping) -> Unit {
  let out = StringBuilder()
  escape_point(out, character, set)
  for character in out.to_string() {
    buffer.push(character)
  }
}

// ------------------------------------------------------------- the result

///|
/// A URL, as the [`Url`] type holds it.
///
/// The standard keeps the username and the password apart and the path as
/// segments; this writes them back together, since a URL is text.
fn to_url(parts : Parts) -> Url {
  let userinfo = if parts.username == "" && parts.password == "" {
    None
  } else if parts.password == "" {
    Some(parts.username)
  } else {
    Some(parts.username + ":" + parts.password)
  }
  let path = if parts.opaque_path {
    if parts.path.length() > 0 {
      parts.path[0]
    } else {
      ""
    }
  } else {
    let out = StringBuilder()
    for segment in parts.path {
      out.write_char('/')
      out.write_string(segment)
    }
    out.to_string()
  }
  {
    scheme: Some(parts.scheme),
    userinfo,
    host: parts.host,
    port: parts.port,
    path,
    query: parts.query,
    fragment: parts.fragment,
  }
}

// ------------------------------------------------------------------ plumbing

///|
/// The input with what the standard takes off before reading it: C0 controls
/// and spaces at either end, and every tab and newline anywhere.
fn clean(text : StringView, trim~ : Bool) -> Array[Char] {
  let all : Array[Char] = []
  for character in text {
    all.push(character)
  }
  let mut begin = 0
  let mut end = all.length()
  if trim {
    while begin < end && all[begin].to_int() <= 0x20 {
      begin += 1
    }
    while end > begin && all[end - 1].to_int() <= 0x20 {
      end -= 1
    }
  }
  let out : Array[Char] = []
  for i = begin; i < end; i = i + 1 {
    let point = all[i].to_int()
    if point != 0x09 && point != 0x0A && point != 0x0D {
      out.push(all[i])
    }
  }
  out
}

///|
/// A buffer as text.
fn text_of(buffer : Array[Char]) -> String {
  let out = StringBuilder()
  for character in buffer {
    out.write_char(character)
  }
  out.to_string()
}

///|
/// A string as characters, for the authority state, which has to put `%40` in
/// front of what it has read.
fn string_chars(text : StringView) -> Array[Char] {
  let out : Array[Char] = []
  for character in text {
    out.push(character)
  }
  out
}

///|
/// Whether the URL has a username or a password, which is not the same as
/// having a userinfo somebody wrote: `@` alone makes one.
fn credentials(url : Parts) -> Bool {
  url.username != "" || url.password != ""
}

///|
/// Take the last segment of the path off (§4.4, "shorten").
fn shorten(url : Parts) -> Unit {
  if url.scheme == "file" &&
    url.path.length() == 1 &&
    drive(url.path[0][:]) is Some(_) {
    return
  }
  if url.path.length() > 0 {
    let _ = url.path.pop()
  }
}

///|
/// Whether `text` is a Windows drive letter: a letter and a colon, which is
/// what `file:` has to tell apart from a one-letter host.
///
/// `Some(true)` when it is written with a colon, `Some(false)` when it is
/// written with anything else in the colon's place — `C|` and `C:` name the
/// same drive, and only the second is the normal form.
fn drive(text : StringView) -> Bool? {
  if text.length() != 2 || !letter(text[0].to_int()) {
    return None
  }
  if text[1].to_int() == 0x3A {
    Some(true)
  } else if text[1].to_int() == 0x7C {
    Some(false)
  } else {
    None
  }
}

///|
/// Whether the input from `pointer` on starts with a Windows drive letter and
/// then the end, a slash or a query: `file:C:/x`, but not `file:CD/x`.
fn drive_at(input : Array[Char], pointer : Int32) -> Bool? {
  guard pointer + 1 < input.length() && letter(input[pointer].to_int()) else {
    return None
  }
  let kind = match input[pointer + 1] {
    ':' => Some(true)
    '|' => Some(false)
    _ => return None
  }
  if pointer + 2 == input.length() {
    return kind
  }
  match input[pointer + 2] {
    '/' | '\\' | '?' | '#' => kind
    _ => None
  }
}

///|
/// How many dots a path segment is: 2 for `..`, `.%2e`, `%2e.` and `%2e%2e`,
/// 1 for `.` and `%2e`, and 0 for anything else, the empty segment included.
fn dots(text : StringView) -> Int32 {
  let mut rest = text
  let mut count = 0
  while true {
    if starts(rest, "%2e") || starts(rest, "%2E") {
      rest = rest[3:]
    } else if rest.length() > 0 && rest[0].to_int() == 0x2E {
      rest = rest[1:]
    } else {
      break
    }
    count += 1
  }
  if rest.length() > 0 || count > 2 {
    0
  } else {
    count
  }
}

// ------------------------------------------------------------------ origin

///|
/// The origin of a URL (§4.7): what two URLs have to share to be the same
/// site, written `scheme://host:port`.
///
/// A `blob:` URL carries the origin of the URL inside it. Everything else that
/// is not a scheme with an authority of its own — `file:`, `data:`, `mailto:`
/// — has an origin no other URL shares, which is written `"null"`.
///
/// ```mbt check
/// test {
///   let url = @moonurl.Url::decode(
///     "https://example.test/a",
///     syntax=@moonurl.Whatwg,
///   )
///   assert_eq(url.origin(), "https://example.test")
///   let file = @moonurl.Url::decode("file:///tmp/x", syntax=@moonurl.Whatwg)
///   assert_eq(file.origin(), "null")
/// }
/// ```
pub fn Url::origin(self : Url) -> String {
  let scheme = self.scheme.unwrap_or("")
  if scheme == "blob" {
    let inner = Some(Url::decode(self.path[:], syntax=Whatwg)) catch {
      _ => None
    }
    guard inner is Some(inner) else { return "null" }
    let scheme = inner.scheme.unwrap_or("")
    return if scheme == "http" || scheme == "https" || scheme == "file" {
      inner.origin()
    } else {
      "null"
    }
  }
  match scheme {
    "ftp" | "http" | "https" | "ws" | "wss" => {
      let host = self.host.unwrap_or("")
      let out = StringBuilder()
      out.write_string(scheme)
      out.write_string("://")
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
      out.to_string()
    }
    _ => "null"
  }
}

// ------------------------------------------------------------------- setters

///|
/// Whether the URL may carry a username, a password or a port: a special
/// scheme other than `file` does, and a URL with no host does not.
fn with_credentials(parts : Parts) -> Bool {
  parts.host is Some(host) && host != "" && parts.scheme != "file"
}

///|
/// The parts of this URL, if it is one the standard can read.
fn read_parts(url : Url) -> Parts? {
  Some(parts_of(url)) catch {
    _ => None
  }
}

///|
/// This URL with its scheme replaced, or this URL if the value is not a scheme.
///
/// A URL may change between special and non-special schemes only through
/// another special one, and only a URL with no credentials, port or `file`
/// host can become `file`; the setter leaves anything else as it was, as the
/// standard's own setter does.
///
/// ```mbt check
/// test {
///   let url = @moonurl.Url::decode(
///     "http://example.test/a",
///     syntax=@moonurl.Whatwg,
///   )
///   assert_eq(url.set_scheme("https").encode(), "https://example.test/a")
///   assert_eq(url.set_scheme("1bad").encode(), "http://example.test/a")
/// }
/// ```
pub fn Url::set_scheme(self : Url, value : StringView) -> Url {
  set_by(self, value.to_owned() + ":", SchemeStart)
}

///|
/// This URL with its username replaced.
pub fn Url::set_username(self : Url, value : StringView) -> Url {
  let parts = match read_parts(self) {
    Some(parts) => parts
    None => return self
  }
  guard with_credentials(parts) else { return self }
  parts.username = escape_with(value, Userinfo)
  to_url(parts)
}

///|
/// This URL with its password replaced.
pub fn Url::set_password(self : Url, value : StringView) -> Url {
  let parts = match read_parts(self) {
    Some(parts) => parts
    None => return self
  }
  guard with_credentials(parts) else { return self }
  parts.password = escape_with(value, Userinfo)
  to_url(parts)
}

///|
/// This URL with its host replaced, and its port too if the value carries one.
///
/// An empty value is a host with nothing in it, not a missing host: the URL
/// keeps its shape and loses its authority's middle.
pub fn Url::set_host(self : Url, value : StringView) -> Url {
  let parts = match read_parts(self) {
    Some(parts) => parts
    None => return self
  }
  guard !parts.opaque_path else { return self }
  set_parts(parts, value, Host)
}

///|
/// This URL with its host replaced and its port left alone.
pub fn Url::set_hostname(self : Url, value : StringView) -> Url {
  let parts = match read_parts(self) {
    Some(parts) => parts
    None => return self
  }
  guard !parts.opaque_path else { return self }
  set_parts(parts, value, Hostname)
}

///|
/// This URL with its port replaced. An empty value takes the port away, which
/// is not the same as setting it to zero.
pub fn Url::set_port(self : Url, value : StringView) -> Url {
  let parts = match read_parts(self) {
    Some(parts) => parts
    None => return self
  }
  guard with_credentials(parts) else { return self }
  if value.length() == 0 {
    parts.port = None
    return to_url(parts)
  }
  set_parts(parts, value, Port)
}

///|
/// This URL with its path replaced. A URL whose path is opaque — `mailto:`,
/// `data:` — has no path to replace, and keeps the one it has.
pub fn Url::set_path(self : Url, value : StringView) -> Url {
  let parts = match read_parts(self) {
    Some(parts) => parts
    None => return self
  }
  guard !parts.opaque_path else { return self }
  parts.path = []
  set_parts(parts, value, PathStart)
}

///|
/// This URL with its query replaced, the leading `?` of the value optional.
/// An empty value takes the query away.
pub fn Url::set_query(self : Url, value : StringView) -> Url {
  let parts = match read_parts(self) {
    Some(parts) => parts
    None => return self
  }
  if value.length() == 0 {
    parts.query = None
    return to_url(parts)
  }
  let text = if value[0].to_int() == 0x3F { value[1:] } else { value }
  parts.query = Some("")
  set_parts(parts, text, Query)
}

///|
/// This URL with its fragment replaced, the leading `#` of the value optional.
/// An empty value takes the fragment away.
pub fn Url::set_fragment(self : Url, value : StringView) -> Url {
  let parts = match read_parts(self) {
    Some(parts) => parts
    None => return self
  }
  if value.length() == 0 {
    parts.fragment = None
    return to_url(parts)
  }
  let text = if value[0].to_int() == 0x23 { value[1:] } else { value }
  parts.fragment = Some("")
  set_parts(parts, text, Fragment)
}

///|
/// Read `value` into `parts` starting at `state`, and return what came of it —
/// or the URL untouched, since a setter that fails changes nothing.
fn set_parts(parts : Parts, value : StringView, state : State) -> Url {
  // The parser is given the parts themselves, so that a setter that fails
  // halfway — a host that reads and a port that does not — keeps what it read,
  // as the standard's own setters do.
  let parsed = Some(parse(value, None, Some(parts), Some(state))) catch {
    _ => None
  }
  match parsed {
    Some(parsed) => to_url(parsed)
    None => to_url(parts)
  }
}

///|
fn set_by(url : Url, value : String, state : State) -> Url {
  let parts = match read_parts(url) {
    Some(parts) => parts
    None => return url
  }
  set_parts(parts, value[:], state)
}

///|
/// The query as pairs, read the way `URLSearchParams` reads it (WHATWG URL
/// Standard §5.1).
///
/// ```mbt check
/// test {
///   let url = @moonurl.Url::decode(
///     "https://h/?a=1&a=2&b=x+y",
///     syntax=@moonurl.Whatwg,
///   )
///   assert_eq(url.params().values("a").length(), 2)
///   assert_eq(url.params().get("b").unwrap(), "x y")
/// }
/// ```
pub fn Url::params(self : Url) -> Query raise Refused {
  match self.query {
    Some(query) => Query::decode(@utf8.encode(query[:]))
    None => Query::new()
  }
}
