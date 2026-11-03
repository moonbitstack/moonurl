// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The port rules of the URL Standard: a special scheme has a default port it
// does not write, a port outside 16 bits is a failure, and leading zeroes read
// as the number they spell.

///|
fn ports_url(text : String) -> @moonurl.Url raise @moonurl.Refused {
  @moonurl.Url::decode(text[:], syntax=@moonurl.Whatwg)
}

///|
fn ports_refused(text : String) -> Bool {
  try {
    ports_url(text) |> ignore
    false
  } catch {
    _ => true
  }
}

///|
/// Every special scheme drops its own default port and keeps any other.
test "a special scheme writes no default port and keeps the rest" {
  assert_eq(ports_url("http://h:80/").encode(), "http://h/")
  assert_eq(ports_url("https://h:443/").encode(), "https://h/")
  assert_eq(ports_url("ws://h:80/").encode(), "ws://h/")
  assert_eq(ports_url("wss://h:443/").encode(), "wss://h/")
  assert_eq(ports_url("ftp://h:21/").encode(), "ftp://h/")
  // A port that is not that scheme's default stays.
  assert_eq(ports_url("http://h:443/").encode(), "http://h:443/")
  assert_eq(ports_url("https://h:80/").encode(), "https://h:80/")
  assert_eq(ports_url("ftp://h:80/").encode(), "ftp://h:80/")
  // A non-special scheme has no default port, so nothing is dropped.
  assert_eq(ports_url("foo://h:80/").encode(), "foo://h:80/")
  assert_eq(ports_url("foo://h:21/").encode(), "foo://h:21/")
}

///|
/// Port 0 is a port; an empty port is none; past 65535 is a failure.
test "the ends of the port range" {
  assert_eq(ports_url("http://h:0/").encode(), "http://h:0/")
  assert_eq(ports_url("http://h:65535/").encode(), "http://h:65535/")
  assert_eq(ports_url("http://h:/").encode(), "http://h/")
  assert_true(ports_refused("http://h:65536/"))
  assert_true(ports_refused("http://h:99999/"))
}

///|
/// Leading zeroes spell a number; a non-digit is not a port.
test "leading zeroes and non-digits" {
  assert_eq(ports_url("http://h:0080/").encode(), "http://h/")
  assert_eq(ports_url("http://h:08080/").encode(), "http://h:8080/")
  assert_true(ports_refused("http://h:80x/"))
}

///|
/// The port setter follows the same rules, and a value it cannot read leaves
/// the URL where it was.
test "setting a port" {
  let url = ports_url("http://h/")
  assert_eq(url.set_port("443").encode(), "http://h:443/")
  assert_eq(url.set_port("80").encode(), "http://h/")
  assert_eq(url.set_port("0").encode(), "http://h:0/")
  assert_eq(url.set_port("").encode(), "http://h/")
  assert_eq(url.set_port("99999").encode(), "http://h/")
  assert_eq(url.set_port("eighty").encode(), "http://h/")
  let secure = ports_url("https://h/")
  assert_eq(secure.set_port("443").encode(), "https://h/")
}
