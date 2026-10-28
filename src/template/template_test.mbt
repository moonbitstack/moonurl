// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// RFC 6570 prints its own example set: one table of variables, and every level
// of expansion against it (§3.2). All of them are here, in the section's
// order, because a template engine that passes the simple cases and drops the
// exploded ones is the usual kind of broken.

///|
fn variables() -> Map[String, @template.Value] {
  let values : Map[String, @template.Value] = Map([])
  values.set("count", @template.Value::List(["one", "two", "three"]))
  values.set("dom", @template.Value::List(["example", "com"]))
  values.set("dub", @template.Value::Text("me/too"))
  values.set("hello", @template.Value::Text("Hello World!"))
  values.set("half", @template.Value::Text("50%"))
  values.set("var", @template.Value::Text("value"))
  values.set("who", @template.Value::Text("fred"))
  values.set("base", @template.Value::Text("http://example.com/home/"))
  values.set("path", @template.Value::Text("/foo/bar"))
  values.set("list", @template.Value::List(["red", "green", "blue"]))
  values.set(
    "keys",
    @template.Value::Pairs([("semi", ";"), ("dot", "."), ("comma", ",")]),
  )
  values.set("v", @template.Value::Text("6"))
  values.set("x", @template.Value::Text("1024"))
  values.set("y", @template.Value::Text("768"))
  values.set("empty", @template.Value::Text(""))
  values.set("empty_keys", @template.Value::Pairs([]))
  values
}

///|
fn expand(template : String) -> String raise {
  @template.Template::decode(template[:]).expand(variables())
}

///|
/// Level 1: a name on its own (§3.2.1).
test "RFC 6570 level 1" {
  assert_eq(expand("{var}"), "value")
  assert_eq(expand("{hello}"), "Hello%20World%21")
}

///|
/// Level 2: the two operators that keep the reserved characters (§3.2.2).
test "RFC 6570 level 2" {
  assert_eq(expand("{+var}"), "value")
  assert_eq(expand("{+hello}"), "Hello%20World!")
  assert_eq(expand("{+path}/here"), "/foo/bar/here")
  assert_eq(expand("here?ref={+path}"), "here?ref=/foo/bar")
  assert_eq(expand("X{#var}"), "X#value")
  assert_eq(expand("X{#hello}"), "X#Hello%20World!")
}

///|
/// Level 3: the operators that build a path, a query or a set of parameters
/// (§3.2.3).
test "RFC 6570 level 3" {
  assert_eq(expand("map?{x,y}"), "map?1024,768")
  assert_eq(expand("{x,hello,y}"), "1024,Hello%20World%21,768")
  assert_eq(expand("{+x,hello,y}"), "1024,Hello%20World!,768")
  assert_eq(expand("{+path,x}/here"), "/foo/bar,1024/here")
  assert_eq(expand("{#x,hello,y}"), "#1024,Hello%20World!,768")
  assert_eq(expand("{#path,x}/here"), "#/foo/bar,1024/here")
  assert_eq(expand("X{.var}"), "X.value")
  assert_eq(expand("X{.x,y}"), "X.1024.768")
  assert_eq(expand("{/var}"), "/value")
  assert_eq(expand("{/var,x}/here"), "/value/1024/here")
  assert_eq(expand("{;x,y}"), ";x=1024;y=768")
  assert_eq(expand("{;x,y,empty}"), ";x=1024;y=768;empty")
  assert_eq(expand("{?x,y}"), "?x=1024&y=768")
  assert_eq(expand("{?x,y,empty}"), "?x=1024&y=768&empty=")
  assert_eq(expand("{&x,y,empty}"), "&x=1024&y=768&empty=")
}

///|
/// Level 4: prefixes and exploded lists and pairs (§3.2.4).
test "RFC 6570 level 4" {
  assert_eq(expand("{var:3}"), "val")
  assert_eq(expand("{var:30}"), "value")
  assert_eq(expand("{list}"), "red,green,blue")
  assert_eq(expand("{list*}"), "red,green,blue")
  assert_eq(expand("{keys}"), "semi,%3B,dot,.,comma,%2C")
  assert_eq(expand("{keys*}"), "semi=%3B,dot=.,comma=%2C")
  assert_eq(expand("{+path:6}/here"), "/foo/b/here")
  assert_eq(expand("{+list}"), "red,green,blue")
  assert_eq(expand("{+list*}"), "red,green,blue")
  assert_eq(expand("{+keys}"), "semi,;,dot,.,comma,,")
  assert_eq(expand("{+keys*}"), "semi=;,dot=.,comma=,")
  assert_eq(expand("{#path:6}/here"), "#/foo/b/here")
  assert_eq(expand("{#list}"), "#red,green,blue")
  assert_eq(expand("{#list*}"), "#red,green,blue")
  assert_eq(expand("{#keys}"), "#semi,;,dot,.,comma,,")
  assert_eq(expand("{#keys*}"), "#semi=;,dot=.,comma=,")
  assert_eq(expand("X{.var:3}"), "X.val")
  assert_eq(expand("X{.list}"), "X.red,green,blue")
  assert_eq(expand("X{.list*}"), "X.red.green.blue")
  assert_eq(expand("X{.keys}"), "X.semi,%3B,dot,.,comma,%2C")
  assert_eq(expand("X{.keys*}"), "X.semi=%3B.dot=..comma=%2C")
  assert_eq(expand("{/var:1,var}"), "/v/value")
  assert_eq(expand("{/list}"), "/red,green,blue")
  assert_eq(expand("{/list*}"), "/red/green/blue")
  assert_eq(expand("{/list*,path:4}"), "/red/green/blue/%2Ffoo")
  assert_eq(expand("{/keys}"), "/semi,%3B,dot,.,comma,%2C")
  assert_eq(expand("{/keys*}"), "/semi=%3B/dot=./comma=%2C")
  assert_eq(expand("{;hello:5}"), ";hello=Hello")
  assert_eq(expand("{;list}"), ";list=red,green,blue")
  assert_eq(expand("{;list*}"), ";list=red;list=green;list=blue")
  assert_eq(expand("{;keys}"), ";keys=semi,%3B,dot,.,comma,%2C")
  assert_eq(expand("{;keys*}"), ";semi=%3B;dot=.;comma=%2C")
  assert_eq(expand("{?var:3}"), "?var=val")
  assert_eq(expand("{?list}"), "?list=red,green,blue")
  assert_eq(expand("{?list*}"), "?list=red&list=green&list=blue")
  assert_eq(expand("{?keys}"), "?keys=semi,%3B,dot,.,comma,%2C")
  assert_eq(expand("{?keys*}"), "?semi=%3B&dot=.&comma=%2C")
  assert_eq(expand("{&var:3}"), "&var=val")
  assert_eq(expand("{&list}"), "&list=red,green,blue")
  assert_eq(expand("{&list*}"), "&list=red&list=green&list=blue")
  assert_eq(expand("{&keys}"), "&keys=semi,%3B,dot,.,comma,%2C")
  assert_eq(expand("{&keys*}"), "&semi=%3B&dot=.&comma=%2C")
}

///|
test "a value that is not there leaves nothing behind" {
  assert_eq(expand("{undef}"), "")
  assert_eq(expand("X{.undef}"), "X")
  assert_eq(expand("{?a,undef,b}"), "")
  assert_eq(expand("{?undef,var}"), "?var=value")
  assert_eq(expand("{undef,undef}"), "")
}

///|
/// A template is read back the way it was written, operators, modifiers and
/// all (§2).
test "a template reads back as itself" {
  for
    text in [
      "http://example.com/home/", "{var}", "{+path}/here", "{#x,hello,y}", "X{.list*}",
      "{/list*,path:4}", "{;keys*}", "{?a,b,c}", "{&x,y,empty}", "{var:3}", "{a.b_c}",
      "{a%20b}",
    ] {
    assert_eq(@template.Template::decode(text[:]).encode(), text)
  }
}

///|
test "what is not a template is refused" {
  for
    text in [
      "{", "{a", "a}", "{=a}", "{,a}", "{!a}", "{@a}", "{|a}", "{a b}", "{a:}", "{a:10000}",
      "{a:", "{a**}", "{a:2*}", "a b", "a{b",
    ] {
    let refused = try {
      @template.Template::decode(text[:]) |> ignore
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
}

///|
/// A URI read back into the variables that made it.
test "a URI is taken apart by the template that made it" {
  let template = @template.Template::decode("/users/{id}/posts{?page,size}")
  let bindings = template.capture("/users/42/posts?page=2&size=10").unwrap()
  assert_eq(bindings.length(), 3)
  assert_eq(bindings[0], ("id", "42"))
  assert_eq(bindings[1], ("page", "2"))
  assert_eq(bindings[2], ("size", "10"))
  // The template does not describe this URI, so nothing is bound.
  assert_true(template.capture("/groups/42/posts?page=2&size=10") is None)
}

///|
test "capture undoes the escapes it reads" {
  let template = @template.Template::decode("{+path}")
  let bindings = template.capture("/a%20b/c").unwrap()
  assert_eq(bindings[0], ("path", "/a b/c"))
}

///|
/// A variable with a path in it, exploded, comes back as the pieces that made
/// it — the engine cannot tell a separator inside a value from one between
/// two values, and says so.
test "an exploded list comes back item by item" {
  let values : Map[String, @template.Value] = Map([])
  values.set("list", @template.Value::List(["red", "green"]))
  let template = @template.Template::decode("{/list*}")
  let uri = template.expand(values)
  assert_eq(uri, "/red/green")
  let bindings = template.capture(uri[:]).unwrap()
  assert_eq(bindings.length(), 1)
  assert_eq(bindings[0], ("list", "red"))
}
