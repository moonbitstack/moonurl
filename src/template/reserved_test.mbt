// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// RFC 6570 §3.2.2 against §3.2.1: the two modes differ on exactly one class of
// characters, the reserved set of RFC 3986 §2.2, and getting that class wrong
// is invisible until a value carries one. These pin the whole set.

///|
fn text_values(text : String) -> Map[String, @template.Value] {
  let values : Map[String, @template.Value] = Map([])
  values.set("v", @template.Value::Text(text))
  values
}

///|
fn expand_one(template : String, text : String) -> String raise {
  @template.Template::decode(template[:]).expand(text_values(text))
}

///|
/// The gen-delims and sub-delims of RFC 3986 §2.2, in the order they are
/// written in the grammar.
let reserved_set : String = ":/?#[]@!$&'()*+,;="

///|
/// The same characters, each percent-encoded.
let reserved_escaped : String = "%3A%2F%3F%23%5B%5D%40%21%24%26%27%28%29%2A%2B%2C%3B%3D"

///|
/// A simple expansion escapes every reserved character (§3.2.1).
test "a simple expansion escapes every reserved character" {
  assert_eq(expand_one("{v}", reserved_set), reserved_escaped)
}

///|
/// A reserved expansion keeps every one of them (§3.2.2).
test "a reserved expansion keeps every reserved character" {
  assert_eq(expand_one("{+v}", reserved_set), reserved_set)
}

///|
/// A fragment expansion keeps them too, and opens with one `#`.
test "a fragment expansion keeps reserved characters" {
  assert_eq(expand_one("{#v}", reserved_set), "#" + reserved_set)
}

///|
/// The operators that introduce a separator escape the value the way a simple
/// expansion does, and put their own separator in front of it (§3.2.3).
test "the separating operators escape reserved characters in the value" {
  assert_eq(expand_one("{.v}", reserved_set), "." + reserved_escaped)
  assert_eq(expand_one("{/v}", reserved_set), "/" + reserved_escaped)
  assert_eq(expand_one("{;v}", reserved_set), ";v=" + reserved_escaped)
  assert_eq(expand_one("{?v}", reserved_set), "?v=" + reserved_escaped)
  assert_eq(expand_one("{&v}", reserved_set), "&v=" + reserved_escaped)
}

///|
/// An unreserved character is never escaped, in either mode (§2.3).
test "an unreserved character is never escaped" {
  let unreserved = "AZaz09-._~"
  assert_eq(expand_one("{v}", unreserved), unreserved)
  assert_eq(expand_one("{+v}", unreserved), unreserved)
}

///|
/// A prefix takes the first characters before it encodes, so it cuts a reserved
/// character in the value the same way it cuts any other (§3.2.4).
test "a prefix cuts before it encodes" {
  assert_eq(expand_one("{v:3}", "a/b?c"), "a%2Fb")
  assert_eq(expand_one("{+v:3}", "a/b?c"), "a/b")
}

///|
/// A reserved expansion still escapes what is neither reserved nor unreserved:
/// a space, and a character outside ASCII as UTF-8.
test "a reserved expansion escapes the rest" {
  assert_eq(expand_one("{+v}", "a b"), "a%20b")
  assert_eq(expand_one("{+v}", "中"), "%E4%B8%AD")
}
