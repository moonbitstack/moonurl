<p align="right">
  <a href="https://moonbitstack.github.io/moonurl/">home</a> &nbsp;·&nbsp;
  <a href="https://moonbitstack.github.io/moonurl/#guide">guide</a> &nbsp;·&nbsp;
  <a href="https://moonbitstack.github.io/moonurl/#api">api</a> &nbsp;·&nbsp;
  <a href="https://mooncakes.io/docs/moonbitstack/moonurl">mooncakes</a>
</p>

# moonurl

URLs for MoonBit, read the way a browser reads them and the way RFC 3986 says
to read them: one type, two grammars. Host names are internationalised, so
`münchen.example` and `xn--mnchen-3ya.example` are the same host. URI templates
fill in and read back. Form bodies and data URLs ride on the same percent
coding. No sockets.

```moonbit
// A string a browser and a generic parser disagree about.
let generic = @moonurl.Url::decode("HTTP://EXAMPLE.test:80/a/../b")
assert_eq(generic.encode(), "HTTP://EXAMPLE.test:80/a/../b")

let browser = @moonurl.Url::decode("HTTP://EXAMPLE.test:80/a/../b", syntax=@moonurl.Whatwg)
assert_eq(browser.encode(), "http://example.test/b")

// Host names, in and out of ASCII.
assert_eq(@moonurl.domain("MÜNCHEN.example"), "xn--mnchen-3ya.example")
let numeric = @moonurl.Url::decode("http://192.0x00A80001/", syntax=@moonurl.Whatwg)
assert_eq(numeric.host, Some("192.168.0.1"))
```

`moon run src/examples/tour` takes a reference apart, resolves the RFC 3986
§5.4 examples, escapes one string for four components and builds a query.
`moon run src/examples/whatwg` reads eight strings both ways, resolves five
references against a base, converts four host names and sets five components.
`moon run src/examples/uritemplate` fills in templates at every level and reads
a URI back. `moon run src/examples/data` reads the four examples RFC 2397
prints.

## Packages

| Package | What | Specification |
|:--|:--|:--|
| `moonurl` | `Url`: parsing, recomposing, resolving, normalising, origins, setters | RFC 3986, WHATWG URL Standard |
| `moonurl` | Percent coding by component, `Kind` | RFC 3986 §2 |
| `moonurl` | `Query`: the pairs of a query or a form body | WHATWG URL Standard §5 |
| `moonurl` | `domain`: a host name in ASCII | UTS 46 |
| `moonurl/idna` | Punycode, and the mapping and validity rules behind it | RFC 3492, UTS 46 |
| `moonurl/template` | URI templates: parse, expand, capture | RFC 6570 |
| `moonurl/dataurl` | A whole representation written inside the reference to it | RFC 2397 |

## Two grammars, one type

RFC 3986 describes a reference as five components and says nothing about what a
scheme means. A browser has to know: `http` has a port and `file` does not,
`\` is a solidus, a host may be a number in any of its spellings. Both readings
produce the same `Url`, so a program that has to accept what people type can
switch grammar for one string and keep working with the result.

```moonbit
let url = @moonurl.Url::decode("https://leo:pw@example.test:8443/a/b?x=1#top")
assert_eq(url.scheme, Some("https"))
assert_eq(url.host, Some("example.test"))
assert_eq(url.port, Some(8443))
assert_eq(url.query, Some("x=1"))
assert_eq(url.origin(), "https://example.test:8443")
```

`syntax` picks the grammar, and `rfc3986` is what it defaults to, so nothing
written against the earlier version of this package changes. `base` resolves a
reference in either grammar.

The WHATWG reading adds what a browser needs and RFC 3986 deliberately leaves
out: the special schemes and their default ports (`http://h:80/` loses the
port), paths normalised on the way in, hosts as names, as IPv4 in decimal,
octal or hexadecimal, as IPv6, or as an opaque string under a scheme of your
own. `Url::origin` answers which URLs are the same site; the nine setters —
`set_scheme`, `set_username`, `set_password`, `set_host`, `set_hostname`,
`set_port`, `set_path`, `set_query`, `set_fragment` — change one component and
leave the rest where it was, tools and all.

## Internationalised host names

A host name is a sequence of labels, and a label may be any word in any script.
`moonurl/idna` maps a name to its ASCII form and back: the mapping table, NFC,
the hyphen rules, the joiner rules of ContextJ, the bidi rule of RFC 5893 and
the DNS lengths. `to_ascii` and `to_unicode` return the name the standard
converts *and* what it objected to, because a browser shows the rest of a name
it cannot finish converting. `moonurl.domain` is the one a URL parser uses: an
ASCII string is taken as it stands, and everything else goes through UTS 46.

```moonbit
let outcome = @idna.to_ascii("münchen.example")
assert_eq(outcome.name, "xn--mnchen-3ya.example")
assert_eq(outcome.is_ok(), true)

// Two settings, for the two callers there are.
assert_eq(@idna.to_ascii("Faß.de").name, "xn--fa-hia.de")
let transitional = { ..@idna.options, transitional: true }
assert_eq(@idna.to_ascii("Faß.de", options=transitional).name, "fass.de")
```

## URI templates

RFC 6570 puts holes in a URI and names them. All four levels are here: the
simple and reserved expansions, the label, path and parameter operators,
prefixes and exploded lists and pairs. `capture` goes the other way, reading a
URI into the names that made it.

```moonbit
let values : Map[String, @template.Value] = Map([])
values.set("list", @template.Value::List(["red", "green"]))
values.set("q", @template.Value::Text("moon bit"))

let list = @template.Template::decode("{/list*}{?q}")
assert_eq(list.expand(values), "/red/green?q=moon%20bit")

let users = @template.Template::decode("/users/{id}{?page}")
let fields : Map[String, @template.Value] = Map([])
fields.set("id", @template.Value::Text("42"))
fields.set("page", @template.Value::Text("2"))
assert_eq(users.expand(fields), "/users/42?page=2")
assert_eq(users.capture("/users/42?page=2"), Some([("id", "42"), ("page", "2")]))
```

`capture` returns nothing when the URI does not match, and gives an exploded
list only its first value: `/red/green` says where the list started, not where
it stopped.

Values come from anything that implements `Variables`; a `Map[String, Value]`
already does, and so can a request, a configuration record or a database row.

## Form encoding

`Query` is a URL's query or a form body as ordered pairs, repeated names kept.
`+` is a space there and nowhere else in a URL, and the serialiser keeps only
letters, digits and `*-._`, so `~` goes out as `%7E` although RFC 3986 leaves it
alone.

```moonbit
let form = @moonurl.Query::decode(b"a=1&b=2&a=3")
assert_eq(form.get("a"), Some("1"))
assert_eq(form.values("a"), ["1", "3"])
assert_eq(form.encode(), "a=1&b=2&a=3")
```

`Query::decode` refuses the whole input past its `limits`: a thousand pairs of
up to 1 MiB each by default. Change one with `Limits::new(pairs=100)` or
`{ ..@moonurl.limits, pairs: 100 }`; the two are the same value. A URL's query
is the same thing, read the same way: `url.params()`.

## Data URLs

A data URL carries the representation inside the reference: the media type, then
either the octets escaped or the same octets in base64.

```moonbit
let greeting = @dataurl.Url::decode("data:text/plain,Hi%20there")
assert_eq(greeting.kind, "text/plain")
assert_eq(greeting.data, b"Hi there")
assert_eq(greeting.charset(), "US-ASCII")
assert_eq(greeting.encode(base64=true), "data:text/plain;base64,SGkgdGhlcmU=")
```

## Interface

| Item | Shape | What it does |
|:--|:--|:--|
| `Url::decode(text, syntax?, base?)` | `Url raise Refused` | Read a reference, in either grammar |
| `Url::encode()` | `String` | Write it back |
| `Url::resolve(reference)` | `Url` | Resolve against this base (RFC 3986) |
| `Url::normalize()` | `Url` | Case, escapes and dot segments (§6.2.2) |
| `Url::origin()` | `String` | `scheme://host:port`, or `"null"` |
| `Url::authority()` | `String?` | The authority, brackets restored |
| `Url::is_absolute()` | `Bool` | A scheme and no fragment |
| `Url::params()` | `Query raise Refused` | The query as pairs |
| `Url::set_*` | `Url` | One component changed, the rest kept |
| `Url::new(..)` | `Url` | A reference built piece by piece |
| `domain(text, strict?)` | `String raise Refused` | A host name in ASCII |
| `escape` / `escape_text` | `String` | Percent-encode octets or text |
| `unescape` / `unescape_text` | `Bytes` / `String` | Undo it |
| `escaped(text, kind?)` | `Bool` | Whether every escape is complete |
| `normalize_escapes(text)` | `String` | Upper-case hex, unreserved octets plain |
| `remove_dots(path)` | `String` | The `.` and `..` segments out |
| `Query::decode(bytes, limits?)` | `Query raise Refused` | A form body or a query |
| `Query::encode()` | `String` | The same body written back |
| `idna::to_ascii` / `to_unicode` | `Outcome` | A name in ASCII, or in Unicode |
| `idna::encode` / `decode` | `String raise Refused` | One label of Punycode |
| `Template::decode(text)` | `Template raise Refused` | Read a template |
| `Template::expand(values)` | `String raise Refused` | Fill it in |
| `Template::capture(uri)` | `Array[(String, String)]?` | Read a URI back into names |
| `dataurl::Url::decode(text)` | `Url raise Refused` | A data URL |

Errors are one enum per package — `Refused` — with an offset named `at`, or the
variable's name where a prefix is one a list or a map cannot take.

## Conformance

The result is what the standards' own vectors ask for: every row of RFC 6570's
own test corpus, every row of the URL Standard's parsing, setter and host-name
data, and the UTS 46 conformance rows.

<!-- conformance:start -->
| Vector | Rows |
|:--|--:|
| RFC 6570 `uritemplate-test` | 270 |
| `urltestdata.json` | 896 |
| `setters_tests.json` | 278 |
| `toascii.json` | 87 |
| `IdnaTestV2.txt` | 6389 |
<!-- conformance:end -->

## Limits

`Query::decode` bounds a form body; `Url` and `Template` do not bound their
input, since a caller that has read the bytes usually knows how long they are
allowed to be. Neither does the IDNA conversion, which the DNS limits can cut
short (`strict` turns them on).

## Licence

Apache-2.0. See [LICENSE](LICENSE).
