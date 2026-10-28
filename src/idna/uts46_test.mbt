// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "punycode round trips through its own encoding" {
  for
    label in [
      "münchen", "他们为什么不说中文", "ليهمابتكلموشعربي؟",
      "他们", "ü", "a", "", "\u{1F600}",
    ] {
    assert_eq(@idna.decode(@idna.encode(label[:])[:]), label)
  }
}

///|
/// The samples the RFC prints (§7.1), and the label sizes that make the last
/// digit of the encoding change.
test "punycode prints the samples of RFC 3492 §7.1" {
  assert_eq(@idna.encode("bücher"), "bcher-kva")
  assert_eq(@idna.decode("bcher-kva"[:]), "bücher")
  assert_eq(
    @idna.encode("他们为什么不说中文"),
    "ihqwcrb4cv8a8dqg056pqjye",
  )
  assert_eq(
    @idna.decode("ihqwcrb4cv8a8dqg056pqjye"[:]),
    "他们为什么不说中文",
  )
  assert_eq(
    @idna.encode("ليهمابتكلموشعربي؟"),
    "egbpdaj6bu4bxfgehfvwxn",
  )
  assert_eq(@idna.encode("3年B組金八先生"), "3B-ww4c5e180e575a65lsy2b")
  // A label with no ASCII carries no delimiter; one with ASCII does.
  assert_false(@idna.encode("他们").contains("-"))
  assert_true(@idna.encode("münchen").contains("-"))
}

///|
test "an A-label that does not decode is refused" {
  // A trailing delimiter is a label whose body is empty, which is fine; a
  // body of digits that never terminates is not.
  assert_eq(@idna.decode("bcher-kva-"[:]), "bcher-kva")
  let bad = try {
    @idna.decode("999999999999"[:]) |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(bad)
}

///|
test "a name goes to ASCII and back" {
  let ascii = @idna.to_ascii("münchen.example")
  assert_true(ascii.is_ok())
  assert_eq(ascii.name, "xn--mnchen-3ya.example")
  let unicode = @idna.to_unicode(ascii.name[:])
  assert_true(unicode.is_ok())
  assert_eq(unicode.name, "münchen.example")
}

///|
test "the mapping step folds case, width and compatibility" {
  assert_eq(
    @idna.to_ascii("ＥＸＡＭＰＬＥ。example").name,
    "example.example",
  )
  assert_eq(@idna.to_ascii("Faß.de").name, "xn--fa-hia.de")
  let transitional = { ..@idna.options, transitional: true, }
  assert_eq(@idna.to_ascii("Faß.de", options=transitional).name, "fass.de")
}

///|
test "a name the rules refuse is reported, and converted as far as it goes" {
  // A no-break space is a space spelled another way, and a space is no part of
  // a host name once the STD 3 rules are on.
  let outcome = @idna.to_ascii("a\u{00A0}b")
  assert_true(outcome.is_ok())
  assert_eq(outcome.name, "a b")
  let strict = @idna.to_ascii("a\u{00A0}b", options=@idna.strict)
  assert_false(strict.is_ok())
  // A control character stops the conversion nowhere; it is reported, and the
  // label still goes out as an A-label.
  let control = @idna.to_ascii("a\u{0080}b")
  assert_false(control.is_ok())
  assert_eq(control.name, "xn--ab-ba")
  assert_eq(@idna.to_unicode("a\u{0080}b").name, "a\u{0080}b")
  // Under STD 3 an underscore is not a host name character.
  assert_true(@idna.to_ascii("a_b").is_ok())
  assert_false(@idna.to_ascii("a_b", options=@idna.strict).is_ok())
}

///|
test "the bidi rule refuses a label that mixes directions" {
  assert_false(@idna.to_ascii("\u{05D0}a").is_ok())
  assert_true(@idna.to_ascii("\u{05D0}").is_ok())
}

///|
test "the DNS limits are only checked when asked" {
  let long = "a".repeat(64)
  assert_true(@idna.to_ascii(long[:]).is_ok())
  assert_false(@idna.to_ascii(long[:], options=@idna.strict).is_ok())
}
