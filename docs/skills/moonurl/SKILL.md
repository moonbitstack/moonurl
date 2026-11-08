---
name: moonurl
description: "URLs for MoonBit: read a reference the way a browser does or the way RFC 3986 does, resolve relative references, turn host names into ASCII, fill in RFC 6570 templates, and read or write form bodies and data URLs. Use when code has to accept a URL a person typed, compare two URLs for origin, build a query, or decode a form post."
---

# moonurl

Add the package and import what you need:

```moonbit
import {
  "moonbitstack/moonurl",
  "moonbitstack/moonurl/idna",
  "moonbitstack/moonurl/template",
  "moonbitstack/moonurl/dataurl",
}
```

The root package holds `Url`, percent coding and `Query`. The other three are
imported separately because most programs want one of them.

## Read a URL and take it apart

`Url::decode` reads a reference into seven components. The default grammar is
RFC 3986, which keeps case and dot segments as they came; `syntax=` switches to
the WHATWG reading a browser uses, which normalises on the way in.

```moonbit
let typed = @moonurl.Url::decode("HTTP://EXAMPLE.test:80/a/../b")
assert_eq(typed.encode(), "HTTP://EXAMPLE.test:80/a/../b")
assert_eq(typed.scheme, Some("HTTP"))
assert_eq(typed.normalize().encode(), "http://example.test:80/b")

let browser = @moonurl.Url::decode("HTTP://EXAMPLE.test:80/a/../b", syntax=@moonurl.Whatwg)
assert_eq(browser.encode(), "http://example.test/b")
assert_eq(browser.port, None)
```

Resolve a relative reference against a base with `resolve`; `origin` tells you
which URLs share a site.

```moonbit
let base = @moonurl.Url::decode("http://example.test/a/b/c")
assert_eq(base.resolve(@moonurl.Url::decode("../d")).encode(), "http://example.test/a/d")
let site = @moonurl.Url::decode("https://example.test:8443/a")
assert_eq(site.origin(), "https://example.test:8443")
```

## Host names in any script

`@moonurl.domain` is what the URL parser uses: an ASCII name is taken as it
stands, anything else goes through UTS 46 and comes back as ASCII.

```moonbit
assert_eq(@moonurl.domain("MÜNCHEN.example"), "xn--mnchen-3ya.example")
```

Reach for `@idna` directly when you need to know what the standard objected to,
or when you want the transitional mapping that turns `ß` into `ss`.

```moonbit
let outcome = @idna.to_ascii("münchen.example")
assert_eq(outcome.name, "xn--mnchen-3ya.example")
assert_eq(outcome.is_ok(), true)

let transitional = { ..@idna.options, transitional: true }
assert_eq(@idna.to_ascii("Faß.de", options=transitional).name, "fass.de")
assert_eq(@idna.to_ascii("Faß.de").name, "xn--fa-hia.de")
```

## Fill in a template, read one back

`Template::expand` takes any `Variables`; a `Map[String, Value]` already is one.

```moonbit
let holes : Map[String, @template.Value] = Map([])
holes.set("list", @template.Value::List(["red", "green"]))
holes.set("q", @template.Value::Text("moon bit"))

let path = @template.Template::decode("{/list*}{?q}")
assert_eq(path.expand(holes), "/red/green?q=moon%20bit")
assert_eq(path.capture("/red/green?q=moon%20bit"), Some([("list", "red"), ("q", "moon bit")]))
```

## Read and write a form body

A URL's query and an `application/x-www-form-urlencoded` body are the same
ordered pairs. Order and repeated names survive; `+` is a space here and nowhere
else in a URL.

```moonbit
let form = @moonurl.Query::decode(b"a=1&b=2&a=3")
assert_eq(form.get("a"), Some("1"))
assert_eq(form.values("a"), ["1", "3"])
assert_eq(form.encode(), "a=1&b=2&a=3")

let edited = @moonurl.Query::new(pairs=[("q", "two words")])
assert_eq(edited.encode(), "q=two+words")
```

## Rules that catch people out

- `syntax` defaults to `@moonurl.Rfc3986`. A string a person typed usually wants
  `@moonurl.Whatwg`: backslashes, default ports and numeric hosts only make sense
  there.
- `Query::decode` takes bytes, not text: `b"a=1"`. Past `limits` — a thousand
  pairs of up to 1 MiB each — it refuses the whole input instead of truncating.
- The serialiser keeps only letters, digits and `*-._`. `~` goes out as `%7E`
  even though RFC 3986 leaves it alone, because the form rules are stricter than
  the reference rules.
- `capture` returns `None` when the URI does not match the template. An exploded
  list binds its first value only.
- `dataurl` defines its own `Url` with `kind` and `data`; it is not the root
  `Url`, and its encoder has its own `base64` switch.
