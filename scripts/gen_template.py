#!/usr/bin/env python3
"""Generate the URI template conformance test from uritemplate-test.

The official suite for RFC 6570: spec-examples.json, spec-examples-by-section.json,
extended-tests.json and negative-tests.json. A row is a template and what it
expands to; an object's key order is not defined, so a row may name several
acceptable answers, and a negative row is one the reader must refuse, either
when it is read or when it is filled in.

Writes src/template/vectors_test.mbt.  Run from the repository root.  Nothing
here ships with the library.
"""

import json
import os
import subprocess
import sys
import urllib.request

# Pinned: the suite is read from one commit, so the vectors regenerate to the
# same bytes and a change upstream cannot silently rewrite what CI replays.
REVISION = "4171dac22aa67fc710b3f6df308a50bd08552986"
BASE = (
    "https://raw.githubusercontent.com/uri-templates/uritemplate-test/%s/"
    % REVISION
)
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".cache")
FILES = [
    "spec-examples.json",
    "spec-examples-by-section.json",
    "extended-tests.json",
    "negative-tests.json",
]


def fetch(name):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        sys.stderr.write("fetching %s\n" % (BASE + name))
        with urllib.request.urlopen(BASE + name) as response:
            open(path, "wb").write(response.read())
    return json.loads(open(path, encoding="utf-8").read())


def literal(text):
    out = []
    for character in str(text):
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


def value_of(value):
    if isinstance(value, bool):
        return "@template.Value::Text(%s)" % literal("true" if value else "false")
    if isinstance(value, str):
        return "@template.Value::Text(%s)" % literal(value)
    if isinstance(value, (int, float)):
        return "@template.Value::Text(%s)" % literal(repr(value))
    if isinstance(value, list):
        items = ", ".join(literal(item) for item in value)
        return "@template.Value::List([%s])" % items
    if isinstance(value, dict):
        pairs = ", ".join(
            "(%s, %s)" % (literal(key), literal(item)) for key, item in value.items()
        )
        return "@template.Value::Pairs([%s])" % pairs
    raise SystemExit("unexpected variable type %r" % type(value))


def expected_of(row):
    if len(row) != 2:
        raise SystemExit("a row with %d fields" % len(row))
    want = row[1]
    if want is False:
        return True, []
    if isinstance(want, str):
        return False, [want]
    if isinstance(want, list):
        return False, want
    raise SystemExit("unexpected expected type %r" % type(want))


def emit_test(source, section, body):
    lines = ["///|", 'test "uritemplate-test: %s / %s" {' % (source, section)]
    lines.append("  let values : Map[String, @template.Value] = Map([])")
    for name, value in (body.get("variables") or {}).items():
        if value is None:
            continue
        lines.append("  values.set(%s, %s)" % (literal(name), value_of(value)))
    lines.append("  let cases : Array[(String, Array[String], Bool)] = [")
    for row in body.get("testcases", []):
        template = row[0]
        negative, wants = expected_of(row)
        if negative:
            lines.append("    (%s, [], true)," % literal(template))
        else:
            want_list = ", ".join(literal(w) for w in wants)
            lines.append("    (%s, [%s], false)," % (literal(template), want_list))
    lines.append("  ]")
    lines.append("  let complaints : Array[String] = []")
    lines.append("  for (template, wants, refused) in cases {")
    lines.append("    let decoded = try {")
    lines.append("      Some(@template.Template::decode(template[:]))")
    lines.append("    } catch {")
    lines.append("      _ => None")
    lines.append("    }")
    lines.append("    match decoded {")
    lines.append("      None =>")
    lines.append("        if !refused {")
    lines.append(
        '          complaints.push("refused a template it must read: " + template)'
    )
    lines.append("        }")
    lines.append("      Some(t) =>")
    lines.append("        if refused {")
    lines.append("          let failed = try {")
    lines.append("            let _ = t.expand(values)")
    lines.append("            false")
    lines.append("          } catch {")
    lines.append("            _ => true")
    lines.append("          }")
    lines.append("          if !failed {")
    lines.append(
        '            complaints.push("accepted a template it must refuse: " + template)'
    )
    lines.append("          }")
    lines.append("        } else {")
    lines.append("          let expanded = try {")
    lines.append("            Some(t.expand(values))")
    lines.append("          } catch {")
    lines.append("            _ => None")
    lines.append("          }")
    lines.append("          match expanded {")
    lines.append("            None =>")
    lines.append(
        '              complaints.push("failed to expand a template it must read: " + template)'
    )
    lines.append("            Some(got) =>")
    lines.append("              if !wants.contains(got) {")
    lines.append(
        '                complaints.push("expansion of " + template + " gave " + got)'
    )
    lines.append("              }")
    lines.append("          }")
    lines.append("        }")
    lines.append("    }")
    lines.append("  }")
    lines.append("  if !complaints.is_empty() {")
    lines.append("    let out = StringBuilder()")
    lines.append('    out.write_string("\\{complaints.length()} case(s) differ:")')
    lines.append("    for i, c in complaints {")
    lines.append("      if i >= 20 {")
    lines.append("        break")
    lines.append("      }")
    lines.append('      out.write_string("\\n  " + c)')
    lines.append("    }")
    lines.append("    fail(out.to_string())")
    lines.append("  }")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def main():
    data = [(name, fetch(name)) for name in FILES]
    total = 0
    lines = [
        "// Copyright 2026 Leo Cheng",
        "// SPDX-License-Identifier: Apache-2.0",
        "",
        "// Generated by scripts/gen_template.py from uritemplate-test, the official",
        "// suite for RFC 6570, revision",
        "// 4171dac22aa67fc710b3f6df308a50bd08552986. Do not edit.",
        "",
    ]
    body_lines = []
    for name, sections in data:
        for section, body in sections.items():
            body_lines.append(emit_test(name, section, body))
            total += len(body.get("testcases", []))
    lines.append("// cases: %d" % total)
    lines.append("")
    lines.extend(body_lines)
    path = os.path.join("src", "template", "vectors_test.mbt")
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    subprocess.run(["moon", "fmt"], check=False)
    sys.stderr.write("%d template cases\n" % total)


if __name__ == "__main__":
    main()
