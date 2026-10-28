// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The same strings a browser reads, read the same way: special schemes, host
/// names in any spelling, a path normalised, an origin, and what the setters
/// do to a URL that is already there.
fn main raise {
  // A string that RFC 3986 would take apart and leave alone, and a browser
  // does not.
  for
    text in [
      "HTTP://EXAMPLE.test:80/a/../b?q#f", "http:example.test", "https://example.test/a b/ü",
      "http://192.0x00A80001/", "http://0x7f.1/", "http://[2001:db8::1]:8080/x",
      "file:///C|/tmp/x", "mailto:leo@example.test",
    ] {
    let whatwg = @moonurl.Url::decode(text[:], syntax=@moonurl.Whatwg)
    let rfc = @moonurl.Url::decode(text[:])
    println(text)
    println("  whatwg  " + whatwg.encode())
    println("  rfc     " + rfc.encode())
    println("  origin  " + whatwg.origin())
    println("")
  }

  // A relative reference against a base, in the browser's grammar.
  let base = @moonurl.Url::decode(
    "https://example.test/a/b/c",
    syntax=@moonurl.Whatwg,
  )
  for reference in ["../d", "/e", "?q=1", "#top", "//other.test/f"] {
    let target = @moonurl.Url::decode(
      reference[:],
      syntax=@moonurl.Whatwg,
      base~,
    )
    println("\{reference}  ->  \{target.encode()}")
  }
  println("")

  // Host names, international and otherwise.
  for
    name in [
      "münchen.example", "他们.example", "xn--mnchen-3ya.example", "example.test.",
    ] {
    let ascii = @moonurl.domain(name[:])
    println("\{name}  ->  \{ascii}")
  }
  println("")

  // The setters change one piece and leave the rest where it was.
  let url = @moonurl.Url::decode(
    "http://example.test/a/b?q=1#f",
    syntax=@moonurl.Whatwg,
  )
  println("start     " + url.encode())
  println("scheme    " + url.set_scheme("https").encode())
  println("port      " + url.set_port("8080").encode())
  println("path      " + url.set_path("/x/../y").encode())
  println("query     " + url.set_query("a=1&b=2").encode())
  println("fragment  " + url.set_fragment("none").encode())
  println(
    "absent    " + url.set_port("").set_query("").set_fragment("").encode(),
  )
}
