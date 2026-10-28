// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Record that a converted name is not the one the standard asks for, and say
/// what both are. The conformance suite is thousands of rows long, so a run
/// collects what differs instead of stopping at the first.
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
) -> Unit {
  if !same {
    complaints.push("\{what} of \{source}: the standard says otherwise")
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
