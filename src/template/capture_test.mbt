// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// `capture` is the other direction of `expand`: a URI that a template made
// reads back into the names that made it. These walk every operator, because a
// matcher that only knows `?` is the usual kind of broken.

///|
fn one_value(name : String, text : String) -> Map[String, @template.Value] {
  let values : Map[String, @template.Value] = Map([])
  values.set(name, @template.Value::Text(text))
  values
}

///|
fn round_trip(
  template : String,
  name : String,
  text : String,
) -> Array[(String, String)]? raise {
  let t = @template.Template::decode(template[:])
  t.capture(t.expand(one_value(name, text)))
}

///|
/// A single value under every operator reads back as itself.
test "every operator reads a single value back" {
  for
    (template, text) in [
      ("{v}", "value"),
      ("{+v}", "/a/b?c"),
      ("{#v}", "top"),
      ("{.v}", "value"),
      ("{/v}", "value"),
      ("{;v}", "value"),
      ("{?v}", "value"),
      ("{&v}", "value"),
    ] {
    assert_eq(round_trip(template, "v", text), Some([("v", text)]))
  }
}

///|
/// An empty value: a parameter writes no `=`, a query writes one, and both
/// read back as the empty string rather than as the name itself.
test "an empty value reads back as an empty value" {
  assert_eq(round_trip("{;v}", "v", ""), Some([("v", "")]))
  assert_eq(round_trip("{?v}", "v", ""), Some([("v", "")]))
  assert_eq(round_trip("{&v}", "v", ""), Some([("v", "")]))
}

///|
/// A prefix is lossy by construction: the URI keeps the first characters and
/// there is no way to know what followed.
test "a prefix reads back the part the URI kept" {
  assert_eq(round_trip("{v:3}", "v", "abcdef"), Some([("v", "abc")]))
}

///|
/// Two names under one operator keep their order.
test "two names under one operator" {
  let values : Map[String, @template.Value] = Map([])
  values.set("a", @template.Value::Text("1"))
  values.set("b", @template.Value::Text("2"))
  let t = @template.Template::decode("{?a,b}")
  assert_eq(t.capture(t.expand(values)), Some([("a", "1"), ("b", "2")]))
}

///|
/// A URI the template could not have made is not captured.
test "a URI the template did not make is nothing" {
  let t = @template.Template::decode("/users/{id}")
  assert_true(t.capture("/groups/42") is None)
}
