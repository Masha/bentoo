#!/usr/bin/env python3
# Spdx-License-Identifier: GPL-2.0-or-later
# Drop-in replacement for third_party/dawn/tools/generate-sources-gn.py.
#
# Upstream's script runs Tint's source generator, written in Go, through a
# toolchain DEPS fetches from CIPD into
# third_party/dawn/tools/golang/<platform>/bin/go. Release tarballs ship no
# such binary, so ninja dies with:
#
#   FileNotFoundError: [Errno 2] No such file or directory:
#     '.../third_party/dawn/tools/golang/linux-amd64/bin/go'
#
# Pointing it at a system Go does not help either: third_party/dawn/go.mod
# requires ~70 external modules and the tarball carries no vendor/ directory,
# so `go run` would need network access, which the build sandbox denies.
#
# It does not need to run at all. Every file the generator emits is already
# checked into the tarball under third_party/dawn/src/tint/, in a 1:1 path
# mapping with the ${root_gen_dir}/src/tint/... outputs the GN action
# declares. This script copies them instead of regenerating them.
#
# Measured on 151.0.7922.71: the real Go generator was run against this tree
# and its output diffed against the checked-in copies. All 27 files are
# byte-identical except for the year on the first line, which the generator
# stamps from the current date (tarball: 2024, run: 2026). No code differs.
#
# The file list is read from src/tint/generated_sources.gni - the same list GN
# declares as the action's outputs - so a version bump that adds or drops a
# generated file needs no edit here. A file that is listed but not checked in
# aborts the build immediately, instead of letting ninja fail later with a
# missing output and no explanation.
import os
import re
import shutil
import sys

DAWN_ROOT = os.path.realpath(os.path.join(os.path.dirname(__file__), ".."))
SOURCES_GNI = os.path.join(DAWN_ROOT, "src", "tint", "generated_sources.gni")

# "${root_gen_dir}/src/tint/lang/core/enums.cc",  ->  src/tint/lang/core/enums.cc
ENTRY_RE = re.compile(r'"\$\{root_gen_dir\}/([^"]+)"')


def generated_paths():
    """Return the output paths, relative to the Dawn root, as GN declares them."""
    try:
        with open(SOURCES_GNI, encoding="utf-8") as gni_file:
            gni = gni_file.read()
    except OSError as err:
        sys.exit(f"cannot read {SOURCES_GNI}: {err}")

    # Only the tint_generated_sources list. The tint_generation_dependencies
    # list that follows it holds the .def/.tmpl inputs, not outputs.
    block = re.search(r"tint_generated_sources\s*=\s*\[(.*?)\]", gni, re.DOTALL)
    if not block:
        sys.exit(f"{SOURCES_GNI}: no tint_generated_sources list found")

    return ENTRY_RE.findall(block.group(1))


def main() -> int:
    if len(sys.argv) != 2:
        sys.exit(f"usage: {os.path.basename(sys.argv[0])} <gen-dir>")

    # Same contract as upstream: argv[1] is the gen dir relative to the build
    # directory, which is the working directory ninja runs the action from.
    gen_dir = os.path.join(os.getcwd(), sys.argv[1])

    paths = generated_paths()
    if not paths:
        sys.exit("tint_generated_sources is empty - refusing to produce nothing")

    for rel_path in paths:
        source = os.path.join(DAWN_ROOT, rel_path)
        if not os.path.isfile(source):
            sys.exit(
                f"{rel_path}: listed as a generated source but not checked in; "
                "this Chromium version needs the Go generator"
            )
        destination = os.path.join(gen_dir, rel_path)
        os.makedirs(os.path.dirname(destination), exist_ok=True)
        # copyfile, not copy2: the destination must come out newer than the
        # .def/.tmpl inputs or ninja considers the action perpetually dirty.
        shutil.copyfile(source, destination)

    return 0


if __name__ == "__main__":
    sys.exit(main())
