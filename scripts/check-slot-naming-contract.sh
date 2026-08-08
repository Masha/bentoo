#!/usr/bin/env bash
# Assert that net-libs/nodejs and app-eselect/eselect-nodejs agree on where a
# slot lives.
#
# The two halves of the multi-slot design never reference each other: the ebuild
# installs into NODE_SLOT_DIR, and the eselect module discovers slots by globbing
# the filesystem. Nothing enforces that the path one writes is the path the other
# looks for. Rename either and both packages still pass their own checks --
# pkgcheck stays clean, the module's own test suite stays green -- while every
# installed slot becomes invisible to `eselect nodejs list`, and `/usr/bin/node`
# silently stops being managed.
#
# This script is that missing link. It extracts the literals from both sources
# and checks they agree, for every major in the tree and every multilib libdir.
#
# Usage: bash scripts/check-slot-naming-contract.sh
# Exit:  0 all pairs agree; 1 otherwise, naming what diverged.

set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# The module filename carries the eselect-nodejs major (nodejs.eselect-<N>), so it
# moves on every bump of that package: d8b541d78 renamed it -1 -> -2 and left this
# path pointing at a file that no longer existed, which made the script exit 1 on
# the missing file before it compared anything at all. A guard that hardcodes the
# name it is guarding is blind to exactly the failure it exists to catch, so glob
# for the module instead of naming a version.
shopt -s nullglob
modules=( "${repo}"/app-eselect/eselect-nodejs/files/nodejs.eselect-[0-9]* )
shopt -u nullglob
(( ${#modules[@]} )) || {
	echo "not found: ${repo}/app-eselect/eselect-nodejs/files/nodejs.eselect-<major>" >&2
	exit 1
}

# Highest major wins. More than one file means several eselect-nodejs versions
# coexist in the tree and only the newest is compared -- report that rather than
# narrowing the check in silence.
module=$(printf '%s\n' "${modules[@]}" | sort -V | tail -n1)
if (( ${#modules[@]} > 1 )); then
	echo "note: ${#modules[@]} module files present, comparing only $(basename "${module}")" >&2
fi
echo "module file  : ${module#"${repo}"/}"

shopt -s nullglob
ebuilds=( "${repo}"/net-libs/nodejs/nodejs-[0-9]*.ebuild )
shopt -u nullglob
(( ${#ebuilds[@]} )) || { echo "no versioned nodejs ebuild found" >&2; exit 1; }

MODULE="${module}" EBUILDS="${ebuilds[*]}" python3 - <<'PY'
import fnmatch
import os
import re
import sys

module = os.environ["MODULE"]
ebuilds = os.environ["EBUILDS"].split()

src = open(module, encoding="utf-8").read()

# Every glob the module uses to find a slot directory.
#
# Deliberately NOT anchored on "node-": a check that only recognises the name it
# already expects cannot detect a rename, which is the single failure this script
# exists to catch. Extract whatever path follows ${EROOT}, then verify the ebuild
# literal matches it. ${major} is a concrete major at run time, so it is
# normalised to * for matching purposes.
#
# Normalise first, extract second. A slot-discovery line can spell the major as
# "${major}" -- quotes and all -- so matching on raw text would stop at the quote
# and silently capture a truncated path. Collapse the variables to a plain glob,
# then take everything up to shell punctuation (these sit in `for d in ...; do`).
normalised = src.replace('"${major}"', "*").replace("${major}", "*")
globs = sorted({
    m.group(1)
    for m in re.finditer(r'"\$\{EROOT\}"(/usr/[^\s;&|)"\']*\*[^\s;&|)"\']*)', normalised)
})
if not globs:
    sys.exit(f"FAIL  no slot-discovery glob found in {module} -- did the module change shape?")

# The module discovers slots in two places (find_targets and slot_libdir) and
# both must agree with the ebuild. Fewer than two means the extraction missed
# one -- treat that as a failure rather than silently checking half the contract.
EXPECTED_GLOB_SITES = 2
if len(globs) < EXPECTED_GLOB_SITES:
    sys.exit(
        f"FAIL  found {len(globs)} discovery glob(s) in {module}, expected at least "
        f"{EXPECTED_GLOB_SITES} ({globs}) -- the module changed shape, or this "
        f"script's extraction no longer sees every site"
    )

# Every libdir a Gentoo profile can pick. The module's lib* wildcard has to
# cover whichever one $(get_libdir) resolves to on the target.
libdirs = ("lib", "lib32", "lib64", "libx32")

print(f"module globs : {globs}")
failed = False

for path in ebuilds:
    name = os.path.basename(path)
    body = open(path, encoding="utf-8").read()

    m = re.search(r'NODE_SLOT_DIR="([^"]*)"', body)
    if not m:
        print(f"FAIL  {name}: no NODE_SLOT_DIR assignment")
        failed = True
        continue
    literal = m.group(1)

    major = re.search(r"nodejs-(\d+)\.", name).group(1)

    # SLOT must be an unindented literal at column 0 -- the autoupdate engine
    # scrapes it with a regex anchored there and neither sources the ebuild nor
    # reads md5-cache, so an indented or computed value is invisible to it.
    slot_m = re.search(r'^SLOT="([^"]*)"', body, re.M)
    if not slot_m:
        print(
            f"FAIL  {name}: no unindented SLOT=\"...\" at column 0 "
            f"-- the autoupdate engine cannot scrape it"
        )
        failed = True
    elif slot_m.group(1) != major:
        # This is the check that replaces what $(ver_cut 1) used to guarantee:
        # copy an ebuild to a new major and forget this line, and it fires.
        print(
            f"FAIL  {name}: SLOT=\"{slot_m.group(1)}\" but the filename says "
            f"major {major} -- was this copied from another major?"
        )
        failed = True

    bad = [
        literal.replace("$(get_libdir)", d).replace("${SLOT}", major)
        for d in libdirs
        if not all(
            fnmatch.fnmatch(
                literal.replace("$(get_libdir)", d).replace("${SLOT}", major), g
            )
            for g in globs
        )
    ]
    if bad:
        print(f"FAIL  {name}: {literal} -> {bad} matches no module glob")
        failed = True
    else:
        print(f"PASS  {name}: {literal} (major {major}) matches every glob in {'/'.join(libdirs)}")

sys.exit(1 if failed else 0)
PY
