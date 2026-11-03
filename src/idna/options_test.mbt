// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Each switch of UTS 46 turns one class of name from tolerated to refused, and
// each has to do so on its own: a preset that quietly ignores one switch would
// let a zone file, or a link, through with the wrong name.

///|
/// Hyphens in the leading, trailing or third-and-fourth positions are a name a
/// browser keeps and a zone file refuses (V2, V3, V4).
test "the hyphen rules are off by default and on under strict" {
  for name in ["-x", "x-", "ab--c"] {
    assert_true(@idna.to_ascii(name[:]).is_ok())
    assert_false(@idna.to_ascii(name[:], options=@idna.strict).is_ok())
  }
}

///|
/// A zero width non-joiner out of context is a joiner fault unless the rule is
/// turned off.
test "the joiner rule is on unless turned off" {
  assert_false(@idna.to_ascii("a\u{200C}b").is_ok())
  let off = { ..@idna.options, check_joiners: false, }
  assert_true(@idna.to_ascii("a\u{200C}b", options=off).is_ok())
}

///|
/// An `xn--` label that does not decode is passed over by default and refused
/// when the caller asks to be told.
test "punycode that does not decode is passed over unless asked" {
  assert_true(@idna.to_ascii("xn--999999999999").is_ok())
  let strict = { ..@idna.options, ignore_invalid_punycode: false, }
  assert_false(@idna.to_ascii("xn--999999999999", options=strict).is_ok())
}

///|
/// A label that mixes directions is a fault only while the bidi rule is on.
test "the bidi rule applies only where asked" {
  assert_false(@idna.to_ascii("\u{05D0}a").is_ok())
  let off = { ..@idna.options, check_bidi: false, }
  assert_true(@idna.to_ascii("\u{05D0}a", options=off).is_ok())
}

///|
/// Transitional processing is a switch, not a default: the sharp s folds to
/// `ss` only when it is asked for.
test "transitional processing is a switch, not a default" {
  assert_eq(@idna.to_ascii("Faß.de").name, "xn--fa-hia.de")
  let transitional = { ..@idna.options, transitional: true, }
  assert_eq(@idna.to_ascii("Faß.de", options=transitional).name, "fass.de")
}
