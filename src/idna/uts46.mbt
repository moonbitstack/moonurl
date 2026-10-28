// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What UTS 46 leaves to the caller. Its two presets cover the two callers
/// there are: a browser reading a host name out of a link, and a zone file.
pub(all) struct Options {
  /// Treat ß, ς and the two joiners the way IDNA2003 did. Deprecated by the
  /// standard, and kept because some names still exist in that spelling.
  transitional : Bool
  /// Refuse a label with a hyphen where one may not be: leading, trailing, or
  /// in the third and fourth positions of a label that is not an A-label.
  check_hyphens : Bool
  /// Refuse a name whose right-to-left labels break the bidi rule of RFC 5893.
  check_bidi : Bool
  /// Refuse a zero width joiner or non-joiner outside the context that allows
  /// one (RFC 5892 Appendix A).
  check_joiners : Bool
  /// Refuse ASCII outside `a` to `z`, `0` to `9` and `-`, the STD 3 rules.
  std3 : Bool
  /// Refuse a name past the DNS limits: 253 octets, 63 to a label.
  dns_length : Bool
  /// Pass an `xn--` label that is not Punycode through untouched instead of
  /// refusing it. The URL standard asks for this: a browser keeps a label it
  /// cannot read rather than dropping the host.
  ignore_invalid_punycode : Bool
} derive(Eq, Debug)

///|
pub extend Options with Eq::{equal, not_equal}

///|
pub extend Options with Debug::{to_repr}

///|
/// What a host name gets: no STD 3, no hyphen rule (an A-label always has a
/// hyphen in the fourth position), the bidi and joiner rules on, and no DNS
/// length check, which the resolver is better placed to make.
pub let options : Options = {
  transitional: false,
  check_hyphens: false,
  check_bidi: true,
  check_joiners: true,
  std3: false,
  dns_length: false,
  ignore_invalid_punycode: true,
}

///|
/// What a zone file gets: everything `options` turns off, turned on.
pub let strict : Options = {
  ..options,
  check_hyphens: true,
  std3: true,
  dns_length: true,
  ignore_invalid_punycode: false,
}

///|
/// Why a name is not the name the standard would accept.
pub(all) enum Fault {
  /// A label that is not in NFC, begins with a combining mark, or begins with
  /// `xn--` where that prefix is not allowed (V1, V4, V6).
  Shape(at~ : Int32)
  /// A hyphen where `check_hyphens` forbids one (V2, V3).
  Hyphen(at~ : Int32)
  /// A full stop inside a label (V5).
  Dot(at~ : Int32)
  /// A code point the mapping table does not allow here (V7).
  Disallowed(at~ : Int32, got~ : Char)
  /// ASCII outside `a` to `z`, `0` to `9` and `-`, while `std3` is on (U1).
  Std3(at~ : Int32, got~ : Char)
  /// An `xn--` label that does not decode, decodes to nothing, or decodes to
  /// ASCII alone (P4).
  Punycode(at~ : Int32)
  /// A joiner out of context (C1, C2).
  Joiner(at~ : Int32)
  /// A label the bidi rule refuses (B1 to B6).
  Bidi(at~ : Int32)
  /// An empty label (A4_2, X4_2).
  Empty(at~ : Int32)
  /// A name or label past its length limit (A4_1, A4_2).
  Length(limit~ : Int32, got~ : Int32)
} derive(Eq, Debug)

///|
pub extend Fault with Eq::{equal, not_equal}

///|
pub extend Fault with Debug::{to_repr}

///|
/// A name as far as the standard could convert it, and what it objected to on
/// the way. Conversion does not stop at the first error, so a caller that
/// wants to show the user what is wrong has the rest of the name too.
pub(all) struct Outcome {
  /// The converted name.
  name : String
  /// Everything wrong with it, in no particular order.
  errors : Array[Fault]
} derive(Eq, Debug)

///|
pub extend Outcome with Eq::{equal, not_equal}

///|
pub extend Outcome with Debug::{to_repr}

///|
/// Whether the name is one the standard accepts.
pub fn Outcome::is_ok(self : Outcome) -> Bool {
  self.errors.is_empty()
}

///|
/// A name as ASCII, the form that goes on the wire (UTS 46 §4.2).
pub fn to_ascii(name : StringView, options~ : Options = options) -> Outcome {
  let errors : Array[Fault] = []
  let labels = prepare(name, options, errors)
  let bidi = bidi_domain(labels)
  for label in labels {
    if label.chars.length() > 0 && !label.unreadable {
      for error in check(label, bidi, options) {
        errors.push(error)
      }
    }
  }
  let out = StringBuilder()
  for i, label in labels {
    if i > 0 {
      out.write_char('.')
    }
    let text = text_of(label.chars)
    if ascii_only(text[:]) {
      out.write_string(text)
    } else {
      out.write_string("xn--")
      out.write_string(encode(text[:]))
    }
  }
  let text = out.to_string()
  if options.dns_length {
    audit(text[:], labels, errors)
  }
  { name: text, errors, }
}

///|
/// A name as Unicode, the form that is read (UTS 46 §4).
pub fn to_unicode(name : StringView, options~ : Options = options) -> Outcome {
  let errors : Array[Fault] = []
  let labels = prepare(name, options, errors)
  let bidi = bidi_domain(labels)
  for i, label in labels {
    if label.chars.length() == 0 {
      // A name may end in the dot of the root label; an empty label anywhere
      // else is a name with a hole in it. A name that is nothing but the root
      // label has no name in it at all.
      if i + 1 < labels.length() || labels.length() == 1 {
        errors.push(Empty(at=label.at))
      }
    } else if !label.unreadable {
      for error in check(label, bidi, options) {
        errors.push(error)
      }
    }
  }
  let out = StringBuilder()
  for i, label in labels {
    if i > 0 {
      out.write_char('.')
    }
    out.write_string(text_of(label.chars))
  }
  { name: out.to_string(), errors, }
}

// ------------------------------------------------------------------- mapping

///|
/// A label on its way through the algorithm, with where it started so that an
/// error can point at the name the caller passed rather than at a copy.
priv struct Label {
  mut chars : Array[Char]
  at : Int32
  /// Whether the label arrived as an A-label, which is validated the way
  /// nontransitional processing validates, whatever the caller asked for.
  mut converted : Bool
  /// Whether the label is an A-label that could not be read, and so stands as
  /// it came: UTS 46 §4 step 4 says to pass it over.
  mut unreadable : Bool
}

///|
/// Map, normalise, break into labels, and decode the A-labels among them
/// (UTS 46 §4 steps 1 to 4).
fn prepare(
  name : StringView,
  options : Options,
  errors : Array[Fault],
) -> Array[Label] {
  let mapped : Array[Char] = []
  for character in name {
    let (status, target) = entry(character.to_int())
    if status == MAPPED && options.transitional && character == '\u{1E9E}' {
      // Capital sharp s maps to its lower case form first, so the deviation
      // rules of step 1 have to see it themselves (UTS 46 §4 step 1).
      mapped.push('s')
      mapped.push('s')
    } else if status == IGNORED {
      continue
    } else if status == MAPPED || (status == DEVIATION && options.transitional) {
      for c in target {
        mapped.push(c)
      }
    } else {
      mapped.push(character)
    }
  }
  let chars : Array[Char] = []
  for c in @normalize.normalize(@normalize.Form::NFC, text_of(mapped)[:]) {
    chars.push(c)
  }
  let labels : Array[Label] = []
  let mut start = 0
  for i = 0; i <= chars.length(); i = i + 1 {
    if i == chars.length() || chars[i] == '.' {
      labels.push({
        chars: chars[start:i].to_owned(),
        at: start,
        converted: false,
        unreadable: false,
      })
      start = i + 1
    }
  }
  for label in labels {
    let chars = label.chars
    guard chars.length() >= 4 && prefix(chars) else { continue }
    if !ascii_only(text_of(chars)[:]) {
      // An A-label is ASCII by definition; anything else is a name that meant
      // to be one and is not.
      errors.push(Punycode(at=label.at))
      label.unreadable = true
      continue
    }
    let decoded = Some(decode(text_of(chars[4:].to_owned())[:])) catch {
      _ => None
    }
    match decoded {
      None => {
        if !options.ignore_invalid_punycode {
          errors.push(Punycode(at=label.at))
        }
        label.unreadable = true
      }
      Some(text) => {
        if text.length() == 0 || ascii_only(text[:]) {
          errors.push(Punycode(at=label.at))
        }
        // `xn--` alone is an empty label written the long way. Anything else
        // that decodes to nothing is a name nobody can read, and stands.
        if text.length() > 0 || chars.length() == 4 {
          let chars : Array[Char] = []
          for c in text {
            chars.push(c)
          }
          label.chars = chars
          label.converted = true
        } else {
          label.unreadable = true
        }
      }
    }
  }
  labels
}

///|
/// Whether `chars` begins with `xn--`.
fn prefix(chars : Array[Char]) -> Bool {
  chars.length() >= 4 &&
  chars[0] == 'x' &&
  chars[1] == 'n' &&
  chars[2] == '-' &&
  chars[3] == '-'
}

// ---------------------------------------------------------------- validation

///|
/// Every criterion of UTS 46 §4.1 this label fails.
fn check(label : Label, bidi : Bool, options : Options) -> Array[Fault] {
  let chars = label.chars
  let at = label.at
  let n = chars.length()
  let errors : Array[Fault] = []
  let transitional = options.transitional && !label.converted
  // V1.
  if !@normalize.is_normalized(@normalize.Form::NFC, text_of(chars)[:]) {
    errors.push(Shape(at~))
  }
  // V2, V3, V4.
  if options.check_hyphens {
    if n >= 4 && chars[2] == '-' && chars[3] == '-' {
      errors.push(Hyphen(at=at + 2))
    }
    if chars[0] == '-' || chars[n - 1] == '-' {
      errors.push(Hyphen(at~))
    }
  } else if prefix(chars) {
    errors.push(Shape(at~))
  }
  // V6.
  if mark(chars[0]) {
    errors.push(Shape(at~))
  }
  for i, character in chars {
    // V5.
    if character == '.' {
      errors.push(Dot(at=at + i))
    }
    // V7, and the STD 3 rule that stands in for it.
    let (status, _) = entry(character.to_int())
    let allowed = status == VALID || (status == DEVIATION && !transitional)
    if !allowed {
      errors.push(Disallowed(at=at + i, got=character))
    } else if options.std3 && character.to_int() < 0x80 && !std3(character) {
      errors.push(Std3(at=at + i, got=character))
    }
  }
  // V8.
  if options.check_joiners {
    joiners(chars, at, errors)
  }
  // V9.
  if options.check_bidi && bidi {
    rule(chars, at, errors)
  }
  errors
}

///|
/// Whether `character` is one STD 3 leaves alone: lower case, a digit, or a
/// hyphen.
fn std3(character : Char) -> Bool {
  let point = character.to_int()
  (point >= 0x61 && point <= 0x7A) ||
  (point >= 0x30 && point <= 0x39) ||
  point == 0x2D
}

///|
/// Whether `character` is a combining mark: General_Category Mn, Mc or Me.
fn mark(character : Char) -> Bool {
  match @moonucd.category(character) {
    Mn | Mc | Me => true
    _ => false
  }
}

///|
/// The ContextJ rules of RFC 5892 Appendix A, which are two regular
/// expressions over joining types, transparent characters and all:
///
/// - a zero width non-joiner needs `(L|D) T* ZWNJ T* (R|D)`, or a virama in
///   front of it;
/// - a zero width joiner needs `(L|D) T* ZWJ`, or a virama in front of it.
fn joiners(chars : Array[Char], at : Int32, errors : Array[Fault]) -> Unit {
  for i, character in chars {
    if character != '\u{200C}' && character != '\u{200D}' {
      continue
    }
    // A virama in front of a joiner is enough on its own.
    let mut ok = i > 0 && @normalize.combining(chars[i - 1]) == 9
    if !ok && i > 0 {
      // Otherwise a character that joins to what follows has to be in front
      // of it, whatever transparent characters stand between the two.
      let mut back = i
      while back > 0 {
        back -= 1
        let kind = joining(chars[back])
        if kind == 5 {
          continue
        }
        ok = kind == 2 || kind == 3
        break
      }
      // A non-joiner also needs one that joins to what came before, on the
      // other side.
      if ok && character == '\u{200C}' {
        let mut forward = i + 1
        ok = false
        while forward < chars.length() {
          let kind = joining(chars[forward])
          if kind != 5 {
            ok = kind == 1 || kind == 3
            break
          }
          forward += 1
        }
      }
    }
    if !ok {
      errors.push(Joiner(at=at + i))
    }
  }
}

///|
/// Whether the name is a bidi domain name: one with a right-to-left character
/// anywhere in it (UTS 46 §2.3).
fn bidi_domain(labels : Array[Label]) -> Bool {
  for label in labels {
    for character in label.chars {
      match @moonucd.bidi(character) {
        R | AL | AN => return true
        _ => ()
      }
    }
  }
  false
}

///|
/// The six conditions of RFC 5893 §2, whose wording the six branches follow.
fn rule(chars : Array[Char], at : Int32, errors : Array[Fault]) -> Unit {
  let n = chars.length()
  let first = @moonucd.bidi(chars[0])
  if first == R || first == AL {
    for character in chars {
      let kind = @moonucd.bidi(character)
      let allowed = kind == R ||
        kind == AL ||
        kind == AN ||
        kind == EN ||
        kind == ES ||
        kind == CS ||
        kind == ET ||
        kind == ON ||
        kind == BN ||
        kind == NSM
      if !allowed {
        errors.push(Bidi(at~))
        return
      }
    }
    let mut last = n - 1
    while last > 0 && @moonucd.bidi(chars[last]) == NSM {
      last -= 1
    }
    let kind = @moonucd.bidi(chars[last])
    if !(kind == R || kind == AL || kind == EN || kind == AN) {
      errors.push(Bidi(at~))
      return
    }
    let mut european = false
    let mut arabic = false
    for character in chars {
      let kind = @moonucd.bidi(character)
      if kind == EN {
        european = true
      } else if kind == AN {
        arabic = true
      }
    }
    if european && arabic {
      errors.push(Bidi(at~))
    }
  } else if first == L {
    for character in chars {
      let kind = @moonucd.bidi(character)
      let allowed = kind == L ||
        kind == EN ||
        kind == ES ||
        kind == CS ||
        kind == ET ||
        kind == ON ||
        kind == BN ||
        kind == NSM
      if !allowed {
        errors.push(Bidi(at~))
        return
      }
    }
    let mut last = n - 1
    while last > 0 && @moonucd.bidi(chars[last]) == NSM {
      last -= 1
    }
    let kind = @moonucd.bidi(chars[last])
    if !(kind == L || kind == EN) {
      errors.push(Bidi(at~))
    }
  } else {
    errors.push(Bidi(at~))
  }
}

// --------------------------------------------------------------------- length

///|
/// The DNS length limits of UTS 46 §4.2 step 4: 253 octets in a name, 63 in a
/// label, and no empty label at all.
fn audit(
  text : StringView,
  labels : Array[Label],
  errors : Array[Fault],
) -> Unit {
  let mut name = text
  if name.length() > 0 && name[name.length() - 1] == '.' {
    name = name[:name.length() - 1]
  }
  if name.length() == 0 || name.length() > 253 {
    errors.push(Length(limit=253, got=name.length()))
  }
  for label in labels {
    let text = text_of(label.chars)
    let size = if ascii_only(text[:]) {
      text.length()
    } else {
      4 + encode(text[:]).length()
    }
    if size == 0 {
      errors.push(Empty(at=label.at))
    } else if size > 63 {
      errors.push(Length(limit=63, got=size))
    }
  }
}

// ------------------------------------------------------------------ plumbing

///|
/// A label as text.
fn text_of(chars : Array[Char]) -> String {
  let out = StringBuilder()
  for character in chars {
    out.write_char(character)
  }
  out.to_string()
}

///|
/// Whether every character is ASCII.
fn ascii_only(text : StringView) -> Bool {
  for character in text {
    if character.to_int() >= 0x80 {
      return false
    }
  }
  true
}
