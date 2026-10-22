# moonurl

URI references for MoonBit, as RFC 3986 defines them: taking one apart, putting it back, resolving a relative one against a base, normalising, and percent coding by component. Data URLs ride on top. No sockets.

```moonbit
let base = @moonurl.Url::decode("http://a/b/c/d;p?q")
base.resolve(@moonurl.Url::decode("../g")).encode() // "http://a/b/g"
@moonurl.escape_text("a b&c/d", kind=Query)         // "a%20b&c/d"
@dataurl.Url::decode("data:,A%20brief%20note").data // b"A brief note"
```

`moon run examples/tour` takes a reference apart, resolves the RFC 3986 §5.4 examples and escapes one string for four components; `moon run examples/data` reads the four examples RFC 2397 prints.

## Packages

|  Package  | What | Specification |
|:--:|:--|:--|
| `moonurl` | URI references: parsing, recomposing, resolving, normalising, percent coding by component | RFC 3986 |
| `moonurl/dataurl` | A whole representation written inside the reference to it | RFC 2397 |

Not here: internationalised host names (RFC 3492), and what belongs to the WHATWG URL Standard rather than to RFC 3986 — special schemes, default ports, Windows drive letters.

## Licence

Apache-2.0.
