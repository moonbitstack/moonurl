#!/usr/bin/env python3
"""Generate the differential vectors against Node's WHATWG URL implementation.

Node carries a second, independent implementation of the URL Standard (ada,
behind `new URL`).  Its answers are recorded here as a corpus this package
replays, so a disagreement with a mature implementation shows up as a red test
rather than as a bug found by a user.

What is recorded, per input:
  * the eleven getters Node answers, and the serialisation;
  * for the setters, one component changed and the URL that results;
  * for form bodies, the serialised pairs before and after `sort()`;
  * for hosts, the host a URL parser makes of `http://<host>/`.

The serialisation is also required to be a fixed point of Node's parser: if
Node reads our corpus's `href` and writes something else, the row is rejected
while generating, because then the two implementations would not agree on the
bytes either of them writes.

Writes src/vectors_node_test.mbt.  Run from the repository root.  Nothing here
ships with the library.
"""

import json
import os
import subprocess
import sys
import tempfile

OUT = os.path.join("src", "vectors_node_test.mbt")

# Absolute URLs, every corner the two grammars have: credentials, ports,
# numeric hosts, brackets, international names, escapes, dot segments, the
# opaque paths of schemes without an authority, and the strings a browser
# refuses.
URLS = [
    "http://example.test",
    "http://example.test/",
    "HTTP://EXAMPLE.TEST/A/B",
    "http://h:80/",
    "https://h:443/",
    "ws://h:80/",
    "wss://h:443/",
    "ftp://h:21/",
    "http://h:8080/",
    "https://h:80/",
    "http://h:/p",
    "http://h:0/",
    "http://h:65535/",
    "http://h:65536/",
    "http://h:00080/",
    "http://user:pw@h:8080/a?q=1#f",
    "http://user@h/",
    "http://:pw@h/",
    "http://user:@h/",
    "http://a@b@h/p",
    "http://u%40s:p%3Aw@h/",
    "http://@h/",
    "http://[2001:db8::1]/",
    "http://[2001:db8::1]:8080/",
    "http://[2001:db8:0:0:0:0:0:1]/",
    "http://[::ffff:127.0.0.1]/",
    "http://[::]/",
    "http://[0:0:0:0:0:0:0:0]/",
    "http://[::1]/p?q#f",
    "http://[::1/",
    "http://[::1]:/",
    "http://127.0.0.1/",
    "http://0x7f.1/",
    "http://0177.0.0.1/",
    "http://2130706433/",
    "http://1.2.3.4.5/",
    "http://1.2.3.256/",
    "http://0x100000000/",
    "http://example.test./",
    "http://münchen.example/",
    "http://MÜNCHEN.example/",
    "http://xn--mnchen-3ya.example/",
    "http://faß.de/",
    "http://例え.テスト/",
    "http://example.test/%7euser",
    "http://example.test/a%2fb",
    "http://example.test/a%2Fb",
    "http://example.test/a b",
    "http://example.test/a\\b",
    "http://example.test/a/./b/../c",
    "http://example.test/../../a",
    "http://example.test/a//b",
    "http://example.test//a",
    "http://example.test/p?",
    "http://example.test/p#",
    "http://example.test/p?#f",
    "http://example.test/p?q#",
    "http://example.test/?a=b c",
    "http://example.test/?a='",
    "http://example.test/?a=%27",
    "http://example.test/?a=1&a=2&b=",
    "http://example.test/#a b`",
    "http://example.test/#a%60b",
    "http://example.test/中",
    "http://example.test/%E4%B8%AD",
    "http://example.test/ ",
    "http://example.test/\u007f",
    "http://example.test/\u0080",
    "http://example.test/a;b=c",
    "http:example.test/p",
    "http:/example.test/p",
    "http:////example.test//a",
    "http:\\\\example.test\\a",
    "file:///tmp/x",
    "file:///",
    "file://C:/x",
    "file://C|/x",
    "file://localhost/x",
    "file://LOCALHOST/x",
    "file://server/share/x",
    "file:///c|/x",
    "file:/tmp/x",
    "file:tmp/x",
    "mailto:leo@example.test",
    "mailto:leo@example.test?subject=a b",
    "mailto:",
    "data:,x",
    "data:text/plain,Hi%20there",
    "blob:https://example.test/1e2f",
    "blob:null/1e2f",
    "javascript:alert(1)",
    "about:blank",
    "urn:isbn:0451450523",
    "foo:a/../b",
    "foo://h/",
    "foo://h/a\\b",
    "foo://h/?a='",
    "foo://h/#a`",
    "foo://H/A",
    "sc://ñ.example/",
    "http://",
    "http://exa mple.test/",
    "http://h\u0000/",
    "1http://h/",
    "http://%zz/",
    "http://h:8a/",
    "https://",
]

# Relative references and the bases they are read against.
BASES = [
    "http://a/b/c/d;p?q",
    "https://example.test/a/b/c",
    "http://example.test/a/b/c/",
    "file:///a/b/c",
    "foo://h/a/b/c",
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
    "g.",
    ".g",
    "g..",
    "..g",
    "./../g",
    "./g/.",
    "g/./h",
    "g/../h",
    "..\\g",
    "\\\\g",
    "http:g",
    "https:g",
    "//",
    "///g",
    "/./g",
    "/../g",
    "?",
    "#",
    "g?",
    "g#",
]

# Each setter, with a value that changes the URL and a value it must refuse.
SETTINGS = [
    ("protocol", "http://example.test/a?q=1#f", "https"),
    ("protocol", "http://example.test/a", "foo"),
    ("protocol", "foo://h/a", "http"),
    ("protocol", "http://h/a", "1http"),
    ("username", "http://h/a", "user"),
    ("username", "http://u@h/a", "me"),
    ("username", "http://h/a", "a b"),
    ("username", "http://h/a", "a@b"),
    ("password", "http://u:p@h/a", "pw"),
    ("password", "http://u:p@h/a", ""),
    ("password", "http://h/a", "p:w"),
    ("host", "http://u:p@h:8080/a", "other.test:9090"),
    ("host", "http://u:p@h:8080/a", "other.test"),
    ("host", "http://h/a", ""),
    ("host", "http://h/a", "[::1]:81"),
    ("host", "http://h/a", "münchen.example"),
    ("host", "http://h/a", "exa mple"),
    ("hostname", "http://h:8080/a", "other.test"),
    ("hostname", "http://h:8080/a", "[::2]"),
    ("hostname", "http://h/a", ""),
    ("port", "http://h/a", "8080"),
    ("port", "http://h/a", ""),
    ("port", "http://h/a", "80"),
    ("port", "http://h/a", "eighty"),
    ("port", "http://h/a", "65536"),
    ("pathname", "http://h/a", "/b/c"),
    ("pathname", "http://h/a", "b/c"),
    ("pathname", "http://h/a", "/a/../b"),
    ("pathname", "http://h/a", ""),
    ("pathname", "foo://h/a", "b/../c"),
    ("search", "http://h/a?q=1", "z=2"),
    ("search", "http://h/a?q=1", "?z=2"),
    ("search", "http://h/a?q=1", ""),
    ("search", "http://h/a", "a b"),
    ("hash", "http://h/a#f", "g"),
    ("hash", "http://h/a#f", "#g"),
    ("hash", "http://h/a#f", ""),
    ("hash", "http://h/a", "a b`"),
]

# Form bodies, as they arrive.
QUERIES = [
    "a=1&b=2&a=3",
    "b=2&a=1&b=3",
    "a",
    "a=",
    "=b",
    "&",
    "&&&a=b&&&&c=d&",
    "a=a+b+c+d",
    "a=%26b%3Dc",
    "a=%E9%AA%87",
    "a=*%2D._",
    "a=%7E",
    "a=b%2Bc&a%2Bb=c",
    "a==a",
    "%=a",
    "b=%%2a",
    "id=0&value=%",
    "a=b&c=d&&e&&",
    "a = b &a=b&c=d%20",
    "a=%00",
    "A=1&a=2",
    "\U0002000BC=1",
    "a=1&a=2&a=3&a=4",
    "",
]

# Host names, through `url.domainToASCII`.  An empty answer means refused.
HOSTS = [
    "example.test",
    "EXAMPLE.TEST",
    "example.test.",
    "münchen.example",
    "MÜNCHEN.example",
    "xn--mnchen-3ya.example",
    "例え.テスト",
    "faß.de",
    "Faß.de",
    "βόλος.example",
    "a\u200cb.example",
    "a\u200db.example",
    "-x.example",
    "x-.example",
    "ab--c.example",
    "exa mple.test",
    "a..b",
    ".a",
    "a..",
    "a" * 64 + ".example",
    ".".join(["a" * 63] * 4),
    # `xn--a` and `xn--999999999999` are left out on purpose: UTS 46 keeps an
    # A-label it cannot decode and web-platform-tests records that answer, while
    # Node refuses it. Taking the standard's side, as `src/interop_test.mbt`
    # says, keeps this file a comparison and not an argument.
    "127.0.0.1",
    "0x7f.1",
    "2130706433",
    "exa%41mple.test",
    "Ünïcödé.example",
    "日本語.jp",
    "ÖBB.at",
    "a_b.example",
    "a*b.example",
    "a\u00adb.example",
    "a\u200db\u200dc.example",
]

NODE_PROGRAM = r"""
import { readFileSync } from "node:fs";
const payload = JSON.parse(readFileSync(process.argv[2], "utf8"));
const out = { urls: [], settings: [], queries: [], sorts: [], hosts: [] };
for (const one of payload.urls) {
  try {
    const u = new URL(one.input, one.base === null ? undefined : one.base);
    out.urls.push({
      ok: true, href: u.href, again: new URL(u.href).href,
      protocol: u.protocol, username: u.username,
      password: u.password, host: u.host, hostname: u.hostname, port: u.port,
      pathname: u.pathname, search: u.search, hash: u.hash, origin: u.origin,
    });
  } catch (e) {
    out.urls.push({ ok: false });
  }
}
for (const one of payload.settings) {
  const u = new URL(one.base);
  u[one.which] = one.value;
  out.settings.push({ href: u.href });
}
for (const raw of payload.queries) {
  const p = new URLSearchParams(raw);
  const before = p.toString();
  p.sort();
  out.queries.push({ before: before, after: p.toString() });
}
for (const name of payload.hosts) {
  try {
    out.hosts.push({ ascii: new URL("http://" + name + "/").hostname });
  } catch (e) {
    out.hosts.push({ ascii: "" });
  }
}
process.stdout.write(JSON.stringify(out));
"""


def literal(text):
    """A MoonBit string literal, the same escaping gen_whatwg.py uses."""
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


def ask(payload):
    with tempfile.NamedTemporaryFile(
        "w", suffix=".json", delete=False, encoding="utf-8"
    ) as handle:
        json.dump(payload, handle)
        corpus = handle.name
    with tempfile.NamedTemporaryFile(
        "w", suffix=".mjs", delete=False, encoding="utf-8"
    ) as handle:
        handle.write(NODE_PROGRAM)
        program = handle.name
    try:
        result = subprocess.run(
            ["node", program, corpus],
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
    finally:
        os.unlink(program)
        os.unlink(corpus)
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        raise SystemExit("node failed")
    return json.loads(result.stdout)


def main():
    urls = [{"input": text, "base": None} for text in URLS]
    for base in BASES:
        for ref in REFS:
            urls.append({"input": ref, "base": base})
    answers = ask(
        {
            "urls": urls,
            "settings": [
                {"which": which, "base": base, "value": value}
                for which, base, value in SETTINGS
            ],
            "queries": QUERIES,
            "hosts": HOSTS,
        }
    )
    version = subprocess.run(
        ["node", "--version"], capture_output=True, text=True
    ).stdout.strip()
    lines = [
        "// Copyright 2026 Leo Cheng",
        "// SPDX-License-Identifier: Apache-2.0",
        "",
        "// Generated by scripts/gen_node.py from Node's own URL implementation",
        "// (%s, ada), which reads the URL Standard independently of the" % version,
        "// web-platform-tests files this package already replays. Do not edit.",
        "",
        "///|",
        "/// One row of the differential corpus: the input and the base it was",
        "/// read against, then what Node answers for each getter.",
        "struct NodeCase {",
        "  input : String",
        "  base : String",
        "  href : String",
        "  protocol : String",
        "  username : String",
        "  password : String",
        "  host : String",
        "  hostname : String",
        "  port : String",
        "  pathname : String",
        "  search : String",
        "  hash : String",
        "  origin : String",
        "}",
        "",
        "///|",
        "let node_cases : Array[NodeCase] = [",
    ]
    accepted = 0
    for row, answer in zip(urls, answers["urls"]):
        if not answer["ok"]:
            continue
        if answer["again"] != answer["href"]:
            raise SystemExit(
                "%r reads back as %r in Node" % (answer["href"], answer["again"])
            )
        accepted += 1
        lines.append("  {")
        lines.append("    input: %s," % literal(row["input"]))
        lines.append("    base: %s," % literal(row["base"] or ""))
        lines.append("    href: %s," % literal(answer["href"]))
        for name in [
            "protocol",
            "username",
            "password",
            "host",
            "hostname",
            "port",
            "pathname",
            "search",
            "hash",
            "origin",
        ]:
            lines.append("    %s: %s," % (name, literal(answer[name])))
        lines.append("  },")
    lines.append("]")
    lines.append("")
    lines.append("///|")
    lines.append("/// One setter applied to one URL, and the URL Node reports afterwards.")
    lines.append("struct NodeSetting {")
    lines.append("  which : String")
    lines.append("  base : String")
    lines.append("  value : String")
    lines.append("  href : String")
    lines.append("}")
    lines.append("")
    lines.append("///|")
    lines.append("let node_settings : Array[NodeSetting] = [")
    for (which, base, value), answer in zip(SETTINGS, answers["settings"]):
        lines.append("  {")
        lines.append("    which: %s," % literal(which))
        lines.append("    base: %s," % literal(base))
        lines.append("    value: %s," % literal(value))
        lines.append("    href: %s," % literal(answer["href"]))
        lines.append("  },")
    lines.append("]")
    lines.append("")
    lines.append("///|")
    lines.append("/// A form body before and after a sort, as Node's `URLSearchParams`")
    lines.append("/// writes it.")
    lines.append("let node_queries : Array[(String, String, String)] = [")
    for raw, answer in zip(QUERIES, answers["queries"]):
        lines.append(
            "  (%s, %s, %s),"
            % (literal(raw), literal(answer["before"]), literal(answer["after"]))
        )
    lines.append("]")
    lines.append("")
    lines.append("///|")
    lines.append("/// A host name and what `url.domainToASCII` makes of it. An empty")
    lines.append("/// answer is a name Node refuses.")
    lines.append("let node_hosts : Array[(String, String)] = [")
    for name, answer in zip(HOSTS, answers["hosts"]):
        lines.append("  (%s, %s)," % (literal(name), literal(answer["ascii"])))
    lines.append("]")
    lines.append("")
    lines.append(REPLAY)
    write("\n".join(lines) + "\n")
    print(
        "src/vectors_node_test.mbt: %d parse rows, %d setter rows, %d bodies, %d hosts"
        % (accepted, len(SETTINGS), len(QUERIES), len(HOSTS))
    )


REPLAY = r'''///|
/// The corpus, read the way a browser reads it: every getter and the
/// serialisation against a second implementation of the same standard.
test "URL parsing, against Node" {
  let complaints : Array[String] = []
  for case in node_cases {
    let base = if case.base == "" {
      None
    } else {
      Some(@moonurl.Url::decode(case.base[:], syntax=@moonurl.Whatwg)) catch {
        _ => None
      }
    }
    let parsed = Some(
      @moonurl.Url::decode(case.input[:], syntax=@moonurl.Whatwg, base?),
    ) catch {
      _ => None
    }
    match parsed {
      None => complaints.push("\{case.input}: refused, Node reads it")
      Some(url) => {
        let label = if case.base == "" {
          case.input
        } else {
          "\{case.input} against \{case.base}"
        }
        note(complaints, url.encode() == case.href, label, "href", url.encode(), case.href)
        // Node writes bytes that are a URL again, and our reader has to see the
        // same URL in them: the second half of a round trip between the two.
        let reread = Some(
          @moonurl.Url::decode(case.href[:], syntax=@moonurl.Whatwg),
        ) catch {
          _ => None
        }
        match reread {
          None => complaints.push("\{label}: our bytes \{case.href} do not read back")
          Some(again) =>
            note(
              complaints,
              again.encode() == case.href,
              label,
              "re-reading",
              again.encode(),
              case.href,
            )
        }
        let fields = fields_of(url)
        let want = [
          case.protocol,
          case.username,
          case.password,
          case.host,
          case.hostname,
          case.port,
          case.pathname,
          case.search,
          case.hash,
          case.origin,
        ]
        let names = [
          "protocol", "username", "password", "host", "hostname", "port", "pathname",
          "search", "hash", "origin",
        ]
        for i, name in names {
          note(complaints, fields[i] == want[i], label, name, fields[i], want[i])
        }
      }
    }
  }
  complain(complaints)
}

///|
/// The nine setters, on values that change the URL and on values that must not.
test "URL setters, against Node" {
  let complaints : Array[String] = []
  for setting in node_settings {
    let url = @moonurl.Url::decode(setting.base[:], syntax=@moonurl.Whatwg)
    let after = match setting.which {
      "protocol" => url.set_scheme(setting.value[:])
      "username" => url.set_username(setting.value[:])
      "password" => url.set_password(setting.value[:])
      "host" => url.set_host(setting.value[:])
      "hostname" => url.set_hostname(setting.value[:])
      "port" => url.set_port(setting.value[:])
      "pathname" => url.set_path(setting.value[:])
      "search" => url.set_query(setting.value[:])
      "hash" => url.set_fragment(setting.value[:])
      other => fail("no setter named \{other}")
    }
    note(
      complaints,
      after.encode() == setting.href,
      "\{setting.which} = \{setting.value} on \{setting.base}",
      "href",
      after.encode(),
      setting.href,
    )
  }
  complain(complaints)
}

///|
/// A form body read and written by Node's `URLSearchParams`, before and after
/// its `sort`.
test "form bodies, against Node" {
  let complaints : Array[String] = []
  for row in node_queries {
    let (raw, written, sorted) = row
    let query = @moonurl.Query::decode(@utf8.encode(raw)[:])
    note(complaints, query.encode() == written, raw, "encode", query.encode(), written)
    query.sort()
    note(complaints, query.encode() == sorted, raw, "sort", query.encode(), sorted)
  }
  complain(complaints)
}

///|
/// Hosts, through the parser a browser uses: UTS 46, the numeric spellings of
/// IPv4, escapes and the brackets of IPv6, against Node's answers.
test "hosts, against Node" {
  let complaints : Array[String] = []
  for row in node_hosts {
    let (name, want) = row
    let text = "http://" + name + "/"
    let got = Some(@moonurl.Url::decode(text[:], syntax=@moonurl.Whatwg)) catch {
      _ => None
    }
    match got {
      None =>
        if want != "" {
          complaints.push("\{name}: refused, Node reads \{want}")
        }
      Some(url) =>
        if want == "" {
          let read = url.host.unwrap_or("")
          complaints.push("\{name}: read as \{read}, Node refuses it")
        } else {
          note(
            complaints,
            url.host == Some(want),
            name,
            "host",
            url.host.unwrap_or(""),
            want,
          )
        }
    }
  }
  complain(complaints)
}
'''


def write(text):
    with open(OUT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    # The rows are as long as their URLs, and the formatter decides where to
    # break them; running it here keeps a regenerated file identical to the
    # one CI checks with `moon fmt && git diff --exit-code`.
    subprocess.run(["moon", "fmt"], check=True)


if __name__ == "__main__":
    main()
