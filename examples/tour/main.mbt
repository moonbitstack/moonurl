// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A URI reference, taken apart and put back; a relative one resolved against
/// a base; and the same text escaped for four different components.
fn main raise {
  let url = @moonurl.Url::decode(
    "https://leo:pw@example.test:12000/v1/a%20b?q=1#top",
  )
  println("scheme    " + show(url.scheme))
  println("userinfo  " + show(url.userinfo))
  println("host      " + show(url.host))
  println("port      " + show(url.port.map(fn(p) { p.to_string() })))
  println("path      " + url.path)
  println("query     " + show(url.query))
  println("fragment  " + show(url.fragment))
  println("back      " + url.encode())
  println("")

  // RFC 3986 §5.4, a few of the examples the section prints.
  let base = @moonurl.Url::decode("http://a/b/c/d;p?q")
  for reference in ["g", "./g", "/g", "//g", "?y", "#s", "..", "../../g", "g:h"] {
    let target = base.resolve(@moonurl.Url::decode(reference[:])).encode()
    println("against http://a/b/c/d;p?q  \{reference}  ->  \{target}")
  }
  println("")

  // Which octets may stand for themselves is the component's question.
  let text = "a b&c/d"
  for
    one in [
      ("Bare", @moonurl.escape_text(text)),
      ("Path", @moonurl.escape_text(text, kind=Path)),
      ("Query", @moonurl.escape_text(text, kind=Query)),
      ("Whole", @moonurl.escape_text(text, kind=Whole)),
    ] {
    println("\{one.0}  \{one.1}")
  }
  println("")

  // RFC 3986 §6.2.2, the three things normalising does.
  let messy = @moonurl.Url::decode("HTTP://EXAMPLE.test/a/./b/../c/%7euser")
  println("messy     " + messy.encode())
  println("normal    " + messy.normalize().encode())
}

///|
fn show(value : String?) -> String {
  match value {
    Some(value) => "\"" + value + "\""
    None => "(absent)"
  }
}
