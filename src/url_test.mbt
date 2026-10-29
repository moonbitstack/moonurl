// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// RFC 3986 prints its own test set: §5.4 resolves forty-odd references against
// one base and states every answer. Both halves are here, verbatim and in the
// section's order, because a resolver that passes the normal examples and fails
// the abnormal ones is the usual kind of broken.

///|
/// The base of every §5.4 example.
fn base() -> @moonurl.Url raise @moonurl.Refused {
  @moonurl.Url::decode("http://a/b/c/d;p?q")
}

///|
fn resolved(reference : String) -> String raise @moonurl.Refused {
  base().resolve(@moonurl.Url::decode(reference[:])).encode()
}

///|
/// RFC 3986 §5.4.1, in order.
test "the normal examples of RFC 3986 §5.4.1" {
  let cases = [
    ("g:h", "g:h"),
    ("g", "http://a/b/c/g"),
    ("./g", "http://a/b/c/g"),
    ("g/", "http://a/b/c/g/"),
    ("/g", "http://a/g"),
    ("//g", "http://g"),
    ("?y", "http://a/b/c/d;p?y"),
    ("g?y", "http://a/b/c/g?y"),
    ("#s", "http://a/b/c/d;p?q#s"),
    ("g#s", "http://a/b/c/g#s"),
    ("g?y#s", "http://a/b/c/g?y#s"),
    (";x", "http://a/b/c/;x"),
    ("g;x", "http://a/b/c/g;x"),
    ("g;x?y#s", "http://a/b/c/g;x?y#s"),
    ("", "http://a/b/c/d;p?q"),
    (".", "http://a/b/c/"),
    ("./", "http://a/b/c/"),
    ("..", "http://a/b/"),
    ("../", "http://a/b/"),
    ("../g", "http://a/b/g"),
    ("../..", "http://a/"),
    ("../../", "http://a/"),
    ("../../g", "http://a/g"),
  ]
  for one in cases {
    assert_eq(resolved(one.0), one.1)
  }
}

///|
/// RFC 3986 §5.4.2, in order. The last one is the strict reading the section
/// calls for: `http:g` keeps its own scheme rather than borrowing the base's
/// authority.
test "the abnormal examples of RFC 3986 §5.4.2" {
  let cases = [
    ("../../../g", "http://a/g"),
    ("../../../../g", "http://a/g"),
    ("/./g", "http://a/g"),
    ("/../g", "http://a/g"),
    ("g.", "http://a/b/c/g."),
    (".g", "http://a/b/c/.g"),
    ("g..", "http://a/b/c/g.."),
    ("..g", "http://a/b/c/..g"),
    ("./../g", "http://a/b/g"),
    ("./g/.", "http://a/b/c/g/"),
    ("g/./h", "http://a/b/c/g/h"),
    ("g/../h", "http://a/b/c/h"),
    ("g;x=1/./y", "http://a/b/c/g;x=1/y"),
    ("g;x=1/../y", "http://a/b/c/y"),
    ("g?y/./x", "http://a/b/c/g?y/./x"),
    ("g?y/../x", "http://a/b/c/g?y/../x"),
    ("g#s/./x", "http://a/b/c/g#s/./x"),
    ("g#s/../x", "http://a/b/c/g#s/../x"),
    ("http:g", "http:g"),
  ]
  for one in cases {
    assert_eq(resolved(one.0), one.1)
  }
}

///|
/// The five components of §3, and the two that are absent rather than empty.
test "a reference comes apart where RFC 3986 §3 says it does" {
  let url = @moonurl.Url::decode("https://leo:pw@example.test:8443/a/b?x=1#top")
  assert_eq(url.scheme, Some("https"))
  assert_eq(url.userinfo, Some("leo:pw"))
  assert_eq(url.host, Some("example.test"))
  assert_eq(url.port, Some(8443))
  assert_eq(url.path, "/a/b")
  assert_eq(url.query, Some("x=1"))
  assert_eq(url.fragment, Some("top"))
  // An empty query is not a missing one: `?` is in the URL either way.
  assert_eq(@moonurl.Url::decode("http://h/p?").query, Some(""))
  assert_eq(@moonurl.Url::decode("http://h/p").query, None)
  assert_eq(@moonurl.Url::decode("http://h/p#").fragment, Some(""))
  assert_eq(@moonurl.Url::decode("http://h/p").fragment, None)
  // No authority at all is not an empty one.
  assert_eq(@moonurl.Url::decode("mailto:leo@example.test").host, None)
  assert_eq(@moonurl.Url::decode("file:///tmp/x").host, Some(""))
}

///|
/// A colon does not make a scheme: §3.1 wants a letter first, and a colon
/// inside a path is not a delimiter at all.
test "what is and is not a scheme" {
  assert_eq(@moonurl.Url::decode("http://h/p").scheme, Some("http"))
  assert_eq(@moonurl.Url::decode("a+b-c.d:x").scheme, Some("a+b-c.d"))
  assert_eq(@moonurl.Url::decode("2026:a").scheme, None)
  assert_eq(@moonurl.Url::decode("a/b:c").scheme, None)
  assert_eq(@moonurl.Url::decode("/a:b").scheme, None)
  assert_eq(@moonurl.Url::decode("a/b:c").path, "a/b:c")
}

///|
/// The authority, including the two ways it can be malformed.
test "the authority splits at the last at-sign" {
  let url = @moonurl.Url::decode("http://a@b@host/p")
  assert_eq(url.userinfo, Some("a@b"))
  assert_eq(url.host, Some("host"))
  // An IP-literal is held without its brackets and written back with them.
  let six = @moonurl.Url::decode("http://[2001:db8::1]:80/p")
  assert_eq(six.host, Some("2001:db8::1"))
  assert_eq(six.port, Some(80))
  assert_eq(six.encode(), "http://[2001:db8::1]:80/p")
  // An empty port is no port (§3.2.3), not port zero.
  assert_eq(@moonurl.Url::decode("http://h:/p").port, None)
  assert_eq(@moonurl.Url::decode("http://h:0/p").port, Some(0))
}

///|
test "an authority that is not one is refused" {
  assert_eq(refused("http://h:80x/p"), Some(@moonurl.Port(at=11)))
  assert_eq(refused("http://[2001:db8/p"), Some(@moonurl.Host(at=7)))
  assert_eq(refused("http://h:80/p"), None)
}

///|
fn refused(text : String) -> @moonurl.Refused? {
  try {
    @moonurl.Url::decode(text[:]) |> ignore
    None
  } catch {
    e => Some(e)
  }
}

///|
/// Writing a reference back gives the string it was read from (§5.3).
test "a reference that is written back reads the same" {
  for
    text in [
      "http://a/b/c/d;p?q", "https://leo:pw@h:8443/a/b?x=1#top", "mailto:leo@example.test",
      "file:///tmp/x", "//h/p", "/p", "p", "", "?q", "#f", "urn:isbn:0451450523",
      "http://[::1]/p",
    ] {
    assert_eq(@moonurl.Url::decode(text[:]).encode(), text)
  }
}

// -------------------------------------------------------------------- coding

///|
/// The unreserved set is never escaped and everything else is, until the
/// component says otherwise (§2.3, §3).
test "which octets stand for themselves depends on the component" {
  assert_eq(@moonurl.escape_text("aZ09-._~"), "aZ09-._~")
  assert_eq(@moonurl.escape_text("a b"), "a%20b")
  assert_eq(@moonurl.escape_text("a/b"), "a%2Fb")
  assert_eq(@moonurl.escape_text("a/b", kind=Path), "a/b")
  assert_eq(@moonurl.escape_text("a/b", kind=Segment), "a%2Fb")
  assert_eq(@moonurl.escape_text("a b/c", kind=Path), "a%20b/c")
  // A query value is `Bare`, because `&` and `=` inside one must not read as
  // the separators they look like.
  assert_eq(@moonurl.escape_text("a&b=c"), "a%26b%3Dc")
  assert_eq(@moonurl.escape_text("a&b=c", kind=Query), "a&b=c")
  // `Whole` is for a value that is already a URI.
  assert_eq(
    @moonurl.escape_text("http://h/p?x=1#f", kind=Whole),
    "http://h/p?x=1#f",
  )
  assert_eq(@moonurl.escape_text("a b", kind=Whole), "a%20b")
  assert_eq(@moonurl.escape_text("100%", kind=Whole), "100%")
  // `spare` is for percent coding outside a URI: gRPC's `grpc-message` keeps
  // printable ASCII but `%`, which is nobody's component.
  assert_eq(
    @moonurl.escape_text("not found: /a b?c", spare=" !/:?"),
    "not found: /a b?c",
  )
  assert_eq(@moonurl.escape_text("100%", spare=" !/:?"), "100%25")
  assert_true(@moonurl.escaped("not found: /a b?c", spare=" !/:?"))
  assert_false(@moonurl.escaped("not found: /a b?c"))
  // Text goes out as UTF-8 (§2.5).
  assert_eq(@moonurl.escape_text("中"), "%E4%B8%AD")
}

///|
test "decoding tolerates what encoding never writes" {
  assert_eq(@moonurl.unescape(b"a%20b"[:]), b"a b")
  assert_eq(@moonurl.unescape(b"a+b"[:]), b"a+b")
  assert_eq(@moonurl.unescape(b"%E4%B8%AD"[:]), b"\xE4\xB8\xAD")
  assert_eq(@moonurl.unescape(b"100%"[:]), b"100%")
  assert_eq(@moonurl.unescape(b"%"[:]), b"%")
  assert_eq(@moonurl.unescape(b"%zz"[:]), b"%zz")
  assert_eq(@moonurl.unescape(b""[:]), b"")
  assert_eq(@moonurl.unescape_text("a%20b%E4%B8%AD"), "a b中")
  // Lower-case hex reads the same as upper (§6.2.2.1).
  assert_eq(@moonurl.unescape(b"%e4%b8%ad"[:]), b"\xE4\xB8\xAD")
}

///|
/// The check `unescape` deliberately does not make.
test "escaped says what unescape tolerates" {
  assert_true(@moonurl.escaped("a%20b"))
  assert_false(@moonurl.escaped("100%"))
  assert_false(@moonurl.escaped("%zz"))
  assert_false(@moonurl.escaped("a b"))
  assert_true(@moonurl.escaped("a/b", kind=Path))
  assert_false(@moonurl.escaped("a/b"))
}

///|
test "everything written escapes back to itself" {
  for
    text in [
      "hello", "a b", "résumé", "100%", "a/b", "?x=1&y=2", "", "~-._", "骇兔",
    ] {
    let out = @moonurl.escape_text(text[:])
    assert_eq(@moonurl.unescape_text(out[:]), text)
    assert_true(@moonurl.escaped(out[:]))
  }
}

// ------------------------------------------------------------- normalisation

///|
/// RFC 3986 §6.2.2: case in the scheme and host, case in the escapes, escapes
/// of octets that never needed one, and the dot segments.
test "normalising does the three things §6.2.2 lists" {
  assert_eq(@moonurl.normalize_escapes("%7e%2Fa"), "~%2Fa")
  assert_eq(@moonurl.normalize_escapes("%e9%aa%87"), "%E9%AA%87")
  assert_eq(@moonurl.normalize_escapes("100%"), "100%")
  assert_eq(@moonurl.normalize_escapes("例え%7e/𝄞%2f"), "例え~/𝄞%2F")
  assert_eq(
    @moonurl.Url::decode("HTTP://EXAMPLE.例え.JP/%7Ea").normalize().encode(),
    "http://example.例え.jp/~a",
  )
  let url = @moonurl.Url::decode("HTTP://EXAMPLE.test/a/./b/../c/%7euser")
  assert_eq(url.normalize().encode(), "http://example.test/a/c/~user")
  // §6.2.3 is not done here: the port stays, because whether 80 is the default
  // is a fact about `http` and not about the syntax.
  assert_eq(
    @moonurl.Url::decode("http://h:80/").normalize().encode(),
    "http://h:80/",
  )
}

///|
/// §5.2.4 on its own, at the inputs the loop exists for.
test "dot segments come out the way §5.2.4 says" {
  assert_eq(@moonurl.remove_dots("/a/b/c/./../../g"), "/a/g")
  assert_eq(@moonurl.remove_dots("mid/content=5/../6"), "mid/6")
  assert_eq(@moonurl.remove_dots("/a/b/.."), "/a/")
  assert_eq(@moonurl.remove_dots("/a/b/."), "/a/b/")
  assert_eq(@moonurl.remove_dots("/../../g"), "/g")
  assert_eq(@moonurl.remove_dots(".."), "")
  assert_eq(@moonurl.remove_dots("."), "")
  assert_eq(@moonurl.remove_dots(""), "")
  assert_eq(@moonurl.remove_dots("/"), "/")
}

///|
test "a URI is a reference with a scheme and no fragment" {
  assert_true(@moonurl.Url::decode("http://h/p").is_absolute())
  assert_false(@moonurl.Url::decode("http://h/p#f").is_absolute())
  assert_false(@moonurl.Url::decode("/p").is_absolute())
}

///|
/// Built rather than read, since a client assembles one far more often than it
/// takes one apart.
test "a reference can be built a piece at a time" {
  let url = @moonurl.Url::new(
    scheme="https",
    host="example.test",
    port=12000,
    path="/v1/items",
    query="page=2",
  )
  assert_eq(url.encode(), "https://example.test:12000/v1/items?page=2")
  assert_eq(url.authority(), Some("example.test:12000"))
  assert_eq(@moonurl.Url::new(path="a/b").authority(), None)
}
