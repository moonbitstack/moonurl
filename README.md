# moonurl

URI references for MoonBit, as RFC 3986 defines them: taking one apart, putting it back, resolving a relative one against a base, normalising, and percent coding by component. Form encoding and data URLs ride on top. No sockets.

```moonbit
let base = @moonurl.Url::decode("http://a/b/c/d;p?q")
base.resolve(@moonurl.Url::decode("../g")).encode() // "http://a/b/g"
@moonurl.escape_text("a b&c/d", kind=Query)         // "a%20b&c/d"
@moonurl.Query::decode(b"q=two+words&tag=a&tag=b").values("tag") // ["a", "b"]
@dataurl.Url::decode("data:,A%20brief%20note").data // b"A brief note"
```

`moon run examples/tour` takes a reference apart, resolves the RFC 3986 §5.4 examples, escapes one string for four components and builds a query; `moon run examples/data` reads the four examples RFC 2397 prints.

## Packages

|  Package  | What | Specification |
|:--:|:--|:--|
| `moonurl` | URI references: parsing, recomposing, resolving, normalising, percent coding by component | RFC 3986 |
| `moonurl` | `Query`: the pairs of a query or a form body, read and written as `application/x-www-form-urlencoded` | WHATWG URL Standard §5 |
| `moonurl/dataurl` | A whole representation written inside the reference to it | RFC 2397 |

Not here: internationalised host names (RFC 3492), and what belongs to the WHATWG URL Standard rather than to RFC 3986 — special schemes, default ports, Windows drive letters.

## Form encoding

`Query` is a URL's query or a form body as ordered pairs, repeated names kept. `+` is a space there and nowhere else in a URL, and the serialiser keeps only letters, digits and `*-._`, so `~` goes out as `%7E` although RFC 3986 leaves it alone. Both directions pass the parser and serialiser cases of web-platform-tests.

`Query::decode` refuses the whole input past its `limits`: a thousand pairs of up to 1 MiB each by default, which are Starlette's `max_fields` and `max_part_size`. Change one with `Limits::new(pairs=100)` or `{ ..@moonurl.limits, pairs: 100 }`; the two are the same value.

## Licence

Apache-2.0. See [LICENSE](LICENSE).
