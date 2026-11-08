// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The filled template and the URI read back, as the README prints them — and
// the shape of an exploded list, which comes back as its first value only.

///|
test "the templates the README fills" {
  let values : Map[String, @template.Value] = Map([])
  values.set("list", @template.Value::List(["red", "green"]))
  values.set("q", @template.Value::Text("moon bit"))
  let list = @template.Template::decode("{/list*}{?q}")
  assert_eq(list.expand(values), "/red/green?q=moon%20bit")
  assert_eq(
    list.capture("/red/green?q=moon%20bit"),
    Some([("list", "red"), ("q", "moon bit")]),
  )
  let users = @template.Template::decode("/users/{id}{?page}")
  let fields : Map[String, @template.Value] = Map([])
  fields.set("id", @template.Value::Text("42"))
  fields.set("page", @template.Value::Text("2"))
  assert_eq(users.expand(fields), "/users/42?page=2")
  assert_eq(
    users.capture("/users/42?page=2"),
    Some([("id", "42"), ("page", "2")]),
  )
  assert_eq(users.capture("/other/42?page=2"), None)
}
