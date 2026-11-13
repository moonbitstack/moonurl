// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The three switches `strict` turns on that nothing else in the suite reaches
// — the hyphen rules are in `options_test.mbt` — and the two lengths it audits.
// Each is checked with the other switches off, because a name refused by two
// rules at once says nothing about either.

///|
fn repeat(text : String, times : Int32) -> String {
  let out = StringBuilder()
  for i = 0; i < times; i = i + 1 {
    out.write_string(text)
  }
  out.to_string()
}

///|
/// A dot at either end of an ASCII label is a hole in the name: a browser keeps
/// `a..b` and a zone file will not hold it.
test "an empty label is refused when the lengths are audited" {
  assert_true(@idna.to_ascii("a..b").is_ok())
  assert_false(@idna.to_ascii("a..b", options=@idna.strict).is_ok())
  let hole = @idna.to_ascii("a..b", options=@idna.strict)
  assert_eq(hole.errors, [@idna.Empty(at=2)])
  // A name that ends in the dot of the root label is not a hole; the dot after
  // `a` is the root, and a name that is only dots has nothing in it.
  assert_true(@idna.to_ascii("a.").is_ok())
  assert_false(@idna.to_ascii("a.", options=@idna.strict).is_ok())
  assert_false(@idna.to_ascii("", options=@idna.strict).is_ok())
  assert_eq(@idna.to_ascii("", options=@idna.strict).errors, [
    @idna.Length(limit=253, got=0),
    @idna.Empty(at=0),
  ])
}

///|
/// 63 octets in a label and 253 in a name are the DNS limits (UTS 46 §4.2 step
/// 4), counted after Punycode, which is longer than the name it stands for.
test "the DNS lengths, at the limit and one past it" {
  let label = repeat("a", 63)
  assert_true(@idna.to_ascii(label[:]).is_ok())
  assert_true(@idna.to_ascii(label[:], options=@idna.strict).is_ok())
  let one_more = repeat("a", 64)
  // Without the audit a 64-octet label is a name like any other: browsers
  // address it, only the DNS cannot hold it.
  assert_true(@idna.to_ascii(one_more[:]).is_ok())
  assert_eq(@idna.to_ascii(one_more[:], options=@idna.strict).errors, [
    @idna.Length(limit=63, got=64),
  ])
  // A name of exactly 253 octets fits, and the same name with one more does not.
  let fitting = repeat(label + ".", 3) + repeat("a", 61)
  assert_eq(fitting.length(), 253)
  assert_true(@idna.to_ascii(fitting[:], options=@idna.strict).is_ok())
  let over = repeat(label + ".", 3) + repeat("a", 62)
  assert_eq(over.length(), 254)
  assert_eq(@idna.to_ascii(over[:], options=@idna.strict).errors, [
    @idna.Length(limit=253, got=254),
  ])
}

///|
/// The limit is on the octets that go on the wire, so a label of non-ASCII
/// characters is measured after Punycode, not before.
test "the limit counts the label that is written, not the one that is read" {
  // Fifty-seven `ü` are 57 characters over the wire as Unicode and 59 octets of
  // Punycode under the four of the `xn--` prefix: 63, at the limit.
  let written = repeat("ü", 57)
  let outcome = @idna.to_ascii(written[:], options=@idna.strict)
  assert_true(outcome.is_ok())
  assert_eq(outcome.name.length(), 63)
  assert_eq(@idna.to_ascii(repeat("ü", 58)[:], options=@idna.strict).errors, [
    @idna.Length(limit=63, got=64),
  ])
}

///|
/// The STD 3 rules are one switch over the characters an ASCII name may hold:
/// of the ASCII that UTS 46 calls valid, only letters, digits and the hyphen
/// pass UTS 46's own note on zone files (U1).
test "the STD 3 rules are off by default and on under strict" {
  for name in ["a_b.example", "a b.example", "a!b.example", "a*b.example"] {
    assert_true(@idna.to_ascii(name[:]).is_ok())
    assert_false(@idna.to_ascii(name[:], options=@idna.strict).is_ok())
  }
  // The fault names the character and where it sits in the name.
  assert_eq(@idna.to_ascii("a_b.example", options=@idna.strict).errors, [
    @idna.Std3(at=1, got='_'),
  ])
  assert_eq(@idna.to_ascii("a b.example", options=@idna.strict).errors, [
    @idna.Std3(at=1, got=' '),
  ])
  // Switching STD 3 off alone leaves the other two switches as they were.
  let lenient = { ..@idna.strict, std3: false, }
  assert_true(@idna.to_ascii("a_b.example", options=lenient).is_ok())
  assert_false(@idna.to_ascii("a..b", options=lenient).is_ok())
}

///|
/// `strict` is the preset that has all three on. A preset that carried one of
/// them off would pass a name a zone file cannot hold, so the record is spelled
/// out here rather than left to the defaults.
test "the strict preset is the three switches, and the default is none" {
  assert_eq(@idna.strict, {
    transitional: false,
    check_hyphens: true,
    check_bidi: true,
    check_joiners: true,
    std3: true,
    dns_length: true,
    ignore_invalid_punycode: false,
  })
  assert_eq(@idna.options, {
    transitional: false,
    check_hyphens: false,
    check_bidi: true,
    check_joiners: true,
    std3: false,
    dns_length: false,
    ignore_invalid_punycode: true,
  })
}

///|
/// Reading a name back has the same rules, and one of its own: an empty label
/// is a name with a hole in it even when the lengths are not audited, because a
/// hole is not a length.
test "reading a name back finds the hole the lengths would" {
  assert_eq(@idna.to_unicode("a..b").errors, [@idna.Empty(at=2)])
  assert_eq(@idna.to_unicode("a.").errors, [])
  assert_eq(@idna.to_unicode("").errors, [@idna.Empty(at=0)])
  assert_eq(@idna.to_unicode("xn--mnchen-3ya.example").name, "münchen.example")
  assert_eq(@idna.to_unicode(".example").errors, [@idna.Empty(at=0)])
}
