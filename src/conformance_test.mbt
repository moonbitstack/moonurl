// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The getters web-platform-tests compares against, read off a Url, and the
// reporting the generated suites share.

///|
/// A field the suite does not check.
let unchecked : String = "\u{1}"

///|
/// The ten getters a row of the suite names, in the order the rows keep them.
fn fields_of(url : @moonurl.Url) -> Array[String] {
  let protocol = match url.scheme {
    Some(scheme) => scheme + ":"
    None => ""
  }
  let (username, password) = match url.userinfo {
    Some(info) => split_at_colon(info[:])
    None => ("", "")
  }
  let hostname = hostname_of(url)
  let port = match url.port {
    Some(port) => port.to_string()
    None => ""
  }
  let host = if port == "" || url.host is None {
    hostname
  } else {
    hostname + ":" + port
  }
  let search = match url.query {
    Some(query) => if query == "" { "" } else { "?" + query }
    None => ""
  }
  let hash = match url.fragment {
    Some(fragment) => if fragment == "" { "" } else { "#" + fragment }
    None => ""
  }
  [
    protocol,
    username,
    password,
    host,
    hostname,
    port,
    url.path,
    search,
    hash,
    url.origin(),
  ]
}

///|
/// The host with its port, as the `host` getter has it.
fn hostname_of(url : @moonurl.Url) -> String {
  match url.host {
    Some(host) => if colon(host[:]) { "[" + host + "]" } else { host }
    None => ""
  }
}

///|
fn colon(text : StringView) -> Bool {
  for i = 0; i < text.length(); i = i + 1 {
    if text[i].to_int() == 0x3A {
      return true
    }
  }
  false
}

///|
fn split_at_colon(text : StringView) -> (String, String) {
  for i = 0; i < text.length(); i = i + 1 {
    if text[i].to_int() == 0x3A {
      return (text[:i].to_owned(), text[i + 1:].to_owned())
    }
  }
  (text.to_owned(), "")
}

///|
/// Record that a converted URL is not the one the suite asks for.
fn note(
  complaints : Array[String],
  same : Bool,
  source : String,
  what : String,
  got : String,
  want : String,
) -> Unit {
  if !same {
    complaints.push("\{what} of \{source}: got \{got}, want \{want}")
  }
}

///|
fn note_flag(
  complaints : Array[String],
  same : Bool,
  source : String,
  what : String,
  base : String,
) -> Unit {
  if !same {
    complaints.push(
      "\{what} of \{source} against \{base}: the suite says otherwise",
    )
  }
}

///|
/// Fail with the first twenty differences, or return if there are none.
fn complain(complaints : Array[String]) -> Unit raise {
  guard !complaints.is_empty() else { return }
  let out = StringBuilder()
  out.write_string("\{complaints.length()} case(s) differ:")
  let mut i = 0
  while i < complaints.length() && i < 20 {
    out.write_string("\n  ")
    out.write_string(complaints[i])
    i += 1
  }
  fail(out.to_string())
}
