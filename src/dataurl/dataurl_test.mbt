// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// RFC 2397 §4 prints four examples. All four are here, and so is the one thing
// §3's grammar says that a reader is likely to get wrong: the comma that splits
// is the first one, and every comma after it is payload.

///|
/// RFC 2397 §4, in order.
test "the examples of RFC 2397 §4" {
  let note = @dataurl.Url::decode("data:,A%20brief%20note")
  assert_eq(note.kind, "text/plain;charset=US-ASCII")
  assert_eq(note.data, @utf8.encode("A brief note"))

  // The second example is deliberately malformed: `%fg` is not an escape. A
  // browser takes it as three characters, and so do we until asked not to.
  let greek = @dataurl.Url::decode(
    "data:text/plain;charset=iso-8859-7,%be%fg%be",
  )
  assert_eq(greek.kind, "text/plain;charset=iso-8859-7")
  assert_eq(greek.charset(), "iso-8859-7")
  assert_eq(greek.data, b"\xBE%fg\xBE")

  // The third is base64, shortened here to three octets.
  let gif = @dataurl.Url::decode("data:image/gif;base64,AAEC")
  assert_eq(gif.kind, "image/gif")
  assert_eq(gif.data, b"\x00\x01\x02")

  // The fourth has commas in the payload.
  let query = @dataurl.Url::decode(
    "data:application/vnd-xxx-query,select_vcount,fcol_from_fieldtable/local",
  )
  assert_eq(query.kind, "application/vnd-xxx-query")
  assert_eq(
    query.data,
    @utf8.encode("select_vcount,fcol_from_fieldtable/local"),
  )
}

///|
/// §2: no media type means `text/plain;charset=US-ASCII`, and parameters alone
/// mean that type wearing them.
test "the media type a data URL means when it names none" {
  assert_eq(@dataurl.kind, "text/plain;charset=US-ASCII")
  assert_eq(@dataurl.Url::decode("data:,x").kind, "text/plain;charset=US-ASCII")
  assert_eq(@dataurl.Url::decode("data:,x").charset(), "US-ASCII")
  assert_eq(
    @dataurl.Url::decode("data:;charset=UTF-8,x").kind,
    "text/plain;charset=UTF-8",
  )
  assert_eq(@dataurl.Url::decode("data:;charset=UTF-8,x").charset(), "UTF-8")
  // A type with no charset parameter still answers the question.
  assert_eq(
    @dataurl.Url::decode("data:image/png;base64,AAEC").charset(),
    "US-ASCII",
  )
}

///|
/// Both spellings write back to something that reads the same.
test "a data URL that is written back reads the same" {
  for
    payload in [
      b"",
      b"hi",
      b"\x00\x01\x02\xFF",
      @utf8.encode("骇兔 rides"),
      b",",
    ] {
    for kind in ["text/plain;charset=US-ASCII", "image/png", "application/json"] {
      let url = @dataurl.Url::new(payload, kind~)
      assert_eq(@dataurl.Url::decode(url.encode()[:]), url)
      assert_eq(@dataurl.Url::decode(url.encode(base64=false)[:]), url)
    }
  }
}

///|
/// The default media type is left out, because reading one back puts it there.
test "what is written out" {
  assert_eq(@dataurl.Url::new(b"hi").encode(), "data:;base64,aGk=")
  assert_eq(@dataurl.Url::new(b"hi").encode(base64=false), "data:,hi")
  assert_eq(
    @dataurl.Url::new(@utf8.encode("A brief note")).encode(base64=false),
    "data:,A%20brief%20note",
  )
  assert_eq(
    @dataurl.Url::new(b"\x00\x01\x02", kind="image/gif").encode(),
    "data:image/gif;base64,AAEC",
  )
  assert_eq(
    @dataurl.Url::new(b"a,b", kind="text/csv").encode(base64=false),
    "data:text/csv,a%2Cb",
  )
}

///|
/// A scheme is case-insensitive (RFC 3986 §3.1), and `;base64` is written both
/// ways by real generators.
test "the scheme and the base64 flag are case-insensitive" {
  assert_eq(@dataurl.Url::decode("DATA:,x").data, b"x")
  assert_eq(
    @dataurl.Url::decode("data:image/gif;BASE64,AAEC").data,
    b"\x00\x01\x02",
  )
  assert_eq(
    @dataurl.Url::decode("Data:image/gif;Base64,AAEC").kind,
    "image/gif",
  )
}

///|
/// Strict turns the two things a browser lets pass into errors.
test "strict rejects what a browser tolerates" {
  // A `%` that is not an escape.
  assert_eq(
    refused("data:text/plain;charset=iso-8859-7,%be%fg%be"),
    Some(@dataurl.Escape(at=3)),
  )
  assert_eq(refused("data:,100%"), Some(@dataurl.Escape(at=3)))
  assert_eq(refused("data:,a%20b"), None)
  // Base64 with whitespace in it, or the wrong amount of padding.
  assert_eq(@dataurl.Url::decode("data:;base64,AA\nEC").data, b"\x00\x01\x02")
  assert_true(refused("data:;base64,AA\nEC") is Some(_))
  assert_eq(refused("data:;base64,AAEC"), None)
  assert_true(refused("data:;base64,AAE") is Some(_))
}

///|
/// Not a data URL at all.
test "a string that is not a data URL" {
  assert_eq(refused("http://example.test/"), Some(@dataurl.Scheme))
  assert_eq(refused(""), Some(@dataurl.Scheme))
  assert_eq(refused("data:text/plain"), Some(@dataurl.Comma))
  assert_eq(refused("data:"), Some(@dataurl.Comma))
  // Nothing after the comma is an empty payload, not a failure.
  assert_eq(@dataurl.Url::decode("data:,").data, b"")
}

///|
/// Base64 that is not base64 names where it stopped.
test "a payload that is not base64" {
  try @dataurl.Url::decode("data:;base64,AA*C") catch {
    @dataurl.Base64(at~) => assert_eq(at, 2)
    _ => fail("the wrong refusal")
  } noraise {
    _ => fail("a bad base64 payload was accepted")
  }
}

///|
fn refused(text : String) -> @dataurl.Refused? {
  try {
    @dataurl.Url::decode(text[:], strict=true) |> ignore
    None
  } catch {
    e => Some(e)
  }
}
