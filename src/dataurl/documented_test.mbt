// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The data URL the README reads and writes back, in both spellings.

///|
test "the data URL the README writes" {
  let greeting = @dataurl.Url::decode("data:text/plain,Hi%20there")
  assert_eq(greeting.kind, "text/plain")
  assert_eq(greeting.data, b"Hi there")
  assert_eq(greeting.charset(), "US-ASCII")
  assert_eq(greeting.encode(base64=true), "data:text/plain;base64,SGkgdGhlcmU=")
}
