// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The two conversions the README prints: the default mapping, and the
// transitional one that turns `ß` into `ss` for callers that still need it.

///|
test "the names the README converts" {
  let outcome = @idna.to_ascii("münchen.example")
  assert_eq(outcome.name, "xn--mnchen-3ya.example")
  assert_eq(outcome.is_ok(), true)
  assert_eq(@idna.to_ascii("Faß.de").name, "xn--fa-hia.de")
  let transitional = { ..@idna.options, transitional: true, }
  assert_eq(@idna.to_ascii("Faß.de", options=transitional).name, "fass.de")
}
