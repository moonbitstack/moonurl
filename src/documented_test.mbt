// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Every value the README prints for this package, asserted here. A snippet that
// compiles but states a result the library does not produce is worse than no
// snippet, so the two halves — prose and code — are checked against each other.

///|
/// The reference, read both ways, and the host names beside it.
test "the reference the README opens with" {
  let generic = @moonurl.Url::decode("HTTP://EXAMPLE.test:80/a/../b")
  assert_eq(generic.encode(), "HTTP://EXAMPLE.test:80/a/../b")
  assert_eq(generic.scheme, Some("HTTP"))
  assert_eq(generic.normalize().encode(), "http://example.test:80/b")
  let browser = @moonurl.Url::decode(
    "HTTP://EXAMPLE.test:80/a/../b",
    syntax=@moonurl.Whatwg,
  )
  assert_eq(browser.encode(), "http://example.test/b")
  assert_eq(browser.port, None)
  assert_eq(@moonurl.domain("MÜNCHEN.example"), "xn--mnchen-3ya.example")
  let numeric = @moonurl.Url::decode(
    "http://192.0x00A80001/",
    syntax=@moonurl.Whatwg,
  )
  assert_eq(numeric.host, Some("192.168.0.1"))
}

///|
/// One reference with every component set: the table of fields the README
/// prints, and the origin derived from them.
test "the components the README reads back" {
  let url = @moonurl.Url::decode("https://leo:pw@example.test:8443/a/b?x=1#top")
  assert_eq(url.scheme, Some("https"))
  assert_eq(url.host, Some("example.test"))
  assert_eq(url.port, Some(8443))
  assert_eq(url.query, Some("x=1"))
  assert_eq(url.origin(), "https://example.test:8443")
}

///|
/// A form body kept in the order it arrived, with the repeated name intact.
test "the form body the README builds" {
  let form = @moonurl.Query::decode(b"a=1&b=2&a=3")
  assert_eq(form.get("a"), Some("1"))
  assert_eq(form.values("a"), ["1", "3"])
  assert_eq(form.encode(), "a=1&b=2&a=3")
  let edited = @moonurl.Query::new(pairs=[("q", "two words")])
  assert_eq(edited.encode(), "q=two+words")
}

///|
/// Resolving against a base, and the origin two URLs share.
test "the reference the README resolves" {
  let base = @moonurl.Url::decode("http://example.test/a/b/c")
  assert_eq(
    base.resolve(@moonurl.Url::decode("../d")).encode(),
    "http://example.test/a/d",
  )
  let site = @moonurl.Url::decode("https://example.test:8443/a")
  assert_eq(site.origin(), "https://example.test:8443")
}
