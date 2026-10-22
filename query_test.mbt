// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The parser cases are web-platform-tests' `url/urlencoded-parser.any.js` and the
// serialiser cases its `url/urlsearchparams-stringifier.any.js`, in their order.

///|
fn decoded(raw : String) -> Array[(String, String)] raise @moonurl.Refused {
  @moonurl.Query::decode(@utf8.encode(raw)[:]).entries()
}

///|
test "the parser cases of web-platform-tests" {
  let cases : Array[(String, Array[(String, String)])] = [
    ("test", [("test", "")]),
    ("\u{FEFF}test=\u{FEFF}", [("\u{FEFF}test", "\u{FEFF}")]),
    ("%EF%BB%BFtest=%EF%BB%BF", [("\u{FEFF}test", "\u{FEFF}")]),
    ("%EF%BF%BF=%EF%BF%BF", [("\u{FFFF}", "\u{FFFF}")]),
    ("%FE%FF", [("\u{FFFD}\u{FFFD}", "")]),
    ("%FF%FE", [("\u{FFFD}\u{FFFD}", "")]),
    ("†&†=x", [("†", ""), ("†", "x")]),
    ("%C2", [("\u{FFFD}", "")]),
    ("%C2x", [("\u{FFFD}x", "")]),
    (
      "_charset_=windows-1252&test=%C2x",
      [("_charset_", "windows-1252"), ("test", "\u{FFFD}x")],
    ),
    ("", []),
    ("a", [("a", "")]),
    ("a=b", [("a", "b")]),
    ("a=", [("a", "")]),
    ("=b", [("", "b")]),
    ("&", []),
    ("&a", [("a", "")]),
    ("a&", [("a", "")]),
    ("a&a", [("a", ""), ("a", "")]),
    ("a&b&c", [("a", ""), ("b", ""), ("c", "")]),
    ("a=b&c=d", [("a", "b"), ("c", "d")]),
    ("a=b&c=d&", [("a", "b"), ("c", "d")]),
    ("&&&a=b&&&&c=d&", [("a", "b"), ("c", "d")]),
    ("a=a&a=b&a=c", [("a", "a"), ("a", "b"), ("a", "c")]),
    ("a==a", [("a", "=a")]),
    ("a=a+b+c+d", [("a", "a b c d")]),
    ("%=a", [("%", "a")]),
    ("%a=a", [("%a", "a")]),
    ("%a_=a", [("%a_", "a")]),
    ("%61=a", [("a", "a")]),
    ("%61+%4d%4D=", [("a MM", "")]),
    ("id=0&value=%", [("id", "0"), ("value", "%")]),
    ("b=%2sf%2a", [("b", "%2sf*")]),
    ("b=%2%2af%2a", [("b", "%2*f*")]),
    ("b=%%2a", [("b", "%*")]),
  ]
  for case in cases {
    assert_eq(decoded(case.0), case.1)
  }
}

///|
fn written(pairs : Array[(String, String)]) -> String {
  @moonurl.Query::new(pairs~).encode()
}

///|
test "the serialiser cases of web-platform-tests" {
  assert_eq(written([("a", "b c")]), "a=b+c")
  assert_eq(written([("a", "b c"), ("a b", "c")]), "a=b+c&a+b=c")
  assert_eq(written([("a", ""), ("a", ""), ("", "b"), ("", "")]), "a=&a=&=b&=")
  assert_eq(written([("", ""), ("", "")]), "=&=")
  assert_eq(written([("a", "b+c"), ("a+b", "c")]), "a=b%2Bc&a%2Bb=c")
  assert_eq(written([("=", "a"), ("b", "=")]), "%3D=a&b=%3D")
  assert_eq(written([("&", "a"), ("b", "&")]), "%26=a&b=%26")
  assert_eq(written([("a", "*-._"), ("*-._", "c")]), "a=*-._&*-._=c")
  assert_eq(written([("a", "b%c"), ("a%b", "c")]), "a=b%25c&a%25b=c")
  assert_eq(written([("a", "b\u{0}c"), ("a\u{0}b", "c")]), "a=b%00c&a%00b=c")
  assert_eq(
    written([("a", "b\u{1F4A9}c"), ("a\u{1F4A9}b", "c")]),
    "a=b%F0%9F%92%A9c&a%F0%9F%92%A9b=c",
  )
  assert_eq(written([("a", "b,c")]), "a=b%2Cc")
  // `~` is unreserved in RFC 3986 but not kept by the form serialiser.
  assert_eq(written([("a", "~")]), "a=%7E")
}

///|
fn round(raw : String) -> String raise @moonurl.Refused {
  @moonurl.Query::decode(@utf8.encode(raw)[:]).encode()
}

///|
test "decoding then encoding, as web-platform-tests checks it" {
  assert_eq(round("id=0&value=%"), "id=0&value=%25")
  assert_eq(round("a=b&c=d&&e&&"), "a=b&c=d&e=")
  assert_eq(round("a = b &a=b&c=d%20"), "a+=+b+&a=b&c=d+")
  assert_eq(round("a=&a=b"), "a=&a=b")
  assert_eq(round("b=%2sf%2a"), "b=%252sf*")
  assert_eq(round("b=%2%2af%2a"), "b=%252*f*")
  assert_eq(round("b=%%2a"), "b=%25*")
}

///|
test "encoding then decoding gives back the pairs" {
  let pairs = [
    ("name", "Ada Lovelace"),
    ("who", "骇兔"),
    ("a&b", "=&?+%"),
    ("", ""),
  ]
  let q = @moonurl.Query::new(pairs~)
  assert_eq(decoded(q.encode()), pairs)
}

///|
/// What a browser posts a plain form as, and a repeated name, which is a list.
test "reading a form" {
  let form = @moonurl.Query::decode(b"name=Ada&born=1815&tag=a&tag=b"[:])
  assert_eq(form.get("name"), Some("Ada"))
  assert_eq(form.get("absent"), None)
  assert_eq(form.values("tag"), ["a", "b"])
  assert_eq(form.values("none"), [])
  assert_true(form.has("born"))
  assert_false(form.has("absent"))
  let coded = @moonurl.Query::decode(
    b"a%26b=%3D%26%3F&who=%E9%AA%87%E5%85%94"[:],
  )
  assert_eq(coded.get("a&b"), Some("=&?"))
  assert_eq(coded.get("who"), Some("骇兔"))
}

///|
test "add, set and remove" {
  let q = @moonurl.Query::new()
  q.add("a", "1")
  q.add("b", "2")
  q.add("a", "3")
  assert_eq(q.encode(), "a=1&b=2&a=3")
  // `set` keeps the first one's place and drops the rest.
  q.set("a", "4")
  assert_eq(q.encode(), "a=4&b=2")
  q.set("c", "5")
  assert_eq(q.encode(), "a=4&b=2&c=5")
  q.remove("b")
  assert_eq(q.encode(), "a=4&c=5")
  q.remove("absent")
  assert_eq(q.entries(), [("a", "4"), ("c", "5")])
}

///|
test "a query owns its pairs" {
  let pairs = [("a", "1")]
  let q = @moonurl.Query::new(pairs~)
  pairs.push(("b", "2"))
  q.entries().push(("c", "3"))
  assert_eq(q.entries(), [("a", "1")])
  assert_eq(q, @moonurl.Query::new(pairs=[("a", "1")]))
}

///|
test "limits refuse the whole input" {
  let small = @moonurl.Limits::new(pairs=2, size=4)
  try @moonurl.Query::decode(b"a=1&b=2&c=3"[:], limits=small) |> ignore catch {
    e => assert_eq(e, @moonurl.Pairs(limit=2))
  } noraise {
    _ => fail("three pairs passed a limit of two")
  }
  try @moonurl.Query::decode(b"a=abcdefgh"[:], limits=small) |> ignore catch {
    e => assert_eq(e, @moonurl.Pair(limit=4, got=10))
  } noraise {
    _ => fail("a ten-octet pair passed a limit of four")
  }
  // At the bounds exactly, and with separators that make no pair.
  assert_eq(
    @moonurl.Query::decode(b"a=12&&b=34&"[:], limits=small).entries().length(),
    2,
  )
}

///|
test "three ways to write the limits are one value" {
  let preset = @moonurl.limits
  assert_eq(preset, @moonurl.Limits::new())
  assert_eq(preset.pairs, 1000)
  assert_eq(preset.size, 1 << 20)
  let named = @moonurl.Limits::new(pairs=8)
  let updated : @moonurl.Limits = { ..@moonurl.limits, pairs: 8, }
  assert_eq(named, updated)
}
