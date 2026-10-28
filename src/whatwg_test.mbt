// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// What the two grammars disagree about, one case at a time. The generated
// suites cover the whole of it; these say why.

///|
fn whatwg(text : String) -> @moonurl.Url raise @moonurl.Refused {
  @moonurl.Url::decode(text[:], syntax=@moonurl.Whatwg)
}

///|
/// A special scheme has a port it does not write and a path that always
/// starts at a solidus.
test "a special scheme fills in what nobody wrote" {
  assert_eq(whatwg("http://example.test").encode(), "http://example.test/")
  assert_eq(whatwg("http://example.test:80/").encode(), "http://example.test/")
  assert_eq(
    whatwg("https://example.test:443/").encode(),
    "https://example.test/",
  )
  assert_eq(
    whatwg("https://example.test:80/").encode(),
    "https://example.test:80/",
  )
  assert_eq(whatwg("ws://h:80/").port, None)
  assert_eq(whatwg("ftp://h:21/").port, None)
  // A scheme with no port of its own keeps whatever it is given.
  assert_eq(whatwg("foo://h:21/").port, Some(21))
}

///|
test "the scheme and the host are case, the path is not" {
  assert_eq(
    whatwg("HTTP://EXAMPLE.TEST/A/B").encode(),
    "http://example.test/A/B",
  )
}

///|
/// A backslash is a solidus under a special scheme, and a character like any
/// other everywhere else.
test "a backslash is a solidus where the scheme is special" {
  assert_eq(
    whatwg("http:\\\\example.test\\a").encode(),
    "http://example.test/a",
  )
  assert_eq(whatwg("foo://h/a\\b").path, "/a\\b")
}

///|
test "a host is a number in any of its spellings" {
  assert_eq(whatwg("http://127.0.0.1/").host, Some("127.0.0.1"))
  assert_eq(whatwg("http://0x7f.1/").host, Some("127.0.0.1"))
  assert_eq(whatwg("http://0177.0.0.1/").host, Some("127.0.0.1"))
  assert_eq(whatwg("http://2130706433/").host, Some("127.0.0.1"))
  assert_eq(whatwg("http://[::ffff:127.0.0.1]/").host, Some("::ffff:7f00:1"))
  assert_eq(whatwg("http://[2001:db8:0:0:0:0:0:1]/").host, Some("2001:db8::1"))
  // Four parts is the most a dotted number may have.
  let refused = try {
    whatwg("http://1.2.3.4.5/") |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(refused)
}

///|
test "a file URL has a host even when it looks like it has none" {
  let url = whatwg("file:///tmp/x")
  assert_eq(url.host, Some(""))
  assert_eq(url.path, "/tmp/x")
  // `C|` and `C:` are the same drive, and the drive is not a host.
  assert_eq(whatwg("file://C:/x").path, "/C:/x")
  assert_eq(whatwg("file://C|/x").path, "/C:/x")
  assert_eq(whatwg("file://localhost/x").host, Some(""))
}

///|
/// A scheme with no authority behind it has a path that is one string, which
/// is why `mailto:` has no segments to shorten.
test "an opaque path is one string" {
  let url = whatwg("mailto:leo@example.test?subject=a b")
  assert_eq(url.host, None)
  assert_eq(url.path, "leo@example.test")
  assert_eq(url.query, Some("subject=a%20b"))
  // Nothing shortens it: `..` is part of the address, not a segment.
  assert_eq(whatwg("foo:a/../b").path, "a/../b")
}

///|
test "the query and the fragment keep what they may carry" {
  assert_eq(whatwg("http://h/?a=b c").query, Some("a=b%20c"))
  // `'` is escaped in a special scheme's query and left alone elsewhere.
  assert_eq(whatwg("http://h/?a='").query, Some("a=%27"))
  assert_eq(whatwg("foo://h/?a='").query, Some("a='"))
  // The backtick is escaped in a fragment and nowhere else.
  assert_eq(whatwg("http://h/#a b`").fragment, Some("a%20b%60"))
}

///|
/// Reading a URL leaves the escapes somebody wrote alone: `%7e` and `%2f` are
/// what they are until `normalize` says otherwise (RFC 3986 §6.2.2).
test "a reader does not rewrite escapes" {
  assert_eq(whatwg("http://h/%7euser%2f").path, "/%7euser%2f")
  assert_eq(
    @moonurl.Url::decode("http://h/%7euser").normalize().encode(),
    "http://h/~user",
  )
}

///|
test "a reference resolves against a base in either grammar" {
  let base = @moonurl.Url::decode("http://a/b/c/d;p?q")
  assert_eq(@moonurl.Url::decode("../g", base~).encode(), "http://a/b/g")
  let whatwg_base = whatwg("https://example.test/a/b/c")
  assert_eq(
    @moonurl.Url::decode("../d", syntax=@moonurl.Whatwg, base=whatwg_base).encode(),
    "https://example.test/a/d",
  )
  // A backslash is a solidus in the reference too.
  assert_eq(
    @moonurl.Url::decode("..\\d", syntax=@moonurl.Whatwg, base=whatwg_base).encode(),
    "https://example.test/a/d",
  )
}

///|
test "the setters change one component and leave the rest" {
  let url = whatwg("http://user:pw@example.test:8080/a?q=1#f")
  assert_eq(
    url.set_scheme("https").encode(),
    "https://user:pw@example.test:8080/a?q=1#f",
  )
  assert_eq(
    url.set_username("me").encode(),
    "http://me:pw@example.test:8080/a?q=1#f",
  )
  assert_eq(
    url.set_password("").encode(),
    "http://user@example.test:8080/a?q=1#f",
  )
  assert_eq(
    url.set_host("other.test:9090").encode(),
    "http://user:pw@other.test:9090/a?q=1#f",
  )
  // The host setter takes the port with it; the hostname setter does not.
  assert_eq(
    url.set_host("other.test").encode(),
    "http://user:pw@other.test:8080/a?q=1#f",
  )
  assert_eq(
    url.set_hostname("other.test").encode(),
    "http://user:pw@other.test:8080/a?q=1#f",
  )
  assert_eq(url.set_port("").encode(), "http://user:pw@example.test/a?q=1#f")
  assert_eq(
    url.set_path("/b/c").encode(),
    "http://user:pw@example.test:8080/b/c?q=1#f",
  )
  assert_eq(
    url.set_query("z=2").encode(),
    "http://user:pw@example.test:8080/a?z=2#f",
  )
  assert_eq(
    url.set_query("?z=2").encode(),
    "http://user:pw@example.test:8080/a?z=2#f",
  )
  assert_eq(
    url.set_fragment("").encode(),
    "http://user:pw@example.test:8080/a?q=1",
  )
}

///|
/// A setter that cannot read its value leaves the URL as it was — except for
/// the part it had already read, which is what the standard does too.
test "a setter with a value that is not one changes nothing" {
  let url = whatwg("http://example.test/a")
  assert_eq(url.set_port("eighty").encode(), "http://example.test/a")
  // A special scheme has to have a host, so an empty one is not a value.
  assert_eq(url.set_host("").encode(), "http://example.test/a")
  assert_eq(url.set_path("/b").set_path("/c").encode(), "http://example.test/c")
}

///|
test "an origin is a scheme, a host and a port" {
  assert_eq(whatwg("http://example.test/a").origin(), "http://example.test")
  assert_eq(
    whatwg("http://example.test:8080/a").origin(),
    "http://example.test:8080",
  )
  assert_eq(whatwg("https://[2001:db8::1]/").origin(), "https://[2001:db8::1]")
  assert_eq(whatwg("file:///tmp/x").origin(), "null")
  assert_eq(whatwg("data:,x").origin(), "null")
  assert_eq(whatwg("foo://h/").origin(), "null")
  // A blob carries the origin of the URL inside it.
  assert_eq(
    whatwg("blob:https://example.test/1e2f").origin(),
    "https://example.test",
  )
}

///|
test "a query reads as pairs, the way a form body does" {
  let url = whatwg("https://h/?a=1&a=2&b=x+y&empty")
  let params = url.params()
  assert_eq(params.values("a").length(), 2)
  assert_eq(params.get("b").unwrap(), "x y")
  assert_eq(params.get("empty").unwrap(), "")
  // No query at all is no pairs, not a pair with nothing in it.
  assert_true(whatwg("https://h/").params().entries().is_empty())
}

///|
test "what a browser refuses is refused here" {
  for
    text in [
      "http://", "http://exa mple.test/", "http://[::1/", "http://h:99999/", "http://%zz/",
      "1http://h/", "http://h\u{0}/",
    ] {
    let refused = try {
      whatwg(text) |> ignore
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
}
