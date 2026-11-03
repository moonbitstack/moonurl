// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Known Punycode encodings, computed once by the standard library's own
// encoder so that a mistake in this package's bias or digit arithmetic cannot
// hide behind a symmetric round trip: an encoder and decoder that share the
// error agree with each other and with nobody else.

///|
let known_labels : Array[(String, String)] = [
  ("münchen", "mnchen-3ya"),
  ("bücher", "bcher-kva"),
  ("ü", "tda"),
  ("中国", "fiqs8s"),
  ("日本語", "wgv71a119e"),
  ("例え", "r8jz45g"),
  ("göttingen", "gttingen-n4a"),
  ("παράδειγμα", "hxajbheg2az3al"),
  ("пример", "e1afmkfd"),
  ("מבחן", "5dbmtg"),
  ("faß", "fa-hia"),
  ("İstanbul", "stanbul-ifb"),
  ("naïve", "nave-6pa"),
  ("café", "caf-dma"),
  ("Straße", "Strae-oqa"),
  ("他们", "8mqxb"),
  ("\u{1F600}", "e28h"),
  ("üñîçø∂é", "7caenl1bu6920d"),
  ("日本語テスト", "zckzah9945czlbtz6h"),
  ("ドメイン名例", "eckwd4c7cu47r2wf"),
  // An all-ASCII label writes its basic string and the delimiter, and nothing
  // after it.
  ("a", "a-"),
  ("abc", "abc-"),
  ("a-b", "a-b-"),
  ("123", "123-"),
]

///|
/// Encode to the independent encoder's answer, and decode back to the label.
test "the independent encoder's answers" {
  for (label, punycode) in known_labels {
    assert_eq(@idna.encode(label[:]), punycode)
    assert_eq(@idna.decode(punycode[:]), label)
  }
}

///|
/// The digit run reads either case, since a name may have been upper cased on
/// its way here and case carries nothing in Punycode (§6.2). The basic part is
/// literal, so its case is kept.
test "a decoding reads either case of digit" {
  assert_eq(@idna.decode("bcher-KVA"[:]), "bücher")
  assert_eq(@idna.decode("mnchen-3Ya"[:]), "münchen")
}

///|
/// A label that carries ASCII writes the delimiter even when there is nothing
/// after it; a label with no ASCII at all writes none, because a leading `-`
/// would read as a delimiter.
test "the delimiter appears only when there is ASCII before it" {
  assert_true(@idna.encode("a").contains("-"))
  assert_false(@idna.encode("他们").contains("-"))
}
