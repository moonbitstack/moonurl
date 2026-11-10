// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The name–value pairs of an `application/x-www-form-urlencoded` string: a URL's
/// query, or a form body (WHATWG URL Standard §5). Order and repeated names are
/// kept, as `URLSearchParams` and Go's `url.Values` keep them.
#derive(Eq, Debug)
pub struct Query {
  priv pairs : Array[(String, String)]
}

///|
pub extend Query with Eq::{equal, not_equal}

///|
pub extend Query with Debug::{to_repr}

///|
/// What a decode accepts. Past either bound the whole input is refused rather
/// than cut short, so a handler never acts on part of a form.
#derive(Eq, Debug)
pub(all) struct Limits {
  /// Most pairs.
  pairs : Int32
  /// Most bytes in one pair as it arrives, still encoded.
  size : Int32
}

///|
pub extend Limits with Eq::{equal, not_equal}

///|
pub extend Limits with Debug::{to_repr}

///|
/// A thousand pairs of up to 1 MiB each: Starlette's `max_fields` and
/// `max_part_size`, and the `parameterLimit` of Node's `qs`.
pub let limits : Limits = { pairs: 1000, size: 1 << 20, }

///|
/// Limits by name, each defaulting to the preset's.
pub fn Limits::new(
  pairs~ : Int32 = limits.pairs,
  size~ : Int32 = limits.size,
) -> Limits {
  { pairs, size, }
}

///|
/// A query holding `pairs`, in order.
pub fn Query::new(pairs? : Array[(String, String)]) -> Query {
  { pairs: pairs.map(p => p.copy()).unwrap_or([]), }
}

///|
/// Read an `application/x-www-form-urlencoded` string (WHATWG URL Standard §5.1).
///
/// `&` separates pairs and the first `=` separates a name from its value; `+` is
/// a space here and nowhere else in a URL. Escapes are undone to octets and the
/// octets read as UTF-8, a broken sequence becoming U+FFFD. An empty piece
/// between two `&` is no pair at all.
///
/// ```mbt check
/// test {
///   let form = @moonurl.Query::decode(b"q=moon+bit&tag=a&tag=b")
///   assert_eq(form.get("q"), Some("moon bit"))
///   assert_eq(form.values("tag"), ["a", "b"])
///   assert_eq(form.encode(), "q=moon+bit&tag=a&tag=b")
/// }
/// ```
pub fn Query::decode(
  raw : BytesView,
  limits~ : Limits = limits,
) -> Query raise Refused {
  let pairs = []
  let n = raw.length()
  let mut start = 0
  for i in 0..<=n {
    guard i == n || raw[i] == b'&' else { continue }
    if i > start {
      if pairs.length() == limits.pairs {
        raise Pairs(limit=limits.pairs)
      }
      if i - start > limits.size {
        raise Pair(limit=limits.size, got=i - start)
      }
      let piece = raw[start:i]
      pairs.push(
        match piece.find(b"=") {
          Some(eq) => (form_text(piece[:eq]), form_text(piece[eq + 1:]))
          None => (form_text(piece), "")
        },
      )
    }
    start = i + 1
  }
  { pairs, }
}

///|
/// Write the pairs as `application/x-www-form-urlencoded` (WHATWG URL Standard
/// §5.2): letters, digits and `*-._` stand for themselves, a space is `+`, and
/// every other octet of the UTF-8 is `%XX`.
pub fn Query::encode(self : Query) -> String {
  let out = StringBuilder()
  for i, pair in self.pairs {
    if i > 0 {
      out.write_char('&')
    }
    form_escape(out, pair.0)
    out.write_char('=')
    form_escape(out, pair.1)
  }
  out.to_string()
}

///|
/// The first value under `name`.
pub fn Query::get(self : Query, name : StringView) -> String? {
  for pair in self.pairs {
    if pair.0[:] == name {
      return Some(pair.1)
    }
  }
  None
}

///|
/// Every value under `name`, in order.
pub fn Query::values(self : Query, name : StringView) -> Array[String] {
  self.pairs.filter(p => p.0[:] == name).map(p => p.1)
}

///|
/// Whether any pair is named `name`.
pub fn Query::has(self : Query, name : StringView) -> Bool {
  self.pairs.iter().any(p => p.0[:] == name)
}

///|
/// Add a pair at the end, keeping any already under `name`.
pub fn Query::add(self : Query, name : String, value : String) -> Unit {
  self.pairs.push((name, value))
}

///|
/// Leave exactly one pair under `name`, holding `value`: the first one's place
/// if there was one, the end if not.
pub fn Query::set(self : Query, name : String, value : String) -> Unit {
  match self.pairs.search_by(p => p.0 == name) {
    Some(at) => {
      self.pairs[at] = (name, value)
      let mut i = 0
      self.pairs.retain(p => {
        let keep = i == at || p.0 != name
        i += 1
        keep
      })
    }
    None => self.pairs.push((name, value))
  }
}

///|
/// Remove every pair under `name`.
pub fn Query::remove(self : Query, name : StringView) -> Unit {
  self.pairs.retain(p => p.0[:] != name)
}

///|
/// Put the pairs in order by name, keeping pairs that share a name in the
/// order they arrived (WHATWG URL Standard §5.1, `URLSearchParams.sort`).
///
/// The order is that of the UTF-16 code units of the names, which is what a
/// browser sorts by, so `\u{1F308}` comes before `\u{FB03}`: its high
/// surrogate is the smaller unit even though the code point is the larger.
/// [`Query::encode`] keeps whatever order it is given, so this is how two
/// bodies with the same pairs come out byte for byte alike. It does not touch
/// the pairs' values.
///
/// ```mbt check
/// test {
///   let body = @moonurl.Query::decode(b"b=2&a=1&b=3")
///   body.sort()
///   assert_eq(body.encode(), "a=1&b=2&b=3")
/// }
/// ```
pub fn Query::sort(self : Query) -> Unit {
  // The order pairs arrived in is part of the answer, so each one carries its
  // place and the comparison falls back on it: equal names keep their order
  // whichever way the sort underneath moves its equals.
  let numbered = Array::makei(self.pairs.length(), i => (i, self.pairs[i]))
  numbered.sort_by((a, b) => {
    let by_name = units_order(a.1.0[:], b.1.0[:])
    if by_name != 0 {
      by_name
    } else {
      a.0 - b.0
    }
  })
  for i, entry in numbered {
    self.pairs[i] = entry.1
  }
}

///|
/// Compare two strings the way the URL standard orders them: unit by unit of
/// UTF-16, the shorter one first when one is a prefix of the other.
fn units_order(a : StringView, b : StringView) -> Int32 {
  let shorter = if a.length() < b.length() { a.length() } else { b.length() }
  for i = 0; i < shorter; i = i + 1 {
    let difference = a[i].to_int() - b[i].to_int()
    if difference != 0 {
      return difference
    }
  }
  a.length() - b.length()
}

///|
/// Every pair, in order.
pub fn Query::entries(self : Query) -> Array[(String, String)] {
  self.pairs.copy()
}

///|
/// One encoded name or value as text.
fn form_text(raw : BytesView) -> String {
  let spaced = Bytes::makei(raw.length(), i => {
    if raw[i] == b'+' {
      b' '
    } else {
      raw[i]
    }
  })
  @utf8.decode_lossy(unescape(spaced)[:])
}

///|
/// Append `text` in the form serialiser's escaping.
fn form_escape(out : StringBuilder, text : String) -> Unit {
  let digits = "0123456789ABCDEF"
  for b in @utf8.encode(text) {
    match b {
      b' ' => out.write_char('+')
      b'*' | b'-' | b'.' | b'_' | b'0'..<=b'9' | b'A'..<=b'Z' | b'a'..<=b'z' =>
        out.write_char(b.to_int().unsafe_to_char())
      _ => {
        out.write_char('%')
        out.write_char(digits[b.to_int() / 16].unsafe_to_char())
        out.write_char(digits[b.to_int() % 16].unsafe_to_char())
      }
    }
  }
}
