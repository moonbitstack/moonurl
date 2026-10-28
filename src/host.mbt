// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Host parsing, as the URL Standard spells it (§3.5): a domain name run
// through IDNA, an IPv4 address in any of the shapes a number may take, an
// IPv6 address in brackets, or — for a scheme that is not special — an opaque
// string.

///|
/// Parse a host (§3.5), returning it the way [`Url::encode`] writes it: an
/// IPv6 address without its brackets, everything else as it stands.
///
/// `special` says whether the scheme is one of the six the standard gives its
/// own rules: a host under any other scheme is any string without a forbidden
/// code point, not a registered name.
fn host(
  text : StringView,
  special~ : Bool,
  at~ : Int32,
) -> String raise Refused {
  let n = text.length()
  if n > 0 && text[0].to_int() == 0x5B {
    guard n > 1 && text[n - 1].to_int() == 0x5D else { raise Host(at~) }
    return ipv6(text[1:n - 1], at~)
  }
  if !special {
    return opaque_host(text, at~)
  }
  // A host may be written in escapes; the name is what they stand for.
  let name = domain_parser(unescape_text(text)[:], strict=false, at~)
  if ends_in_number(name[:]) {
    return ipv4(name[:], at~)
  }
  name
}

///|
/// The domain parser of §3.3: the host name a browser would make of `text`.
///
/// Strict is for a name that has to be one: `CheckHyphens`, the STD 3 rules
/// and the DNS lengths are all on, and invalid Punycode is refused.
///
/// Lenient is the browser: an ASCII string is taken as it stands, lowercased,
/// whatever IDNA would say about the label — a name that reads as Punycode but
/// is not still addresses something. Everything else goes through UTS 46.
///
/// ```mbt check
/// test {
///   assert_eq(@moonurl.domain("MÜNCHEN.example"), "xn--mnchen-3ya.example")
///   assert_eq(@moonurl.domain("xn--a"), "xn--a")
/// }
/// ```
pub fn domain(
  text : StringView,
  strict~ : Bool = false,
) -> String raise Refused {
  domain_parser(text, strict~, at=0)
}

///|
fn domain_parser(
  text : StringView,
  strict~ : Bool,
  at~ : Int32,
) -> String raise Refused {
  if strict {
    let outcome = @idna.to_ascii(text, options=@idna.strict)
    guard outcome.is_ok() else { raise Name(at~) }
    return outcome.name
  }
  let name = if ascii(text) {
    downcase(text)
  } else {
    // A browser keeps a label it cannot read; the standard's own profile
    // refuses one it cannot decode, which is what this is.
    let options = { ..@idna.options, ignore_invalid_punycode: false, }
    let outcome = @idna.to_ascii(text, options~)
    guard outcome.is_ok() else { raise Name(at~) }
    outcome.name
  }
  guard name.length() > 0 else { raise Name(at~) }
  for character in name {
    guard !forbidden_domain(character) else { raise Name(at~) }
  }
  name
}

///|
/// `text` with its ASCII letters lowered, which is all a domain name needs:
/// everything else is IDNA's business.
fn downcase(text : StringView) -> String {
  let out = StringBuilder()
  for character in text {
    let point = character.to_int()
    if point >= 0x41 && point <= 0x5A {
      out.write_char((point + 32).unsafe_to_char())
    } else {
      out.write_char(character)
    }
  }
  out.to_string()
}

///|
/// Whether `text` is ASCII, which decides whether a name takes the browser's
/// short way through the domain parser.
fn ascii(text : StringView) -> Bool {
  for character in text {
    if character.to_int() >= 0x80 {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------- IPv4

///|
/// Parse an IPv4 address (§3.5): one to four parts, each in decimal, octal or
/// hexadecimal, the last one filling whatever the others left over.
///
/// The arithmetic is 64-bit wide: an address is a number that does not fit in
/// 32 bits once it is signed, and `0xFFFFFFFF` is a perfectly good host.
fn ipv4(text : StringView, at~ : Int32) -> String raise Refused {
  let parts = split_dots(text)
  if parts.length() > 0 && parts[parts.length() - 1].length() == 0 {
    if parts.length() > 1 {
      let _ = parts.pop()
    }
  }
  guard parts.length() <= 4 else { raise Address(at~) }
  let numbers : Array[Int64] = []
  for part in parts {
    let (number, _) = ipv4_number(part)
    numbers.push(number)
  }
  let last = numbers.length() - 1
  let octet : Int64 = 255
  for i, number in numbers {
    guard i == last || number <= octet else { raise Address(at~) }
  }
  // The last part fills what the others leave: 127.1 is 127.0.0.1.
  let mut address = numbers[last]
  let one : Int64 = 1
  guard address < one << (8 * (5 - numbers.length())) else {
    raise Address(at~)
  }
  let mut shift = 3
  for i = 0; i < last; i = i + 1 {
    address += numbers[i] << (8 * shift)
    shift -= 1
  }
  let out = StringBuilder()
  let byte : Int64 = 0xFF
  for i = 3; i >= 0; i = i - 1 {
    if i < 3 {
      out.write_char('.')
    }
    out.write_string(((address >> (8 * i)) & byte).to_string())
  }
  out.to_string()
}

///|
/// One part of an IPv4 address as a number, in the radix its prefix names:
/// `0x` hexadecimal, a leading `0` octal, decimal otherwise.
fn ipv4_number(text : StringView) -> (Int64, Bool) raise Refused {
  guard text.length() > 0 else { raise Address(at=0) }
  let mut body = text
  let mut radix : Int64 = 10
  let mut octal = false
  if text.length() >= 2 &&
    text[0].to_int() == 0x30 &&
    (text[1].to_int() == 0x78 || text[1].to_int() == 0x58) {
    body = text[2:]
    radix = 16
    octal = true
  } else if text.length() >= 2 && text[0].to_int() == 0x30 {
    body = text[1:]
    radix = 8
    octal = true
  }
  if body.length() == 0 {
    return (0, true)
  }
  // A part may be a number no address can hold. That is not a parse failure:
  // it is the range check below that refuses it.
  let ceiling : Int64 = 0x20000000000
  let mut value : Int64 = 0
  for character in body {
    let written = match character {
      '0'..<='9' => character.to_int() - 0x30
      'a'..<='f' => character.to_int() - 0x57
      'A'..<='F' => character.to_int() - 0x37
      _ => -1
    }
    guard written >= 0 else { raise Address(at=0) }
    let digit = written.to_int64()
    guard digit < radix else { raise Address(at=0) }
    // Past the ceiling the value only has to stay too big to be an address;
    // stopping it there keeps it from overflowing on a long run of digits.
    value = if value > ceiling / radix {
      ceiling
    } else {
      value * radix + digit
    }
  }
  (value, octal)
}

// ---------------------------------------------------------------------- IPv6

///|
/// Parse an IPv6 address (§3.5), the brackets already taken off, and write it
/// back in the compressed form of RFC 5952.
fn ipv6(text : StringView, at~ : Int32) -> String raise Refused {
  let input : Array[Char] = []
  for character in text {
    input.push(character)
  }
  let n = input.length()
  let pieces : Array[Int32] = Array::make(8, 0)
  let mut pointer = 0
  let mut piece = 0
  let mut compress = -1
  if code(input, 0) == Some(':') {
    guard code(input, 1) == Some(':') else { raise Address(at~) }
    pointer = 2
    piece = 1
    compress = 1
  }
  while pointer < n {
    guard piece < 8 else { raise Address(at~) }
    if code(input, pointer) == Some(':') {
      guard compress < 0 else { raise Address(at~) }
      pointer += 1
      piece += 1
      compress = piece
      continue
    }
    let mut value = 0
    let mut length = 0
    while length < 4 {
      match code(input, pointer) {
        Some(character) if hex(character) => {
          value = value * 0x10 + hex_value(character)
          pointer += 1
          length += 1
        }
        _ => break
      }
    }
    if code(input, pointer) == Some('.') {
      // The tail is an IPv4 address, written two bytes at a time.
      guard length > 0 && piece <= 6 else { raise Address(at~) }
      pointer -= length
      let mut seen = 0
      while pointer < n {
        if seen > 0 {
          guard code(input, pointer) == Some('.') && seen < 4 else {
            raise Address(at~)
          }
          pointer += 1
        }
        let mut octet = -1
        let mut digits = 0
        while pointer < n {
          match code(input, pointer) {
            Some(character) if character >= '0' && character <= '9' => {
              let number = character.to_int() - 0x30
              guard !(digits == 1 && octet == 0) else { raise Address(at~) }
              octet = if octet < 0 { number } else { octet * 10 + number }
              guard octet <= 255 else { raise Address(at~) }
              pointer += 1
              digits += 1
            }
            _ => break
          }
        }
        guard digits > 0 else { raise Address(at~) }
        pieces[piece] = pieces[piece] * 0x100 + octet
        seen += 1
        if seen == 2 || seen == 4 {
          piece += 1
        }
      }
      guard seen == 4 else { raise Address(at~) }
      break
    } else if code(input, pointer) == Some(':') {
      pointer += 1
      guard pointer < n else { raise Address(at~) }
    } else if pointer < n {
      raise Address(at~)
    }
    pieces[piece] = value
    piece += 1
  }
  if compress >= 0 {
    // Move the pieces after the gap to the end of the address.
    let mut swaps = piece - compress
    let mut target = 7
    while target > 0 && swaps > 0 {
      let temporary = pieces[target]
      pieces[target] = pieces[compress + swaps - 1]
      pieces[compress + swaps - 1] = temporary
      target -= 1
      swaps -= 1
    }
  } else {
    guard piece == 8 else { raise Address(at~) }
  }
  ipv6_text(pieces)
}

///|
/// An IPv6 address written the way RFC 5952 asks: the longest run of zero
/// pieces, of two or more, written `::`.
fn ipv6_text(pieces : Array[Int32]) -> String {
  let mut best = -1
  let mut best_length = 1
  let mut run = -1
  let mut length = 0
  for i, piece in pieces {
    if piece == 0 {
      if run < 0 {
        run = i
        length = 0
      }
      length += 1
      if length > best_length {
        best = run
        best_length = length
      }
    } else {
      run = -1
      length = 0
    }
  }
  let out = StringBuilder()
  let mut i = 0
  while i < 8 {
    if i == best {
      out.write_string("::")
      i += best_length
      continue
    }
    if i > 0 && i != best + best_length {
      out.write_char(':')
    }
    out.write_string(pieces[i].to_string(radix=16))
    i += 1
  }
  out.to_string()
}

///|
fn hex(character : Char) -> Bool {
  hex_value(character) >= 0
}

///|
fn hex_value(character : Char) -> Int32 {
  match character {
    '0'..<='9' => character.to_int() - 0x30
    'a'..<='f' => character.to_int() - 0x57
    'A'..<='F' => character.to_int() - 0x37
    _ => -1
  }
}

// -------------------------------------------------------------- opaque hosts

///|
/// An opaque host (§3.5): any string without a forbidden host code point,
/// percent-encoded for what no URI may carry.
fn opaque_host(text : StringView, at~ : Int32) -> String raise Refused {
  for character in text {
    guard !forbidden_host(character) else { raise Name(at~) }
  }
  let out = StringBuilder()
  escape_each(out, text, C0Control)
  out.to_string()
}

// ------------------------------------------------------------------ predicates

///|
/// The code points no host may contain (§3.2).
fn forbidden_host(character : Char) -> Bool {
  match character {
    '\u{0}'
    | '\t'
    | '\n'
    | '\r'
    | ' '
    | '#'
    | '/'
    | ':'
    | '<'
    | '>'
    | '?'
    | '@'
    | '['
    | '\\'
    | ']'
    | '^'
    | '|' => true
    _ => false
  }
}

///|
/// What a *domain* may not contain: the above, and the C0 controls, `%` and
/// DEL, which a registered name has no business carrying either.
fn forbidden_domain(character : Char) -> Bool {
  forbidden_host(character) ||
  character.to_int() < 0x20 ||
  character == '%' ||
  character == '\u{7F}'
}

// ------------------------------------------------------------------ numbers

///|
/// Whether a domain name ends in something that reads as an IPv4 address
/// number, which is what sends it to the IPv4 parser (§3.5).
fn ends_in_number(text : StringView) -> Bool {
  let parts = split_dots(text)
  if parts.length() > 0 && parts[parts.length() - 1].length() == 0 {
    let _ = parts.pop()
  }
  guard parts.length() > 0 else { return false }
  let last = parts[parts.length() - 1]
  guard last.length() > 0 else { return false }
  if digits_only(last) {
    return true
  }
  // `0x`, or `0x` and hexadecimal digits, is a number with nothing in it yet.
  try {
    ipv4_number(last) |> ignore
    true
  } catch {
    _ => false
  }
}

///|
fn digits_only(text : StringView) -> Bool {
  guard text.length() > 0 else { return false }
  for character in text {
    guard character >= '0' && character <= '9' else { return false }
  }
  true
}

///|
fn split_dots(text : StringView) -> Array[StringView] {
  let parts : Array[StringView] = []
  let mut start = 0
  for i = 0; i <= text.length(); i = i + 1 {
    if i == text.length() || text[i].to_int() == 0x2E {
      parts.push(text[start:i])
      start = i + 1
    }
  }
  parts
}
