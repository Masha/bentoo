#!/usr/bin/env python3
# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
"""Offline stand-in for `cargo about generate --format=json`.

Upstream's flake feeds cargo-about's JSON into contrib/licenses.mjs, which
builds the "Licenses" page of the GUI.  cargo-about is not packaged, so this
emits the subset of its schema that licenses.mjs reads:

    {"licenses": [{"id", "name", "text",
                   "used_by": [{"crate": {"name", "version", "repository"}}]}]}

Input is `cargo metadata --format-version 1 --filter-platform <host>` on
stdin; --filter-platform drops the Windows/Apple/Android-only crates that are
never linked into the Linux binaries.  Every crate reachable from the
workspace root is listed with the license files it ships.
"""

import json
import sys
from pathlib import Path

LICENSE_PREFIXES = ("license", "licence", "copying", "unlicense", "notice")


def license_texts(pkg: dict) -> str:
    root = Path(pkg["manifest_path"]).parent
    files = []
    if pkg.get("license_file"):
        files.append(root / pkg["license_file"])
    files.extend(
        p
        for p in sorted(root.iterdir())
        if p.is_file() and p.name.lower().startswith(LICENSE_PREFIXES)
    )
    seen = set()
    texts = []
    for path in files:
        resolved = path.resolve()
        if resolved in seen or not resolved.is_file():
            continue
        seen.add(resolved)
        texts.append(resolved.read_text(encoding="utf-8", errors="replace").strip())
    return "\n\n".join(texts)


def main() -> int:
    meta = json.load(sys.stdin)
    members = set(meta["workspace_members"])
    nodes = {n["id"]: n for n in meta["resolve"]["nodes"]}
    packages = {p["id"]: p for p in meta["packages"]}

    reachable = set()
    stack = [meta["resolve"]["root"]]
    while stack:
        pkg_id = stack.pop()
        if pkg_id in reachable:
            continue
        reachable.add(pkg_id)
        stack.extend(nodes[pkg_id]["dependencies"])

    grouped = {}
    for pkg_id in sorted(reachable - members):
        pkg = packages[pkg_id]
        expr = pkg.get("license") or "NOASSERTION"
        text = license_texts(pkg) or (
            f"{pkg['name']} {pkg['version']} is distributed under {expr}; "
            "the crate ships no license text."
        )
        entry = grouped.setdefault(
            (expr, text), {"id": expr, "name": expr, "text": text, "used_by": []}
        )
        entry["used_by"].append(
            {
                "crate": {
                    "name": pkg["name"],
                    "version": pkg["version"],
                    "repository": pkg.get("repository"),
                }
            }
        )

    json.dump({"licenses": list(grouped.values())}, sys.stdout, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
