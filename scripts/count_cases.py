#!/usr/bin/env python3
"""Fill the conformance table in README.md from the generated vectors.

The counts are read out of the files the generators write, so a vector that
grows or shrinks moves the README with it. Run from the repository root. With
`--check`, write nothing and exit 1 if the README is out of date; CI uses that.
"""

import re
import sys

README = "README.md"
START = "<!-- conformance:start -->"
END = "<!-- conformance:end -->"


def array_count(text, name):
    """How many elements the top-level array named `name` holds."""
    match = re.search(r"let\s+" + re.escape(name) + r"\s*:[^=]*=\s*\[", text)
    if not match:
        raise SystemExit("no array named %s" % name)
    i = match.end()
    depth = 1
    count = 0
    expect = True
    in_string = False
    escaped = False
    while i < len(text):
        c = text[i]
        if in_string:
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == '"':
                in_string = False
            i += 1
            continue
        if c == '"':
            in_string = True
        elif c in "([{":
            if c in "({" and depth == 1 and expect:
                count += 1
                expect = False
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                return count
        elif c == "," and depth == 1:
            expect = True
        i += 1
    raise SystemExit("unterminated array named %s" % name)


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def numbers():
    url = read("src/vectors_url_test.mbt")
    host = read("src/vectors_host_test.mbt")
    idna = read("src/idna/vectors_test.mbt")
    template = read("src/template/vectors_test.mbt")
    template_cases = re.search(r"// cases: (\d+)", template)
    if not template_cases:
        raise SystemExit("no case count in src/template/vectors_test.mbt")
    rows = 0
    for batch in re.findall(r"let\s+(uts46_\d+)\s*:", idna):
        rows += array_count(idna, batch)
    return [
        ("RFC 6570 `uritemplate-test`", int(template_cases.group(1))),
        ("`urltestdata.json`", array_count(url, "url_cases")),
        ("`setters_tests.json`", array_count(url, "setter_cases")),
        ("`toascii.json`", array_count(host, "host_cases")),
        ("`IdnaTestV2.txt`", rows),
    ]


def block(rows):
    lines = [START, "| Vector | Rows |", "|:--|--:|"]
    for name, count in rows:
        lines.append("| %s | %d |" % (name, count))
    lines.append(END)
    return "\n".join(lines)


def main():
    check = "--check" in sys.argv[1:]
    readme = read(README)
    start = readme.find(START)
    end = readme.find(END)
    if start < 0 or end < 0:
        raise SystemExit("the conformance markers are missing from README.md")
    updated = readme[:start] + block(numbers()) + readme[end + len(END):]
    if check:
        if updated != readme:
            sys.stderr.write("README conformance table is out of date\n")
            raise SystemExit(1)
        return
    if updated != readme:
        with open(README, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(updated)
        sys.stderr.write("README conformance table updated\n")


if __name__ == "__main__":
    main()
