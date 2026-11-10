#!/usr/bin/env python3
"""Write the reference in docs/index.html from the interface files and the
`///` comments beside the declarations.

The page is hand-designed; this script owns one region of it, between the
`<!-- api:begin -->` and `<!-- api:end -->` markers, and rewrites nothing
outside them. Run from the repository root:

    python3 scripts/gen_api.py            # rewrite the region
    python3 scripts/gen_api.py --check    # compare, exit 1 if stale

Every item a `pkg.generated.mbti` publishes gets its own anchor, and the
script compares the two lists before it writes: an item that is published but
not on the page stops the run, so CI cannot ship a reference that has fallen
behind the interface.
"""

import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PAGE = ROOT / "docs" / "index.html"
BEGIN = "<!-- api:begin -->"
END = "<!-- api:end -->"

# The package, its folder, the abbreviation used in anchor names, the line
# that heads the group, and the sentence a reader needs before the list. A
# package has no doc comment of its own, so the sentence lives here.
PACKAGES = [
    (
        "moonurl",
        "src",
        "moonurl",
        "Url · Query · percent coding",
        "Parsing, recomposing, resolving, normalising, origins, setters; "
        "percent coding by component; form bodies.",
    ),
    (
        "moonurl/idna",
        "src/idna",
        "idna",
        "punycode · UTS 46",
        "A name mapped to ASCII and back: the mapping table, NFC, hyphen and "
        "joiner rules, the bidi rule, and DNS lengths.",
    ),
    (
        "moonurl/template",
        "src/template",
        "template",
        "RFC 6570",
        "Holes named and filled: simple and reserved expansions, label, path "
        "and parameter operators, prefixes and exploded lists and pairs.",
    ),
    (
        "moonurl/dataurl",
        "src/dataurl",
        "dataurl",
        "RFC 2397",
        "A whole representation written inside the reference to it.",
    ),
]

# `Eq` and `Debug` are implemented on every value type; the three methods they
# bring are public but nobody looks them up, so they are named once at the foot
# of their type instead of taking a card each.
DERIVED = {"equal", "not_equal", "to_repr"}

DECL = re.compile(
    r"^pub(?:\((?:all|open)\))?\s+(fn(?:\[[^\]]*\])?|let|struct|enum|suberror|trait|type)"
    r"\s+([A-Za-z_]\w*(?:::[A-Za-z_]\w*)?)"
)
IMPL = re.compile(r"^pub impl\s+(.+?)\s*\{?$")
TRAIT_FN = re.compile(r"^\s+fn\s+([A-Za-z_]\w*)")
FIELD = re.compile(r"^\s+(?:mut\s+)?([A-Za-z_]\w*)\s*:\s*(.+?)\s*$")
VARIANT = re.compile(r"^\s+([A-Z]\w*)(\(.*\))?\s*$")
MBTI_ITEM = re.compile(
    r"pub(?:\((?:all|open)\))?\s+(struct|enum|suberror|trait)\s+(\w+)(.*)$"
)
BADGE = {
    "struct": "struct",
    "enum": "enum",
    "suberror": "error",
    "trait": "trait",
    "type": "alias",
    "impl": "impl",
    "using": "re-export",
}


def uncomment(line):
    body = line.strip()[3:]
    return body[1:] if body.startswith(" ") else body


def docs_of(folder):
    """Doc comments by item: `Name`, `Type.field`, `Type::method`."""
    out = {}
    for path in sorted((ROOT / folder).glob("*.mbt")):
        if path.name.endswith("_test.mbt"):
            continue
        owner = None
        pending = []
        for line in path.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if stripped == "///|":
                pending = []
                continue
            if stripped.startswith("///"):
                pending.append(uncomment(line))
                continue
            if stripped.startswith("#"):
                continue
            match = DECL.match(line)
            if match:
                name = match.group(2)
                if pending:
                    out[name] = pending
                owner = (
                    name
                    if match.group(1) in ("struct", "enum", "suberror", "trait")
                    and stripped.endswith("{")
                    else None
                )
                pending = []
                continue
            match = IMPL.match(line)
            if match:
                if pending:
                    out["impl " + match.group(1).split(" with ")[0]] = pending
                owner = None
                pending = []
                continue
            if owner:
                member = (
                    TRAIT_FN.match(line)
                    if line.startswith("  fn ")
                    else FIELD.match(line) or VARIANT.match(line)
                )
                if member and pending:
                    out[owner + "." + member.group(1)] = pending
                if stripped.startswith("}"):
                    owner = None
            pending = []
    return out


def signature_of(lines, start):
    """The declaration at `start`, its body's `{` and comments taken off."""
    text = lines[start].strip()
    index = start
    while not (text.endswith("{") and text.count("(") <= text.count(")")):
        if index + 1 >= len(lines):
            break
        index += 1
        text += " " + lines[index].strip()
    text = text.split("//")[0].rstrip()
    if text.endswith("{"):
        text = text[:-1].rstrip()
    text = re.sub(r"\s+", " ", text)
    # A declaration wrapped over several lines leaves a space at each break,
    # including next to the brackets; take those out so the list reads evenly.
    text = re.sub(r"\(\s+", "(", text)
    text = re.sub(r"\s+\)", ")", text)
    text = re.sub(r"\[\s+", "[", text)
    text = re.sub(r"\s+\]", "]", text)
    text = re.sub(r",\s*\)", ")", text)
    return text


def decls_of(folder):
    """What the source writes for each declaration, with the parameter names
    the interface file leaves out."""
    out = {}
    for path in sorted((ROOT / folder).glob("*.mbt")):
        if path.name.endswith("_test.mbt"):
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        for index, line in enumerate(lines):
            match = DECL.match(line)
            if not match:
                continue
            name = match.group(2)
            if match.group(1) == "let":
                out.setdefault(name, line.strip().split("=")[0].strip())
            else:
                out.setdefault(name, signature_of(lines, index))
    return out


def strip_modifier(text):
    return re.sub(r"^pub(?:\((?:all|open)\))?\s+", "", text)


def items_of(folder):
    """The public items of a package, in interface-file order."""
    text = (ROOT / folder / "pkg.generated.mbti").read_text(encoding="utf-8")
    items = []
    block = None
    for line in text.splitlines():
        if block is not None:
            block["body"].append(line)
            if line.startswith("}"):
                items.append(block)
                block = None
            continue
        if not line.startswith("pub"):
            continue
        match = MBTI_ITEM.match(line)
        if match:
            entry = {
                "kind": match.group(1),
                "name": match.group(2),
                "owner": None,
                "body": [],
            }
            if match.group(3).strip().endswith("{"):
                block = entry
            else:
                items.append(entry)
            continue
        match = re.match(r"pub fn(?:\[[^\]]*\])?\s+(\w+)::(\w+)", line)
        if match:
            items.append(
                {
                    "kind": "method",
                    "name": match.group(1) + "::" + match.group(2),
                    "owner": match.group(1),
                    "body": [line],
                }
            )
            continue
        for kind, pattern in (
            ("fn", r"pub fn(?:\[[^\]]*\])?\s+(\w+)"),
            ("let", r"pub let (\w+)"),
            ("type", r"pub type (\w+)"),
            ("impl", r"pub impl (.+?)\s*$"),
        ):
            match = re.match(pattern, line)
            if match:
                name = match.group(1)
                items.append(
                    {
                        "kind": kind,
                        "name": "impl " + name if kind == "impl" else name,
                        "owner": None,
                        "body": [line],
                    }
                )
                break
        else:
            if line.startswith("pub using"):
                items.append(
                    {"kind": "using", "name": line.strip(), "owner": None, "body": [line]}
                )
    return items


def members_of(item):
    """A struct's fields, with their types; an enum's or error's variants.

    The interface file opens the declaration on its own line, so the body
    arrives without a header; every line after the first one that is a field
    or a variant is one.
    """
    out = []
    for line in item["body"]:
        stripped = line.strip()
        if not stripped or stripped.startswith("//") or stripped == "}":
            continue
        if item["kind"] == "struct":
            match = FIELD.match(line)
            if match:
                out.append((match.group(1), match.group(2)))
        else:
            match = VARIANT.match(line)
            if match:
                out.append((match.group(1), (match.group(2) or "")[1:-1]))
    return out


def render_inline(text):
    escaped = html.escape(text)
    escaped = re.sub(r"\[`([^`]+)`\]", r"<code>\1</code>", escaped)
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)


def link(text):
    """A doc comment as HTML: paragraphs, inline code, fenced examples."""
    out, paragraph, fence = [], [], None

    def flush():
        if paragraph:
            out.append("<p>%s</p>" % render_inline(" ".join(paragraph)))
            paragraph.clear()

    for line in text:
        if line.strip().startswith("```"):
            if fence is None:
                flush()
                fence = []
            else:
                out.append(
                    '<pre class="eg"><code>%s</code></pre>'
                    % html.escape("\n".join(fence))
                )
                fence = None
            continue
        if fence is not None:
            fence.append(line)
        elif not line.strip():
            flush()
        else:
            paragraph.append(line.strip())
    flush()
    if fence:
        out.append('<pre class="eg"><code>%s</code></pre>' % html.escape("\n".join(fence)))
    return "\n".join(out)


def anchor(short, name):
    """A stable id for one item. Case is kept: `Kind` the enum and `kind` the
    preset are two items, and so are `Options` and `options`."""
    slug = re.sub(r"[^A-Za-z0-9]+", "-", name).strip("-")
    return "api-%s-%s" % (short, slug)


def decl_text(item, decls):
    """The declaration as its source writes it; the interface file's text is
    the fallback for what no source line declares, such as the derives."""
    source = decls.get(item["name"])
    if source:
        return strip_modifier(source)
    return strip_modifier(" ".join(line.strip() for line in item["body"]))


def card(short, item, decls, docs, opened=False):
    name = item["name"]
    body = []
    doc = docs.get(name)
    if not doc and item["kind"] == "impl":
        trait, _, target = name[len("impl ") :].partition(" for ")
        doc = ["`%s` implements `%s`." % (target.strip(), trait.strip())]
    if doc:
        body.append(link(doc))
    if item["kind"] in ("struct", "enum", "suberror"):
        fields = []
        for member, shape in members_of(item):
            notes = docs.get("%s.%s" % (name, member))
            fields.append(
                '<dt><code>%s</code>%s</dt><dd>%s</dd>'
                % (
                    html.escape(member),
                    '<span class="ty">%s</span>' % html.escape(shape) if shape else "",
                    link(notes) if notes else "",
                )
            )
        if fields:
            body.append('<dl class="api-fields">%s</dl>' % "".join(fields))
    if item["kind"] == "trait":
        # The members of a trait are part of its declaration, not items of
        # their own, so the whole declaration is printed for an implementor.
        # The interface file carries the body alone: its opening line is the
        # one `decl_text` already holds.
        members = "\n".join(
            line for line in item["body"] if line.strip() not in ("", "}")
        )
        body.insert(
            0,
            '<pre class="eg"><code>%s</code></pre>'
            % html.escape("%s {\n%s\n}" % (strip_modifier(decl_text(item, decls)), members)),
        )
    summary = '<span class="pm">+</span><span class="decl">%s</span>' % html.escape(
        decl_text(item, decls)
    )
    badge = BADGE.get(item["kind"])
    if badge and item["kind"] not in ("fn", "let"):
        summary += '<span class="badge">%s</span>' % badge
    return '<details class="api-item" id="%s"%s><summary>%s</summary><div class="desc">%s</div></details>' % (
        anchor(short, name),
        " open" if opened else "",
        summary,
        "".join('<div class="api-doc">%s</div>' % part for part in body),
    )


def derived_line(short, owner, names):
    parts = [
        '<code id="%s">%s</code>' % (anchor(short, owner + "::" + name), name)
        for name in names
    ]
    return '<p class="derived">Derived: %s.</p>' % ", ".join(parts)


def collect(folder):
    items = items_of(folder)
    docs = docs_of(folder)
    decls = decls_of(folder)
    types = [i for i in items if i["kind"] in ("struct", "enum", "suberror")]
    methods = {}
    for item in items:
        if item["kind"] == "method":
            methods.setdefault(item["owner"], []).append(item)
    return items, docs, decls, types, methods


def render(packages):
    chunks = ["<!-- written by scripts/gen_api.py; edit that, not this -->"]
    expected = []
    for _full, folder, short, tag, blurb in packages:
        items, docs, decls, types, methods = collect(folder)
        expected.extend(anchor(short, item["name"]) for item in items)
        groups = [
            ("Types", sorted(types, key=lambda i: i["name"].lower())),
            (
                "Functions",
                sorted(
                    (i for i in items if i["kind"] == "fn"),
                    key=lambda i: i["name"].lower(),
                ),
            ),
            (
                "Values",
                sorted(
                    (i for i in items if i["kind"] == "let"),
                    key=lambda i: i["name"].lower(),
                ),
            ),
            (
                "Traits",
                sorted(
                    (i for i in items if i["kind"] == "trait"),
                    key=lambda i: i["name"].lower(),
                )
                + sorted(
                    (i for i in items if i["kind"] in ("impl", "using")),
                    key=lambda i: i["name"].lower(),
                ),
            ),
        ]
        package_name = "moonurl" if short == "moonurl" else "moonurl/" + short
        chunks.append('<div class="pkg">')
        chunks.append(
            '<h3>%s <span class="tag">%s</span></h3>\n<p class="note">%s</p>'
            % (html.escape(package_name), html.escape(tag), html.escape(blurb))
        )
        first = True
        for title, group in groups:
            if not group:
                continue
            chunks.append('<h4 class="api-group">%s</h4>' % title)
            for item in group:
                chunks.append(card(short, item, decls, docs, first))
                first = False
                if item["kind"] not in ("struct", "enum", "suberror"):
                    continue
                owned = sorted(
                    methods.get(item["name"], []), key=lambda m: m["name"].lower()
                )
                derived = [
                    m["name"].split("::", 1)[1]
                    for m in owned
                    if m["name"].split("::", 1)[1] in DERIVED
                ]
                if derived:
                    chunks.append(derived_line(short, item["name"], sorted(derived)))
                for method in owned:
                    if method["name"].split("::", 1)[1] in DERIVED:
                        continue
                    chunks.append(card(short, method, decls, docs))
        chunks.append("</div>")
    listed = len(set(expected))
    lead = (
        '<p class="api-stat">%d public items in %d packages: everything the '
        "interface files publish. The <code>equal</code>, <code>not_equal</code> "
        "and <code>to_repr</code> that <code>Eq</code> and <code>Debug</code> "
        "bring are named at the foot of the type that carries them.</p>"
        % (listed, len(packages))
    )
    body = "\n".join(chunks)
    found = set(re.findall(r'id="(api-[^"]+)"', body))
    if found != set(expected):
        missing = sorted(set(expected) - found)
        extra = sorted(found - set(expected))
        raise SystemExit(
            "the reference and the interface files disagree\n  missing: %s\n  extra: %s"
            % (", ".join(missing) or "-", ", ".join(extra) or "-")
        )
    return lead + "\n" + body, listed


def main():
    check = "--check" in sys.argv[1:]
    body, listed = render(PACKAGES)
    page = PAGE.read_text(encoding="utf-8")
    if BEGIN not in page or END not in page:
        raise SystemExit("docs/index.html has no %s ... %s region" % (BEGIN, END))
    head, rest = page.split(BEGIN, 1)
    _, tail = rest.split(END, 1)
    new = head + BEGIN + "\n" + body + "\n" + END + tail
    if new == page:
        print("docs/index.html: %d public items, all listed" % listed)
        return 0
    if check:
        print("docs/index.html is out of date: run scripts/gen_api.py")
        return 1
    PAGE.write_text(new, encoding="utf-8", newline="\n")
    print("docs/index.html: %d public items, all listed" % listed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
