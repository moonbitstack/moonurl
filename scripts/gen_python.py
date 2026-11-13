#!/usr/bin/env python3
"""Generate the differential vectors against Python's `urllib.parse`.

Python's `urllib.parse` is an independent reading of the same RFC 3986 this
package's `Rfc3986` syntax implements: `urljoin` for reference resolution,
`urlsplit` for taking a reference apart, and `quote` for which octets of a
component may stand for themselves.  Its answers are recorded here as a corpus
this package replays.

`quote` is compared over the whole of ASCII: for every component, every code
point, whether Python leaves it alone.  That is the escape table itself, which
otherwise only round trips would exercise.

Four behaviours of Python's are deliberately not recorded, because they are
properties of its model rather than of the RFC.  `src/interop_test.mbt` states
each one and what this package answers:

  * a reference whose scheme is the base's (`http:g`) is read as relative,
    where RFC 3986 §5.4.2 keeps `http:g`;
  * `urlsplit` cannot tell an empty component from an absent one, so a
    reference that is nothing but `?` or `#` comes back without its delimiter,
    where RFC 3986 §5.3 writes it;
  * an empty reference returns the base with its fragment, where §5.2.2 takes
    the fragment from the reference and so drops it;
  * `urljoin` only resolves a reference against a scheme on its own list
    (`uses_relative`), so a base of any other scheme — and a base that is not
    absolute, which RFC 3986 §5.1 leaves undefined — is left out.

Writes src/vectors_python_test.mbt.  Run from the repository root.  Nothing
here ships with the library.
"""

import os
import subprocess
import sys
import urllib.parse

OUT = os.path.join("src", "vectors_python_test.mbt")

BASES = [
    "http://a/b/c/d;p?q",
    "http://a/b/c/d",
    "http://a/b/c/",
    "http://a/b/",
    "http://a/",
    "http://a",
    "https://example.test/a/b?x=1",
    "http://user:pw@h:8080/a/b?x=1",
    "http://[2001:db8::1]/a/b",
]

REFS = [
    "g:h",
    "g",
    "./g",
    "g/",
    "/g",
    "//g",
    "?y",
    "g?y",
    "#s",
    "g#s",
    "g?y#s",
    ";x",
    "g;x",
    "g;x?y#s",
    "",
    ".",
    "./",
    "..",
    "../",
    "../g",
    "../..",
    "../../",
    "../../g",
    "../../../g",
    "../../../../g",
    "/./g",
    "/../g",
    "g.",
    ".g",
    "g..",
    "..g",
    "./../g",
    "./g/.",
    "g/./h",
    "g/../h",
    "g;x=1/./y",
    "g;x=1/../y",
    "g?y/./x",
    "g?y/../x",
    "g#s/./x",
    "g#s/../x",
    "https:g",
    "http:g",
    "/a/./b/../c",
    "a%20b",
    "%2e%2e/g",
]

SPLITS = [
    "http://example.test",
    "http://example.test/",
    "http://example.test:8080/a/b?x=1#f",
    "http://user:pw@example.test:8080/a/b",
    "http://a@b@example.test/p",
    "http://[2001:db8::1]:8080/a",
    "http://[::1]/p?q#f",
    "https://example.test/a%2Fb?q=%20#frag",
    "//example.test/p",
    "//example.test",
    "/a/b/c",
    "a/b/c",
    "",
    "?q",
    "#f",
    "mailto:leo@example.test",
    "urn:isbn:0451450523",
    "file:///tmp/x",
    "file://localhost/tmp/x",
    "foo://h/a/b",
    "foo:/a/b",
    "http://example.test/a/../b",
    "http://example.test/a//b",
    "http://example.test/p?",
    "http://example.test/p#",
    "http://example.test/p?#",
    "http://example.test./",
]

# The characters a component may keep, as Python's `quote` sees them: the safe
# set each component has under RFC 3986 §3.
SAFE = {
    "Bare": "",
    "Userinfo": "!$&'()*+,;=:",
    "Host": "!$&'()*+,;=",
    "Segment": "!$&'()*+,;=:@",
    "Path": "!$&'()*+,;=:@/",
    "Query": "!$&'()*+,;=:@/?",
    "Fragment": "!$&'()*+,;=:@/?",
}

# Strings written through every component, so the table above is not the only
# thing compared: text, escapes and octets that are not ASCII.
TEXTS = [
    "aZ09-._~",
    "a b",
    "a/b",
    "a?b#c",
    "a&b=c",
    "100%",
    "%7e",
    "résumé",
    "骇兔 rides",
    "a+b",
    "!$&'()*+,;=:@",
    "",
]

KINDS = ["Bare", "Userinfo", "Host", "Segment", "Path", "Query", "Fragment"]


def literal(text):
    out = []
    for character in text:
        point = ord(character)
        if character == '"':
            out.append('\\"')
        elif character == "\\":
            out.append("\\\\")
        elif 0x20 <= point < 0x7F:
            out.append(character)
        else:
            out.append("\\u{%X}" % point)
    return '"' + "".join(out) + '"'


def main():
    joins = []
    for base in BASES:
        for ref in REFS:
            if ref.split(":")[0] == base.split(":")[0] and ":" in ref:
                if not ref.startswith("//") and ref.split(":")[0] in (
                    "http",
                    "https",
                    "file",
                    "foo",
                ):
                    # Python reads a reference with the base's own scheme as
                    # relative; RFC 3986 §5.4.2 does not. Left to
                    # `src/interop_test.mbt`.
                    continue
            joins.append((base, ref, urllib.parse.urljoin(base, ref)))

    lines = [
        "// Copyright 2026 Leo Cheng",
        "// SPDX-License-Identifier: Apache-2.0",
        "",
        "// Generated by scripts/gen_python.py from Python %s's" % sys.version.split()[0],
        "// `urllib.parse`, an implementation of RFC 3986 that is not this one.",
        "// Do not edit.",
        "",
        "///|",
        "/// A base, a reference and the reference resolved against it, as",
        "/// `urllib.parse.urljoin` answers.",
        "let python_joins : Array[(String, String, String)] = [",
    ]
    for base, ref, joined in joins:
        lines.append(
            "  (%s, %s, %s)," % (literal(base), literal(ref), literal(joined))
        )
    lines.append("]")
    lines.append("")
    lines.append("///|")
    lines.append("/// A reference and its five components, as `urllib.parse.urlsplit`")
    lines.append("/// answers them: scheme, authority, path, query, fragment. Absent and")
    lines.append("/// empty are both written as nothing, since `urlsplit` does not tell")
    lines.append("/// them apart.")
    lines.append("let python_splits : Array[(String, String, String, String, String, String)] = [")
    for text in SPLITS:
        parts = urllib.parse.urlsplit(text)
        lines.append(
            "  (%s, %s, %s, %s, %s, %s),"
            % (
                literal(text),
                literal(parts.scheme),
                literal(parts.netloc),
                literal(parts.path),
                literal(parts.query),
                literal(parts.fragment),
            )
        )
    lines.append("]")
    lines.append("")
    lines.append("///|")
    lines.append("/// For each component, every code point of ASCII and whether")
    lines.append("/// `quote` leaves it as it is.")
    lines.append("let python_kept : Array[(String, Array[Bool])] = [")
    for kind in KINDS:
        safe = SAFE[kind]
        kept = []
        for point in range(0x80):
            character = chr(point)
            kept.append("true" if urllib.parse.quote(character, safe=safe) == character else "false")
        lines.append("  (")
        lines.append("    %s," % literal(kind))
        lines.append("    [")
        for start in range(0, 0x80, 8):
            lines.append("      " + ", ".join(kept[start : start + 8]) + ",")
        lines.append("    ],")
        lines.append("  ),")
    lines.append("]")
    lines.append("")
    lines.append("///|")
    lines.append("/// The same strings written through every component.")
    lines.append("let python_texts : Array[(String, String, String)] = [")
    for kind in KINDS:
        for text in TEXTS:
            lines.append(
                "  (%s, %s, %s),"
                % (
                    literal(kind),
                    literal(text),
                    literal(urllib.parse.quote(text, safe=SAFE[kind])),
                )
            )
    lines.append("]")
    lines.append("")
    lines.append(REPLAY)
    with open(OUT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")
    # The rows are as long as their URLs, and the formatter decides where to
    # break them; running it here keeps a regenerated file identical to the
    # one CI checks with `moon fmt && git diff --exit-code`.
    subprocess.run(["moon", "fmt"], check=True)
    print(
        "src/vectors_python_test.mbt: %d resolutions, %d splits, %d components, %d strings"
        % (len(joins), len(SPLITS), len(KINDS), len(KINDS) * len(TEXTS))
    )


REPLAY = r'''///|
/// Every component, and the two ways of naming it.
fn kind_named(name : String) -> @moonurl.Kind raise {
  match name {
    "Bare" => Bare
    "Userinfo" => Userinfo
    "Host" => Host
    "Segment" => Segment
    "Path" => Path
    "Query" => Query
    "Fragment" => Fragment
    other => fail("no component named \{other}")
  }
}

///|
/// Reference resolution, against Python's `urljoin`: the whole of RFC 3986
/// §5.4, and every base a reference can be read against.
test "resolution, against Python" {
  let complaints : Array[String] = []
  for row in python_joins {
    let (base, reference, joined) = row
    let checked = Some(
      @moonurl.Url::decode(reference[:], base=@moonurl.Url::decode(base[:])),
    ) catch {
      _ => None
    }
    match checked {
      None => complaints.push("\{reference} against \{base}: refused")
      Some(url) =>
        note(
          complaints,
          url.encode() == joined,
          "\{reference} against \{base}",
          "joined",
          url.encode(),
          joined,
        )
    }
  }
  complain(complaints)
}

///|
/// Taking a reference apart, against Python's `urlsplit`.
test "splitting, against Python" {
  let complaints : Array[String] = []
  for row in python_splits {
    let (text, scheme, netloc, path, query, fragment) = row
    let url = @moonurl.Url::decode(text[:])
    let got = [
      url.scheme.unwrap_or(""),
      url.authority().unwrap_or(""),
      url.path,
      url.query.unwrap_or(""),
      url.fragment.unwrap_or(""),
    ]
    let want = [scheme, netloc, path, query, fragment]
    let names = ["scheme", "authority", "path", "query", "fragment"]
    for i, name in names {
      note(complaints, got[i] == want[i], text, name, got[i], want[i])
    }
  }
  complain(complaints)
}

///|
/// The escape table of each component against `quote`: every octet of ASCII,
/// kept or escaped, one at a time.
test "which octets are kept, against Python" {
  let complaints : Array[String] = []
  for row in python_kept {
    let (name, kept) = row
    let kind = kind_named(name)
    for point = 0; point < 0x80; point = point + 1 {
      let character = point.unsafe_to_char()
      let text = character.to_string()
      let written = @moonurl.escape_text(text[:], kind~)
      let want = if kept[point] { text } else { hex(point) }
      note(complaints, written == want, text, name, written, want)
    }
  }
  complain(complaints)
}

///|
/// Two upper-case hex digits for an octet.
fn hex(point : Int) -> String {
  let digits : StringView = "0123456789ABCDEF"
  let high = digits[point / 16].unsafe_to_char().to_string()
  let low = digits[point % 16].unsafe_to_char().to_string()
  "%" + high + low
}

///|
/// Whole strings through each component, against `quote`.
test "strings through each component, against Python" {
  let complaints : Array[String] = []
  for row in python_texts {
    let (name, text, want) = row
    let written = @moonurl.escape_text(text[:], kind=kind_named(name))
    note(complaints, written == want, text, name, written, want)
  }
  complain(complaints)
}
'''


if __name__ == "__main__":
    main()
