// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Two mature implementations answer some of these questions differently, and
// the vectors beside this file leave those questions out so that a difference
// in model does not read as a failure. This file asks them, and states which
// answer is taken and why: a deviation that is written down is a decision, one
// that is only absent from the corpus is an omission.

///|
/// RFC 3986 §5.4.2 resolves `http:g` against an `http` base to `http:g`: a
/// reference that names its own scheme is not relative, however much it looks
/// it. Python's `urljoin` takes the other reading and answers
/// `http://a/b/c/g`. The section's own example list says `http:g`.
test "a reference with the base's scheme keeps its scheme" {
  let base = @moonurl.Url::decode("http://a/b/c/d;p?q")
  assert_eq(@moonurl.Url::decode("http:g", base~).encode(), "http:g")
  assert_eq(base.resolve(@moonurl.Url::decode("http:g")).encode(), "http:g")
  // A scheme that differs is a different reference entirely, in both readings.
  assert_eq(base.resolve(@moonurl.Url::decode("g:h")).encode(), "g:h")
}

///|
/// An empty query and an empty fragment are components that are there and hold
/// nothing, which §5.3 writes as `?` and `#`. Python's `urlsplit` returns the
/// same answer for absent and for empty, so `urljoin` cannot write the
/// delimiter back and answers `http://a/b` for a reference of `?`.
test "an empty component is written back as a delimiter" {
  let base = @moonurl.Url::decode("http://a/b?q=1")
  assert_eq(@moonurl.Url::decode("?", base~).encode(), "http://a/b?")
  assert_eq(@moonurl.Url::decode("#", base~).encode(), "http://a/b?q=1#")
  assert_eq(@moonurl.Url::decode("g?", base~).encode(), "http://a/g?")
  assert_eq(@moonurl.Url::decode("g#", base~).encode(), "http://a/g#")
}

///|
/// §5.2.2 takes the fragment from the reference, so resolving an empty
/// reference drops the base's fragment. Python's `urljoin` returns the base
/// untouched for an empty reference, fragment and all; Go's
/// `ResolveReference` does what the section says, and so does this.
test "an empty reference does not inherit the base's fragment" {
  let base = @moonurl.Url::decode("http://a/b?q=1#f")
  assert_eq(@moonurl.Url::decode("", base~).encode(), "http://a/b?q=1")
  // Everything else about the base is inherited, which is the point of the
  // empty reference.
  let kept = @moonurl.Url::decode("", base~)
  assert_eq(kept.query, Some("q=1"))
  assert_eq(kept.path, "/b")
}

///|
/// A reference is resolved against any absolute base, whatever its scheme:
/// §5.2.2 merges paths and never asks what the scheme means. Python's
/// `urljoin` only resolves schemes on its own list and returns the reference
/// unchanged for the rest, so its answer for a `urn` base is the reference
/// itself.
test "a reference resolves against a base of any scheme" {
  let object = @moonurl.Url::decode("urn:isbn:0451450523")
  assert_eq(object.resolve(@moonurl.Url::decode("g")).encode(), "urn:g")
  let plain = @moonurl.Url::decode("foo://h/a/b")
  assert_eq(plain.resolve(@moonurl.Url::decode("g")).encode(), "foo://h/a/g")
  assert_eq(plain.resolve(@moonurl.Url::decode("../g")).encode(), "foo://h/g")
}

///|
/// UTS 46 keeps an A-label it cannot decode and lets the mapping decide what
/// the label says; with the STD 3 and length rules off, `xn--a` decodes to
/// U+0080, which is disallowed, so the name is reported with the fault and the
/// name still comes back. A URL host parser is more forgiving than that: an
/// ASCII host is taken as it stands, so `xn--a` addresses something. Node
/// refuses it at both layers, which is the one place in the differential corpus
/// where the two disagree; the URL Standard's own `toascii.json` keeps it.
test "an A-label that does not decode is kept, and reported" {
  let outcome = @idna.to_ascii("xn--a")
  assert_eq(outcome.name, "xn--a")
  assert_eq(outcome.errors, [@idna.Disallowed(at=0, got='\u{80}')])
  // The URL parser takes the name as it stands, as a browser does.
  assert_eq(@moonurl.domain("xn--a"), "xn--a")
  let url = @moonurl.Url::decode("http://xn--a/", syntax=@moonurl.Whatwg)
  assert_eq(url.host, Some("xn--a"))
}
