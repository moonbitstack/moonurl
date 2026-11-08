"""Compile the MoonBit blocks of docs/index.html against this module's source.

The guide on the site prints the same examples the README does, and a page that
nothing compiles drifts away from the library it describes. Blocks are read in
page order, the way a reader meets them, so a later block may use a name an
earlier one defined. Shell commands (`moon add ...`) are skipped.

Usage: python scripts/check_page_snippets.py [--moon moon] [file ...]
"""

import argparse
import html
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import check_snippets

BLOCK = re.compile(r"<pre><code>(.*?)</code></pre>", re.S)
SHELL = re.compile(r"\s*moon (add|run)\b")


def blocks(path):
    text = path.read_text(encoding="utf-8")
    for m in BLOCK.finditer(text):
        body = html.unescape(m.group(1))
        if SHELL.match(body):
            continue
        yield text[: m.start(1)].count("\n") + 1, body


def compile_blocks(items, module, src, aliases, moon):
    """Check one package's worth of blocks; return the failures as (line, message)."""
    code, spans = check_snippets.program(items)
    used = set(re.findall(r"@([a-z_][a-z0-9_]*)\.", code))
    imports = sorted(
        {aliases[a] for a in used if a in aliases}
        | {f"moonbitlang/core/{a}" for a in used if a not in aliases and a in check_snippets.CORE}
        | {
            f"moonbitlang/core/{check_snippets.NESTED[a]}"
            for a in used
            if a not in aliases and a in check_snippets.NESTED
        }
    )
    pkg = src / "snippet_check"
    shutil.rmtree(pkg, ignore_errors=True)
    pkg.mkdir(parents=True)
    head = "import {\n" + "".join(f'  "{p}",\n' for p in imports) + "}\n" if imports else ""
    (pkg / "moon.pkg").write_text(head, encoding="utf-8", newline="\n")
    (pkg / "snippets.mbt").write_text(code, encoding="utf-8", newline="\n")
    try:
        r = subprocess.run(
            [moon, "check", "--target", "all", pkg.relative_to(ROOT).as_posix()],
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    finally:
        shutil.rmtree(pkg, ignore_errors=True)
    out = r.stdout + r.stderr
    bad = set()
    for m in re.finditer(
        r"Error: \[\d+\][^\n]*\n[^\n]*snippets\.mbt:(\d+):\d+[^\n]*\n(?:[^\n]*\n){0,6}?[^\n]*╰[─┬ ]*(?:─ )?([^\n]+)",
        out,
    ):
        at = int(m.group(1))
        line = next((b for s, e, b in spans if s <= at <= e), None)
        bad.add((line, m.group(2).strip()))
    if r.returncode and not bad:
        bad.add((None, out.strip().splitlines()[-1] if out.strip() else "moon check failed"))
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--moon", default="moon")
    ap.add_argument("files", nargs="*")
    args = ap.parse_args()
    module, src, deps = check_snippets.module_info()
    subprocess.run([args.moon, "update"], cwd=ROOT, capture_output=True)
    aliases = check_snippets.packages(module, src, deps)
    files = [Path(f) for f in args.files] or [ROOT / "docs" / "index.html"]
    failed = 0
    for file in files:
        file = file if file.is_absolute() else ROOT / file
        if not file.exists():
            continue
        items = list(blocks(file))
        bad = sorted(compile_blocks(items, module, src, aliases, args.moon))
        for line, message in bad:
            print(f"{file.relative_to(ROOT).as_posix()}:{line}: {message}")
        failed += len(bad)
        if not bad:
            print(f"{file.relative_to(ROOT).as_posix()}: {len(items)} blocks compile")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
