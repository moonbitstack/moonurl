// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A URI template filled in three ways, and a URI read back into the names it
/// was built from.
fn main raise {
  let values : Map[String, @template.Value] = Map([])
  values.set("who", @template.Value::Text("moon bit"))
  values.set("path", @template.Value::Text("/a/b"))
  values.set("list", @template.Value::List(["red", "green", "blue"]))
  values.set("keys", @template.Value::Pairs([("lang", "en"), ("page", "2")]))

  for
    text in [
      "https://example.test/{path}", "{+path}/here", "{/list*}{?who}", "{?keys*}",
      "{;who,keys}",
    ] {
    let template = @template.Template::decode(text[:])
    println(text)
    println("  expanded  " + template.expand(values))
    println("")
  }

  // A template that describes a URI is also the thing that reads one.
  let template = @template.Template::decode("/users/{id}/posts{?page,size}")
  let uri = "/users/42/posts?page=2&size=10"
  println(uri)
  for binding in template.capture(uri[:]).unwrap() {
    println("  \{binding.0} = \{binding.1}")
  }
  println("")

  // Not every string is a template, and the ones that are not say where.
  for text in ["{a", "{a b}", "{a:10000}", "{=a}"] {
    let outcome = @template.Template::decode(text[:]).encode() catch {
      @template.Refused::Bracket(at~) => "not closed, at \{at}"
      @template.Refused::Syntax(at~, got~) =>
        "'\{got}' may not stand there, at \{at}"
      @template.Refused::Operator(at~, got~) => "'\{got}' is reserved, at \{at}"
      @template.Refused::Length(at~, limit~, got~) =>
        "\{got} is past \{limit}, at \{at}"
    }
    println("\{text}  ->  \{outcome}")
  }
}
