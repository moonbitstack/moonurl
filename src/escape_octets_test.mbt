// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Percent coding has to be a bijection on octets in every component: a byte
// that survives escaping and unescaping differently would corrupt a request
// target on the way out and a form body on the way in.

///|
fn all_octets() -> Bytes {
  let out : Array[Byte] = []
  for i = 0; i < 256; i = i + 1 {
    out.push(i.to_byte())
  }
  Bytes::from_array(out)
}

///|
/// Every octet, in every component, comes back as itself.
test "every octet is the same octet after a round trip" {
  let raw = all_octets()
  for
    kind in [
      @moonurl.Bare,
      @moonurl.Host,
      @moonurl.Userinfo,
      @moonurl.Segment,
      @moonurl.Path,
      @moonurl.Query,
      @moonurl.Fragment,
    ] {
    let coded = @moonurl.escape(raw[:], kind~)
    assert_eq(@moonurl.unescape(@utf8.encode(coded)[:]), raw)
    assert_true(@moonurl.escaped(coded[:], kind~))
  }
  // `Whole` keeps a bare `%` as it stands — the value is already a URI — so
  // `escaped` rightly calls it incomplete; the round trip still holds.
  let whole = @moonurl.escape(raw[:], kind=@moonurl.Whole)
  assert_eq(@moonurl.unescape(@utf8.encode(whole)[:]), raw)
}

///|
/// Escapes are two digits wide and upper case (§6.2.2.1).
test "escapes are two digits wide and upper case" {
  assert_eq(@moonurl.escape(b"\x00"[:]), "%00")
  assert_eq(@moonurl.escape(b"\x7F"[:]), "%7F")
  assert_eq(@moonurl.escape(b"\xFF"[:]), "%FF")
  assert_eq(@moonurl.escape(b"a b"[:]), "a%20b")
  assert_eq(@moonurl.escape(b"%25"[:]), "%2525")
}

///|
/// Normalising escapes is idempotent: a second pass changes nothing.
test "normalising escapes is idempotent" {
  for text in ["%7e%2Fa", "%E9%AA%87", "100%", "a%2fb%3Fc", ""] {
    let once = @moonurl.normalize_escapes(text[:])
    assert_eq(@moonurl.normalize_escapes(once[:]), once)
  }
}
