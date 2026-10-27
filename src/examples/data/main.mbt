// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The four examples RFC 2397 §4 prints, then the same payload written both
/// ways, then the two things `strict` refuses.
fn main raise {
  for
    text in [
      "data:,A%20brief%20note", "data:text/plain;charset=iso-8859-7,%be%fg%be", "data:image/gif;base64,AAEC",
      "data:application/vnd-xxx-query,select_vcount,fcol_from_fieldtable/local",
    ] {
    let url = @dataurl.Url::decode(text[:])
    println(text)
    println("  type     " + url.kind)
    println("  charset  " + url.charset())
    println("  octets   " + octets(url.data))
    println("")
  }

  // One payload, both spellings. Base64 by default, because it is the only one
  // that does not grow for octets that are not text.
  let icon = @dataurl.Url::new(b"\x89PNG\r\n\x1a\n", kind="image/png")
  println("base64    " + icon.encode())
  println("percent   " + icon.encode(base64=false))
  println("")

  // A media type equal to the default is left out, and reading puts it back.
  let note = @dataurl.Url::new(@utf8.encode("A brief note"))
  println("written   " + note.encode(base64=false))
  println(
    "read back " + @dataurl.Url::decode(note.encode(base64=false)[:]).kind,
  )
  println("")

  // What a browser lets pass, and what `strict` will not.
  for text in ["data:,100%", "data:;base64,AA\nEC"] {
    let lenient = @dataurl.Url::decode(text[:])
    println("lenient   " + octets(lenient.data))
    try @dataurl.Url::decode(text[:], strict=true) |> ignore catch {
      e => println("strict    refused: " + e.to_repr().to_string())
    }
  }
}

///|
fn octets(data : Bytes) -> String {
  let out = StringBuilder()
  for i = 0; i < data.length(); i = i + 1 {
    let b = data[i].to_int()
    if b >= 0x20 && b < 0x7F {
      out.write_char(b.unsafe_to_char())
    } else {
      out.write_string("<\{b}>")
    }
  }
  out.to_string()
}
