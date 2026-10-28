// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What a variable holds (RFC 6570 §2.3): one string, a list of them, or a set
/// of named ones.
pub(all) enum Value {
  /// A string.
  Text(String)
  /// A list, whose items are expanded in order.
  List(Array[String])
  /// An associative array: names with values, expanded in order.
  Pairs(Array[(String, String)])
} derive(Eq, Debug)

///|
pub extend Value with Eq::{equal, not_equal}

///|
pub extend Value with Debug::{to_repr}

///|
/// Where the values of a template come from. Implement it for whatever holds
/// them — a map, a configuration record, a request's query.
///
/// ```mbt check
/// test {
///   let values : Map[String, @template.Value] = Map([])
///   values.set("q", @template.Value::Text("moon bit"))
///   assert_eq(
///     @template.Template::decode("?q={q}").expand(values),
///     "?q=moon%20bit",
///   )
/// }
/// ```
pub(open) trait Variables {
  fn get(Self, StringView) -> Value?
}

///|
/// A map of names to values is the obvious place to look.
pub impl Variables for Map[String, Value] with fn get(self, name) {
  self.get_from_string(name)
}

///|
/// Why a string is not a template.
pub(all) suberror Refused {
  /// A `{` that is never closed, or a `}` that opens nothing, at this offset.
  Bracket(at~ : Int32)
  /// A character that may not stand in a template where this one does.
  Syntax(at~ : Int32, got~ : Char)
  /// A reserved operator: `=`, `,`, `!`, `@` or `|` (RFC 6570 §2.2).
  Operator(at~ : Int32, got~ : Char)
  /// A `:N` prefix that is not one to four digits from 1 to 9999.
  Length(at~ : Int32, limit~ : Int32, got~ : Int32)
} derive(Eq, Debug)

///|
pub extend Refused with Eq::{equal, not_equal}

///|
pub extend Refused with Debug::{to_repr}

///|
/// The eight operators of §2.2, and the empty one that is no operator at all.
priv enum Operator {
  Simple
  Reserved
  Fragment
  Label
  Path
  Parameter
  Query
  Continuation
} derive(Eq, Debug)

///|
/// One variable of an expression: its name, and the modifier the fourth level
/// adds to it.
priv struct Variable {
  name : String
  /// The length a `:N` prefix asks for, in characters.
  prefix : Int32?
  /// Whether a `*` asks for the value to be expanded in full.
  explode : Bool
} derive(Eq, Debug)

///|
/// A literal, or an expression to fill in.
priv enum Part {
  Literal(String)
  Expression(Operator, Array[Variable])
} derive(Eq, Debug)

///|
/// A template (RFC 6570 §2), kept as the pieces it was read into.
pub struct Template {
  priv parts : Array[Part]
} derive(Eq, Debug)

///|
pub extend Template with Eq::{equal, not_equal}

///|
pub extend Template with Debug::{to_repr}

// ------------------------------------------------------------------- reading

///|
/// Read a template (§2).
///
/// ```mbt check
/// test {
///   let template = @template.Template::decode("http://h{/list*}{?q,page}")
///   assert_eq(template.encode(), "http://h{/list*}{?q,page}")
/// }
/// ```
pub fn Template::decode(text : StringView) -> Template raise Refused {
  let input : Array[Char] = []
  for character in text {
    input.push(character)
  }
  let parts : Array[Part] = []
  let mut literal = StringBuilder()
  let mut i = 0
  let n = input.length()
  while i < n {
    let character = input[i]
    if character == '{' {
      if !literal.is_empty() {
        parts.push(Literal(literal.to_string()))
        literal = StringBuilder()
      }
      let (part, next) = expression(input, i)
      parts.push(part)
      i = next
    } else if character == '}' {
      raise Bracket(at=i)
    } else {
      guard literal_char(character) else { raise Syntax(at=i, got=character) }
      if character == '%' {
        guard i + 2 < n &&
          hex(input[i + 1].to_int()) &&
          hex(input[i + 2].to_int()) else {
          raise Syntax(at=i, got=character)
        }
        literal.write_char('%')
        literal.write_char(input[i + 1])
        literal.write_char(input[i + 2])
        i += 3
        continue
      }
      literal.write_char(character)
      i += 1
    }
  }
  if !literal.is_empty() {
    parts.push(Literal(literal.to_string()))
  }
  { parts, }
}

///|
/// Read one `{...}`, and say where it ends.
fn expression(input : Array[Char], open : Int32) -> (Part, Int32) raise Refused {
  let n = input.length()
  let mut i = open + 1
  guard i < n else { raise Bracket(at=open) }
  let operator = match input[i] {
    '+' => Some(Reserved)
    '#' => Some(Fragment)
    '.' => Some(Label)
    '/' => Some(Path)
    ';' => Some(Parameter)
    '?' => Some(Query)
    '&' => Some(Continuation)
    '=' | ',' | '!' | '@' | '|' => raise Operator(at=i, got=input[i])
    _ => None
  }
  match operator {
    Some(_) => i += 1
    None => ()
  }
  let op = operator.unwrap_or(Simple)
  let variables : Array[Variable] = []
  while true {
    let (variable, next) = varspec(input, i)
    variables.push(variable)
    i = next
    guard i < n else { raise Bracket(at=open) }
    if input[i] == ',' {
      i += 1
      continue
    }
    guard input[i] == '}' else { raise Syntax(at=i, got=input[i]) }
    i += 1
    break
  }
  (Expression(op, variables), i)
}

///|
/// Read one variable name and its modifier, up to the `,` or `}` after it.
fn varspec(
  input : Array[Char],
  start : Int32,
) -> (Variable, Int32) raise Refused {
  let n = input.length()
  let mut i = start
  let name = StringBuilder()
  while i < n {
    let character = input[i]
    if character == ':' ||
      character == '*' ||
      character == ',' ||
      character == '}' {
      break
    }
    if character == '.' || character == '_' || varchar(character) {
      name.write_char(character)
      i += 1
    } else if character == '%' {
      guard i + 2 < n &&
        hex(input[i + 1].to_int()) &&
        hex(input[i + 2].to_int()) else {
        raise Syntax(at=i, got=character)
      }
      name.write_char('%')
      name.write_char(input[i + 1])
      name.write_char(input[i + 2])
      i += 3
    } else {
      raise Syntax(at=i, got=character)
    }
  }
  guard !name.is_empty() else { raise Syntax(at=i, got=input[i]) }
  // The prefix modifier is for the operators that expand a scalar, and does
  // not go with `*`.
  let mut prefix = None
  if i < n && input[i] == ':' {
    i += 1
    let mut digits = 0
    let mut length = 0
    while i < n && input[i] >= '0' && input[i] <= '9' {
      length = length * 10 + (input[i].to_int() - 0x30)
      digits += 1
      i += 1
      guard digits <= 4 && length <= 9999 else {
        raise Length(at=i, limit=9999, got=length)
      }
    }
    guard digits > 0 && length > 0 else {
      raise Length(at=i, limit=9999, got=length)
    }
    prefix = Some(length)
  }
  let mut explode = false
  if i < n && input[i] == '*' {
    explode = true
    i += 1
    guard prefix is None else { raise Syntax(at=i, got='*') }
  }
  ({ name: name.to_string(), prefix, explode, }, i)
}

///|
/// Whether a character may stand in a literal (§2.1): everything except the
/// space, the delimiters a template needs, and the characters a URI never
/// carries.
fn literal_char(character : Char) -> Bool {
  let point = character.to_int()
  if point <= 0x20 {
    return false
  }
  if point < 0x7F {
    return match character {
      '"' | '\'' | '<' | '>' | '\\' | '^' | '`' | '{' | '|' | '}' => false
      _ => true
    }
  }
  true
}

///|
fn varchar(character : Char) -> Bool {
  let point = character.to_int()
  (point >= 0x41 && point <= 0x5A) ||
  (point >= 0x61 && point <= 0x7A) ||
  (point >= 0x30 && point <= 0x39)
}

///|
fn hex(point : Int32) -> Bool {
  (point >= 0x30 && point <= 0x39) ||
  (point >= 0x41 && point <= 0x46) ||
  (point >= 0x61 && point <= 0x66)
}

// ------------------------------------------------------------------- writing

///|
/// The template as it was written, the way §2 spells it.
pub fn Template::encode(self : Template) -> String {
  let out = StringBuilder()
  for part in self.parts {
    match part {
      Literal(text) => out.write_string(text)
      Expression(operator, variables) => {
        out.write_char('{')
        match operator_char(operator) {
          Some(character) => out.write_char(character)
          None => ()
        }
        for i, variable in variables {
          if i > 0 {
            out.write_char(',')
          }
          out.write_string(variable.name)
          match variable.prefix {
            Some(length) => {
              out.write_char(':')
              out.write_string(length.to_string())
            }
            None => ()
          }
          if variable.explode {
            out.write_char('*')
          }
        }
        out.write_char('}')
      }
    }
  }
  out.to_string()
}

///|
/// The character an expression is written with, if it is written with one.
fn operator_char(operator : Operator) -> Char? {
  match operator {
    Simple => None
    Reserved => Some('+')
    Fragment => Some('#')
    Label => Some('.')
    Path => Some('/')
    Parameter => Some(';')
    Query => Some('?')
    Continuation => Some('&')
  }
}

///|
/// The character an expansion opens the URI with, if it opens it with one.
/// `{+x}` and `{x}` both start with a value, so neither has one.
fn prefix_char(operator : Operator) -> Char? {
  match operator {
    Simple | Reserved => None
    Fragment => Some('#')
    Label => Some('.')
    Path => Some('/')
    Parameter => Some(';')
    Query => Some('?')
    Continuation => Some('&')
  }
}

// --------------------------------------------------------------- expansion

///|
/// Fill the template in (§3.2).
///
/// ```mbt check
/// test {
///   let values : Map[String, @template.Value] = Map([])
///   values.set("who", @template.Value::Text("moon"))
///   values.set("list", @template.Value::List(["a", "b"]))
///   let template = @template.Template::decode("{/who}{?list}")
///   assert_eq(template.expand(values), "/moon?list=a,b")
/// }
/// ```
pub fn[T : Variables] Template::expand(
  self : Template,
  variables : T,
) -> String {
  let out = StringBuilder()
  for part in self.parts {
    match part {
      Literal(text) => out.write_string(text)
      Expression(operator, specs) => {
        let pieces : Array[String] = []
        for spec in specs {
          let value = variables.get(spec.name[:])
          if value is Some(value) {
            for piece in expanded(operator, spec, value) {
              pieces.push(piece)
            }
          }
        }
        if pieces.length() > 0 {
          match prefix_char(operator) {
            Some(character) => out.write_char(character)
            None => ()
          }
          for i, piece in pieces {
            if i > 0 {
              out.write_char(separator(operator))
            }
            out.write_string(piece)
          }
        }
      }
    }
  }
  out.to_string()
}

///|
/// What one variable becomes: the pieces that go between the separators.
fn expanded(
  operator : Operator,
  spec : Variable,
  value : Value,
) -> Array[String] {
  let pieces : Array[String] = []
  let named = named(operator)
  let reserved = operator == Reserved || operator == Fragment
  match value {
    Text(text) => {
      let text = match spec.prefix {
        Some(length) => first_chars(text, length)
        None => text
      }
      let encoded = encode(text[:], reserved~)
      if named {
        if encoded.length() == 0 {
          pieces.push(spec.name + empty_suffix(operator))
        } else {
          pieces.push(spec.name + "=" + encoded)
        }
      } else {
        pieces.push(encoded)
      }
    }
    List(items) =>
      if spec.explode {
        for item in items {
          let encoded = encode(item[:], reserved~)
          if named {
            if encoded.length() == 0 {
              pieces.push(spec.name + empty_suffix(operator))
            } else {
              pieces.push(spec.name + "=" + encoded)
            }
          } else {
            pieces.push(encoded)
          }
        }
        if items.length() == 0 && named {
          pieces.push(spec.name + empty_suffix(operator))
        }
      } else {
        let joined = StringBuilder()
        for i, item in items {
          if i > 0 {
            joined.write_char(',')
          }
          joined.write_string(encode(item[:], reserved~))
        }
        let text = joined.to_string()
        if named {
          if text.length() == 0 {
            pieces.push(spec.name + empty_suffix(operator))
          } else {
            pieces.push(spec.name + "=" + text)
          }
        } else {
          pieces.push(text)
        }
      }
    Pairs(pairs) => {
      let joined = StringBuilder()
      if spec.explode {
        for pair in pairs {
          let (name, item) = pair
          if !joined.is_empty() {
            joined.write_char(separator(operator))
          }
          let encoded = encode(item[:], reserved~)
          joined.write_string(encode(name[:], reserved~))
          if encoded.length() == 0 {
            joined.write_string(empty_suffix(operator))
          } else {
            joined.write_char('=')
            joined.write_string(encoded)
          }
        }
      } else {
        for i, pair in pairs {
          let (name, item) = pair
          if i > 0 {
            joined.write_char(',')
          }
          joined.write_string(encode(name[:], reserved~))
          joined.write_char(',')
          joined.write_string(encode(item[:], reserved~))
        }
      }
      let text = joined.to_string()
      if named && !spec.explode {
        if text.length() == 0 {
          pieces.push(spec.name + empty_suffix(operator))
        } else {
          pieces.push(spec.name + "=" + text)
        }
      } else {
        pieces.push(text)
      }
    }
  }
  pieces
}

///|
fn separator(operator : Operator) -> Char {
  match operator {
    Simple | Reserved | Fragment => ','
    Label => '.'
    Path => '/'
    Parameter => ';'
    Query | Continuation => '&'
  }
}

///|
fn named(operator : Operator) -> Bool {
  operator == Parameter || operator == Query || operator == Continuation
}

///|
/// What follows a name whose value is empty (§3.2.1, the `ifemp` column).
fn empty_suffix(operator : Operator) -> String {
  match operator {
    Query | Continuation => "="
    _ => ""
  }
}

///|
/// The first `length` characters of `text`.
fn first_chars(text : String, length : Int32) -> String {
  let out = StringBuilder()
  let mut taken = 0
  for character in text {
    if taken == length {
      break
    }
    out.write_char(character)
    taken += 1
  }
  out.to_string()
}

///|
/// Percent-encode a value for expansion (§3.2.1): the unreserved characters
/// stand for themselves, and a run of `%XX` somebody already encoded is left
/// as it is. With `reserved`, the delimiters of a URI stand for themselves
/// too, which is what `+` and `#` are for.
fn encode(text : StringView, reserved~ : Bool) -> String {
  let input : Array[Char] = []
  for character in text {
    input.push(character)
  }
  let out = StringBuilder()
  let n = input.length()
  let mut i = 0
  while i < n {
    let character = input[i]
    let point = character.to_int()
    // An escape somebody else wrote is already an escape; only its absence
    // would need one.
    if point == 0x25 &&
      i + 2 < n &&
      hex(input[i + 1].to_int()) &&
      hex(input[i + 2].to_int()) {
      out.write_char(character)
      out.write_char(input[i + 1])
      out.write_char(input[i + 2])
      i += 3
      continue
    }
    if unreserved(point) || (reserved && delimiter(point)) {
      out.write_char(character)
    } else {
      for byte in @utf8.encode(one(character)[:]) {
        let value = byte.to_int()
        out.write_char('%')
        out.write_char(hex_char(value >> 4))
        out.write_char(hex_char(value & 0xF))
      }
    }
    i += 1
  }
  out.to_string()
}

///|
fn unreserved(point : Int32) -> Bool {
  (point >= 0x41 && point <= 0x5A) ||
  (point >= 0x61 && point <= 0x7A) ||
  (point >= 0x30 && point <= 0x39) ||
  point == 0x2D ||
  point == 0x2E ||
  point == 0x5F ||
  point == 0x7E
}

///|
/// The reserved characters of RFC 3986 §2.2, the gen-delims and sub-delims.
fn delimiter(point : Int32) -> Bool {
  match point {
    0x3A | 0x2F | 0x3F | 0x23 | 0x5B | 0x5D | 0x40 => true
    0x21 | 0x24 | 0x26 | 0x27 | 0x28 | 0x29 | 0x2A => true
    0x2B | 0x2C | 0x3B | 0x3D => true
    _ => false
  }
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
fn one(character : Char) -> String {
  let out = StringBuilder()
  out.write_char(character)
  out.to_string()
}

// ----------------------------------------------------------------- matching

///|
/// The variables a URI spells out, in the order the template names them, or
/// nothing if the URI is not one this template could have produced.
///
/// A template is a pattern, not a grammar: a value that holds the separator is
/// read as two values. Escapes are undone, so a name comes back as it was.
///
/// ```mbt check
/// test {
///   let template = @template.Template::decode("/users/{id}{?page}")
///   assert_eq(template.capture("/users/42?page=2").unwrap(), [
///     ("id", "42"),
///     ("page", "2"),
///   ])
/// }
/// ```
pub fn Template::capture(
  self : Template,
  uri : StringView,
) -> Array[(String, String)]? {
  let bindings : Array[(String, String)] = []
  let mut at = 0
  for i, part in self.parts {
    match part {
      Literal(text) => {
        guard starts_at(uri, at, text[:]) else { return None }
        at += text.length()
      }
      Expression(operator, specs) => {
        let end = match boundary(self.parts, i + 1, uri, at) {
          Some(end) => end
          None => return None
        }
        let slice = uri[at:end]
        at = end
        if !captured(operator, specs, slice, bindings) {
          return None
        }
      }
    }
  }
  guard at == uri.length() else { return None }
  Some(bindings)
}

///|
/// Split one expansion's text between the variables that made it.
fn captured(
  operator : Operator,
  specs : Array[Variable],
  text : StringView,
  bindings : Array[(String, String)],
) -> Bool {
  // The prefix character belongs to the expansion, not to a value.
  let text = match prefix_char(operator) {
    Some(character) =>
      if text.length() > 0 && text[0].to_int() == character.to_int() {
        text[1:]
      } else {
        text
      }
    None => text
  }
  if text.length() == 0 {
    return match prefix_char(operator) {
      Some(_) => true
      None => true
    }
  }
  let pieces = split(text, separator(operator))
  let mut i = 0
  for piece in pieces {
    if i >= specs.length() {
      // Every name has its value; what is left is the tail of the last one,
      // which only an exploded variable can have produced.
      guard specs[specs.length() - 1].explode else { return false }
      break
    }
    let spec = specs[i]
    i += 1
    let value = if named(operator) {
      match split_at(piece, '=') {
        Some((name, value)) =>
          // `?a` and `?a=` both mean an empty value.
          if name[:] == spec.name[:] {
            value
          } else {
            return false
          }
        None => piece
      }
    } else {
      piece
    }
    bindings.push((spec.name, unescaped(value.to_owned()[:])))
  }
  true
}

///|
/// Where the expansion that starts at `from` ends: at the literal that follows
/// it, or at the character an expression after it opens with, since neither
/// can be part of a value.
fn boundary(
  parts : Array[Part],
  at : Int32,
  uri : StringView,
  from : Int32,
) -> Int32? {
  guard at < parts.length() else { return Some(uri.length()) }
  match parts[at] {
    Literal(text) => find(uri, from, text[:])
    Expression(operator, _) =>
      match prefix_char(operator) {
        Some(character) =>
          match find_char(uri, from, character) {
            Some(found) => Some(found)
            None => Some(uri.length())
          }
        None => Some(uri.length())
      }
  }
}

///|
/// The first `character` in `text` at or after `at`.
fn find_char(text : StringView, at : Int32, character : Char) -> Int32? {
  let mut i = at
  while i < text.length() {
    if text[i].to_int() == character.to_int() {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
fn starts_at(text : StringView, at : Int32, prefix : StringView) -> Bool {
  if at + prefix.length() > text.length() {
    return false
  }
  for i = 0; i < prefix.length(); i = i + 1 {
    if text[at + i].to_int() != prefix[i].to_int() {
      return false
    }
  }
  true
}

///|
/// The first place `text` appears in `haystack` at or after `at`.
fn find(haystack : StringView, at : Int32, text : StringView) -> Int32? {
  let mut i = at
  while i + text.length() <= haystack.length() {
    if starts_at(haystack, i, text) {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
fn split(text : StringView, at : Char) -> Array[StringView] {
  let pieces : Array[StringView] = []
  let mut start = 0
  for i = 0; i <= text.length(); i = i + 1 {
    if i == text.length() || text[i].to_int() == at.to_int() {
      pieces.push(text[start:i])
      start = i + 1
    }
  }
  pieces
}

///|
fn split_at(text : StringView, at : Char) -> (StringView, StringView)? {
  for i = 0; i < text.length(); i = i + 1 {
    if text[i].to_int() == at.to_int() {
      return Some((text[:i], text[i + 1:]))
    }
  }
  None
}

///|
/// Undo percent-encoding, leaving a `%` that starts nothing alone.
fn unescaped(text : StringView) -> String {
  let input : Array[Char] = []
  for character in text {
    input.push(character)
  }
  let bytes : Array[Int32] = []
  let n = input.length()
  let mut i = 0
  while i < n {
    if input[i].to_int() == 0x25 &&
      i + 2 < n &&
      hex(input[i + 1].to_int()) &&
      hex(input[i + 2].to_int()) {
      bytes.push(
        (hex_value(input[i + 1].to_int()) << 4) |
        hex_value(input[i + 2].to_int()),
      )
      i += 3
    } else {
      bytes.push(input[i].to_int())
      i += 1
    }
  }
  let raw : Array[Byte] = []
  for byte in bytes {
    raw.push(byte.to_byte())
  }
  @utf8.decode_lossy(Bytes::from_array(raw)[:])
}

///|
fn hex_value(point : Int32) -> Int32 {
  if point >= 0x30 && point <= 0x39 {
    point - 0x30
  } else if point >= 0x41 && point <= 0x46 {
    point - 0x37
  } else {
    point - 0x57
  }
}
