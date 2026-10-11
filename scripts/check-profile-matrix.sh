#!/usr/bin/env bash
# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
#
# Validate the composable system profiles: the base presets, the layers under
# profiles/{targets,features}, the contract that describes them
# (profiles/catalog.toml) and the /etc drop-in fragments under layers/.
#
# Requires bash >= 5 and Python >= 3.11 (the catalog is read with the stdlib
# `tomllib`, which first shipped in 3.11).
#
# WHAT IT IS FOR
#
# A bentoo system is one base preset plus optional layers, all plain Portage
# profiles; `bentoo profile` (app-portage/bentoolkit) reads the catalog and
# writes the `parent` file Portage resolves. Nothing else in this tree checks a
# profile: pkgcheck's ProfilesCheck needs its git addon, which crashes here. A
# layer can therefore name a parent that does not exist, a catalog entry can
# drift from its directory, or two layers can combine into a set Portage
# cannot resolve - and every one of those passes pkgcheck, merges cleanly and
# only breaks on a user's machine. This script is that missing gate.
#
# STRICTLY READ-ONLY
#
# It reads the tree and prints a report. It never writes into the tree it
# validates, never touches the host's /etc/portage, and leaves nothing behind:
# its one scratch directory is created with `mktemp -d` under ${TMPDIR:-/tmp}
# and removed by an EXIT trap, on the passing path and on every failing one.
#
# HOW IT CLASSIFIES
#
#   --static            the catalog against its schema and the tree, and the
#                       layers/ fragment rules. Seconds; never calls Portage.
#   --staged            --static, then resolution of every layer the index
#                       touches over the 4 reference presets (the hook mode).
#   --full              --static, then every layer alone, every pair and the
#                       largest allowed selection over every preset (manual).
#   --compose <preset-id> [layer-id...]
#                       the composition validity rule: print the ordered
#                       `parent` lines, or name the broken rule.
#   --self-test         the unit fixtures (top-level *.bats of
#                       scripts/tests/check-profile-matrix/, never integration/)
#                       on scratch trees: no checkout, no ::gentoo.
#
# The tree is ${BENTOO_TREE:-the git toplevel of the checkout holding this
# script}; every tree read and every git call goes through it.
#
# Prerequisites are checked PER MODE, and the first missing one is named with
# exit 2: every mode needs bash >= 5 and python3 with tomllib; --staged and
# --full also need emerge, portageq and /var/db/repos/gentoo; --self-test also
# needs bats. --static, --compose and --self-test never read
# /var/db/repos/gentoo, so they run on a host without Portage.
#
# The script is ONE self-contained file - no sourced helper, no separate .py,
# the TOML is read by an embedded python3 heredoc - because the self-test
# copies it and runs the copy alone.
#
# WHAT THIS STILL MISSES - stated here rather than discovered later
#
#   * --self-test does not cut the network off: the fixtures simply never
#     reach for it. Isolating it (unshare -n) needs user namespaces, which a
#     container or a hardened host may refuse, and a guard that fails there is
#     a guard people learn to skip.
#   * "--static and --compose never read /var/db/repos/gentoo" is held by
#     construction (neither mode references the path), not by a test: the
#     directory cannot be made to disappear without root, and its path is not
#     overridable on purpose.
#   * A `parent` line naming another repository (`gentoo:...`, as every
#     preset's first line does) is not resolved by --static: that would read
#     /var/db/repos/gentoo. Only this repo's lines (`:path`, `bentoo:path`,
#     relative, absolute) are checked; --staged and --full resolve the rest
#     through Portage.
#
# Exit status:
#   0  everything compared is clean
#   1  at least one gap, each one named
#   2  NOTHING WAS COMPARED: bad usage, a missing prerequisite, no input, or an
#      internal error. An empty report reads exactly like a clean one; this
#      code exists so the two are never confused
#   130 / 143  interrupted by INT / TERM (the scratch directory is still removed)
#
# Results go to stdout; every message that leads to exit 2 goes to stderr.

set -Eeuo pipefail

### where things live ################################################

SCRIPT_PATH=$(cd -- "$(dirname -- "$0")" && pwd -P)/$(basename -- "$0")
SCRIPT_DIR=${SCRIPT_PATH%/*}
SUITE_DIR=$SCRIPT_DIR/tests/check-profile-matrix
GENTOO_REPO=/var/db/repos/gentoo
PROG=check-profile-matrix

# Set by resolve_tree / make_workdir, only in the modes that need them.
TREE=""
WORK=""

### exit status and signals ##########################################
#
# INTERNAL status convention, mapped to the public one in ONE place (on_exit):
#   0      clean
#   $GAP   a gap (3, never 1). A function reports a gap with `return "$GAP"`.
#   2      nothing compared
# 1 is reserved for what a FAILING COMMAND returns (mkdir, cp, a crashed
# child): errexit carries that status out raw, and if gaps were 1 too an
# internal failure would read as a gap. on_exit turns every status other than
# 0, $GAP and 2 into 2, "internal error", and $GAP into the public 1.
# The embedded Python uses the same 3 for the same reason (see catalog_py).

GAP=3
CHILD=""    # pid of the running run_child, for on_signal
SIGNALED="" # 130 / 143 once INT / TERM arrived
ERR_AT=""   # where the last command failed, for the internal-error message

# on_exit STATUS -- the EXIT trap: remove the scratch directory, then map the
# internal status to the public one.
on_exit() {
	# errexit off: a failing printf here must not leave with its own status.
	set +e
	local rc=$1
	if [ -n "$WORK" ] && ! rm -rf -- "$WORK"; then
		printf '%s: cannot remove the scratch dir %s\n' "$PROG" "$WORK" >&2
		rc=2
	fi
	if [ -n "$SIGNALED" ]; then exit "$SIGNALED"; fi
	case $rc in
	0) exit 0 ;;
	"$GAP") exit 1 ;;
	2) exit 2 ;;
	esac
	printf '%s: internal error: exit %s%s\n' "$PROG" "$rc" "${ERR_AT:+ at $ERR_AT}" >&2
	exit 2
}

# on_signal STATUS -- INT/TERM: stop the running child (its whole process
# group, see run_child), wait for it so nothing writes into $WORK after it is
# removed, and exit through on_exit. INT also sends TERM: a background child
# of a script may have been started with INT ignored.
on_signal() {
	set +e
	SIGNALED=$1
	if [ -n "$CHILD" ]; then
		kill -TERM -- "-$CHILD" 2>/dev/null || kill -TERM -- "$CHILD" 2>/dev/null || true
		wait "$CHILD" 2>/dev/null || true
	fi
	exit "$SIGNALED"
}

install_traps() {
	trap 'on_exit "$?"' EXIT
	trap 'on_signal 130' INT
	trap 'on_signal 143' TERM
	trap 'ERR_AT="line $LINENO: $BASH_COMMAND"' ERR
}

# run_child CMD [ARG...] -- run a long-running child (bats; emerge in --staged
# and --full) and return its status. Bash runs a trap only once the FOREGROUND
# command has finished, so a foreground child would hold INT/TERM off until it
# exits. Here the child runs in the background and this shell `wait`s, which
# returns as soon as a trapped signal arrives. `set -m` gives the child its own
# process group, so on_signal stops the child and everything it forked (bats
# runs one process per file and per test); stdin is /dev/null because a
# background process group that reads the terminal would be stopped.
run_child() {
	local rc=0
	set -m
	"$@" </dev/null &
	CHILD=$!
	set +m
	wait "$CHILD" || rc=$?
	CHILD=""
	return "$rc"
}

### command line #####################################################

MODE=""
COMPOSE_ARGS=()

usage() {
	cat <<'EOF'
Usage: check-profile-matrix.sh MODE

Modes:
  --static                             catalog schema + fragment rules (seconds)
  --staged                             --static, then resolve the layers the index touches
  --full                               --static, then resolve every combination (hours)
  --compose <preset-id> [layer-id...]  print the composed parent lines, or the broken rule
  --self-test                          run the unit fixtures (no tree, no ::gentoo)
  -h, --help                           this text

Tree: $BENTOO_TREE, else the git toplevel of the checkout holding the script.
Exit: 0 clean - 1 a gap - 2 nothing compared (bad usage, missing prerequisite)
EOF
}

# bad_usage MESSAGE -- name what was wrong, print the usage, exit 2.
bad_usage() {
	printf '%s: %s\n' "$PROG" "$1" >&2
	usage >&2
	exit 2
}

parse_args() {
	(($#)) || bad_usage 'no mode given'
	case $1 in
	-h | --help)
		usage
		exit 0
		;;
	--static | --staged | --full | --self-test)
		MODE=$1
		(($# == 1)) || bad_usage "$1 takes no argument, got: ${*:2}"
		;;
	--compose)
		MODE=$1
		(($# >= 2)) || bad_usage '--compose needs a preset id'
		COMPOSE_ARGS=("${@:2}")
		;;
	*)
		bad_usage "unknown mode: $1"
		;;
	esac
}

### prerequisites ####################################################

# missing WHAT -- name the first missing prerequisite of $MODE and exit 2.
missing() {
	printf '%s: missing prerequisite: %s (needed by %s)\n' "$PROG" "$1" "$MODE" >&2
	exit 2
}

# check_prerequisites -- per mode, in a fixed order, first miss wins.
check_prerequisites() {
	if ((BASH_VERSINFO[0] < 5)); then
		missing "bash >= 5 (running ${BASH_VERSION})"
	fi
	command -v python3 >/dev/null 2>&1 ||
		missing 'python3 (>= 3.11, for tomllib)'
	python3 -I -c 'import tomllib' >/dev/null 2>&1 ||
		missing 'python3 with tomllib (Python >= 3.11)'

	case $MODE in
	--staged | --full)
		[ -d "$GENTOO_REPO" ] || missing "$GENTOO_REPO (the ::gentoo tree)"
		command -v emerge >/dev/null 2>&1 || missing emerge
		command -v portageq >/dev/null 2>&1 || missing portageq
		;;
	--self-test)
		command -v bats >/dev/null 2>&1 || missing bats
		;;
	esac
}

### tree and scratch space ###########################################

# resolve_tree -- set TREE from $BENTOO_TREE or the script's git checkout.
# Only the modes that read the tree call it: --self-test runs from a lone
# copy of this file that sits in no repository.
resolve_tree() {
	if [ -n "${BENTOO_TREE:-}" ]; then
		TREE=$BENTOO_TREE
	elif ! TREE=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null); then
		printf '%s: no tree: BENTOO_TREE is unset and %s is not in a git checkout\n' \
			"$PROG" "$SCRIPT_DIR" >&2
		exit 2
	fi
	[ -d "$TREE/profiles" ] || {
		printf '%s: no tree: %s has no profiles/ directory\n' "$PROG" "$TREE" >&2
		exit 2
	}
}

# make_workdir -- the run's ONE scratch directory; on_exit removes it on every
# exit, signals included.
make_workdir() {
	WORK=$(mktemp -d -t "$PROG.XXXXXX") || {
		printf '%s: cannot create scratch dir\n' "$PROG" >&2
		exit 2
	}
}

### the embedded catalog reader ######################################

# catalog_py SUBCOMMAND [ARG...] -- run the embedded Python on the tree and
# return 0 clean, $GAP a gap, 2 nothing compared.
#
# The Python side reports a gap with 3, a status the interpreter never
# produces on its own: a SyntaxError, an uncaught exception or
# `sys.exit("msg")` all exit 1, and a bad interpreter invocation exits 2. So
# 0 -> 0, 3 -> $GAP, and ANYTHING else -> 2: a crash can never read as a gap
# or as a pass.
#
# The program itself arrives on stdin (the heredoc): data for it must come
# through argv or files in $WORK, never through a pipe into this function.
catalog_py() {
	local rc=0
	# -I: isolated mode -- no PYTHON* variables and no cwd on sys.path, so a
	# stray tomllib.py next to wherever the hook runs cannot stand in for the
	# standard library and make the check pass without checking anything.
	python3 -I - "$TREE" "$@" <<'PY' || rc=$?
import os
import re
import sys
import tomllib
from pathlib import Path

CATALOG = "profiles/catalog.toml"

# Exit statuses (see catalog_py in the shell above): 0 clean, GAP a gap,
# NOTHING nothing compared. GAP is 3 because the interpreter exits 1 by
# itself on any crash, and that must never read as a gap.
CLEAN = 0
NOTHING = 2
GAP = 3


def load_catalog(tree, stream=None):
    """Return the parsed catalog, or exit: NOTHING when absent, GAP when
    invalid. A gap is printed on `stream` (stdout by default)."""
    stream = stream or sys.stdout
    path = tree / CATALOG
    try:
        raw = path.read_bytes()
    except FileNotFoundError:
        # Nothing can be compared: a message that leads to exit 2 goes to stderr.
        print(f"catalog: missing: {CATALOG}", file=sys.stderr)
        sys.exit(NOTHING)
    try:
        return tomllib.loads(raw.decode("utf-8"))
    except UnicodeDecodeError as err:
        print(f"catalog: encoding: {CATALOG}: not UTF-8 ({err.reason})", file=stream)
        sys.exit(GAP)
    except tomllib.TOMLDecodeError as err:
        # str(err) carries "(at line N, column M)" on every Python >= 3.11;
        # the .lineno/.msg attributes only exist from 3.14 on.
        print(f"catalog: toml: {CATALOG}: {err}", file=stream)
        sys.exit(GAP)
    except RecursionError:
        # tomllib recurses per nesting level: a catalog nested thousands deep
        # is a broken catalog, not a crash of this script.
        print(f"catalog: toml: {CATALOG}: nested too deeply to parse", file=stream)
        sys.exit(GAP)


# --- schema 1 (design.md "Data Models") ---------------------------------------

ATTRIBUTES = ("init", "multilib", "desktop", "hardened", "selinux", "llvm")
TOP_KEYS = ("schema", "attributes", "types", "preset", "layer")
TYPE_KEYS = ("rank", "exclusive")
PRESET_KEYS = ("id", "status") + ATTRIBUTES
PRESET_STATUS = ("stable", "dev", "exp")
LAYER_KEYS = (
    "id", "type", "description", "base", "conflicts", "requires", "has_files",
    "services",
)
SERVICE_KEYS = ("openrc", "systemd")
# A layer directory is a directory under one of these that holds `eapi`...
LAYER_ROOTS = ("targets", "features")
# ...except this one: every preset inherits it, nobody selects it.
NOT_A_LAYER = "features/branding"
PROFILES_DESC = "profiles/profiles.desc"
ARCH = "amd64"


# TOML values arrive as Python values in which True == 1 and 1.0 == 1, so
# every type test and every value comparison below goes through type(), never
# isinstance() or a bare ==: `multilib = 1` must not pass as `true`.
def is_int(value):
    return type(value) is int


def is_bool(value):
    return type(value) is bool


def is_str(value):
    return type(value) is str


def is_table(value):
    return type(value) is dict


def is_array(value):
    return type(value) is list


def same(a, b):
    return type(a) is type(b) and a == b


def show(value):
    """Render a value the way it is written in TOML, for a failure line."""
    if is_bool(value):
        return "true" if value else "false"
    if is_str(value):
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if is_array(value):
        return "[" + ", ".join(show(v) for v in value) + "]"
    if is_table(value):
        return "{" + ", ".join(f"{k} = {show(v)}" for k, v in value.items()) + "}"
    return str(value)


# One id segment: what a profile directory name is made of. It excludes the
# empty segment (//, leading or trailing /) and every control character, so
# an id can neither escape the tree nor forge a second output line.
SEGMENT = re.compile(r"[A-Za-z0-9._+-]+")


def valid_id(value):
    """An id is a plain relative path under profiles/: every segment a
    SEGMENT, none of them '.' or '..', nothing absolute. It is joined onto the
    tree, so this also keeps every read inside it."""
    if not is_str(value) or not value:
        return False
    return all(
        SEGMENT.fullmatch(p) and p not in (".", "..") for p in value.split("/")
    )


def one_line(text):
    """Escape every control character, so one failure is always one line."""
    return "".join(
        c if c.isprintable() else repr(c)[1:-1] for c in str(text)
    )


def parent_lines(path):
    """The lines of a `parent` file as Portage reads them (grabfile): blank
    lines dropped, a '#' item ends the line, whitespace normalised."""
    lines = []
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        items = []
        for item in raw.split():
            if item.startswith("#"):
                break
            items.append(item)
        if items:
            lines.append(" ".join(items))
    return lines


class CatalogCheck:
    """Every --static catalog rule. Each failure is one line
    `catalog: <rule>: <subject>[: <detail>]`, collected, never raised: the run
    reports all of them before it exits."""

    def __init__(self, tree, catalog):
        self.tree = tree
        self.profiles = tree / "profiles"
        self.catalog = catalog
        self.failures = []
        self.allowed = {}  # attribute -> its [attributes] array, when well-formed
        self.types = set()  # every [types.<name>]
        self.presets = []  # (subject, entry) of every [[preset]] table
        self.layers = []  # (subject, entry) of every [[layer]] table
        self.ids = []  # (kind, id) of every entry whose id is valid
        self.layer_dirs = []  # every layer directory found on disk
        self.walked_symlinks = set()  # symlinks the layer walk already reported

    def fail(self, rule, subject, detail=""):
        line = f"catalog: {rule}: {one_line(subject)}"
        self.failures.append(f"{line}: {one_line(detail)}" if detail else line)

    def run(self):
        self.top_level()
        self.attributes()
        self.type_table()
        for subject, entry in self.presets:
            self.preset(subject, entry)
        for subject, entry in self.layers:
            self.layer(subject, entry)
        self.duplicate_ids()
        self.layer_dirs = self.layer_directories()
        self.directories_of_ids()  # R4.3
        self.entries_of_directories()  # R4.2
        self.desc_matches_presets()  # R4.4
        self.layer_references()  # R4.6, plus requires
        self.parents()
        self.fragments()  # R5.1-R5.5, R4.3 through layers/
        return self.failures

    # --- shape: keys, types, values (R4.1, R4.5) ----------------------------

    def unknown_keys(self, subject, table, known):
        for key in table:
            if key not in known:
                self.fail("unknown-key", subject, key)

    def entries(self, kind):
        """[[kind]] as a list of (subject, table); the subject is the id when
        it is a non-empty string, else the entry's position."""
        value = self.catalog.get(kind, [])
        if not is_array(value) or not all(is_table(e) for e in value):
            self.fail("wrong-type", "top level", f"{kind} must be an array of tables ([[{kind}]])")
            return []
        out = []
        for n, entry in enumerate(value, 1):
            ident = entry.get("id")
            out.append((ident if valid_id(ident) else f"[[{kind}]] #{n}", entry))
        return out

    def top_level(self):
        self.unknown_keys("top level", self.catalog, TOP_KEYS)
        if "schema" not in self.catalog:
            self.fail("schema", "top level", "schema is missing, expected schema = 1")
        elif not same(self.catalog["schema"], 1):
            self.fail("schema", "top level", f"schema = {show(self.catalog['schema'])}, expected schema = 1")
        self.presets = self.entries("preset")
        self.layers = self.entries("layer")

    def attributes(self):
        table = self.catalog.get("attributes")
        if table is None:
            self.fail("required-key", "top level", "attributes")
            return
        if not is_table(table):
            self.fail("wrong-type", "top level", "attributes must be a table ([attributes])")
            return
        self.unknown_keys("[attributes]", table, ATTRIBUTES)
        for attr in ATTRIBUTES:
            if attr not in table:
                self.fail("required-key", "[attributes]", attr)
            elif not is_array(table[attr]) or not table[attr]:
                self.fail("wrong-type", "[attributes]", f"{attr} must be a non-empty array of allowed values")
            elif not all(is_str(v) or is_bool(v) for v in table[attr]):
                self.fail("wrong-type", "[attributes]", f"{attr} values must be strings or booleans, got {show(table[attr])}")
            else:
                values = table[attr]
                dupes = [v for i, v in enumerate(values) if any(same(v, w) for w in values[:i])]
                for value in dupes:
                    self.fail("duplicate-value", "[attributes]", f"{attr} lists {show(value)} more than once")
                self.allowed[attr] = values

    def type_table(self):
        table = self.catalog.get("types")
        if table is None:
            self.fail("required-key", "top level", "types")
            return
        if not is_table(table):
            self.fail("wrong-type", "top level", "types must hold tables ([types.<name>])")
            return
        for name, spec in table.items():
            self.types.add(name)
            subject = f"types.{name}"
            if not is_table(spec):
                self.fail("wrong-type", subject, "must be a table with rank and exclusive")
                continue
            self.unknown_keys(subject, spec, TYPE_KEYS)
            if "rank" not in spec:
                self.fail("required-key", subject, "rank")
            elif not is_int(spec["rank"]):
                self.fail("wrong-type", subject, f"rank must be an integer, got {show(spec['rank'])}")
            if "exclusive" not in spec:
                self.fail("required-key", subject, "exclusive")
            elif not is_bool(spec["exclusive"]):
                self.fail("wrong-type", subject, f"exclusive must be a boolean, got {show(spec['exclusive'])}")

    def entry_id(self, kind, subject, entry):
        if "id" not in entry:
            self.fail("required-key", subject, "id")
        elif not valid_id(entry["id"]):
            self.fail("bad-id", subject, f"id = {show(entry['id'])} is not a relative path under profiles/")
        else:
            self.ids.append((kind, entry["id"]))

    def attribute_value(self, subject, attr, value, where):
        """`value` must be one of the [attributes] values of `attr`; skipped
        when [attributes] itself lacks `attr` (already reported there)."""
        allowed = self.allowed.get(attr)
        if allowed is not None and not any(same(value, a) for a in allowed):
            self.fail(
                "attribute-value", subject,
                f"{where}{attr} = {show(value)} is not in [attributes] {attr} = {show(allowed)}",
            )

    def preset(self, subject, entry):
        self.unknown_keys(subject, entry, PRESET_KEYS)
        self.entry_id("preset", subject, entry)
        if "status" not in entry:
            self.fail("required-key", subject, "status")
        elif not any(same(entry["status"], s) for s in PRESET_STATUS):
            self.fail(
                "status", subject,
                f"status = {show(entry['status'])}, expected one of {show(list(PRESET_STATUS))}",
            )
        for attr in ATTRIBUTES:
            if attr not in entry:
                self.fail("required-key", subject, attr)
            else:
                self.attribute_value(subject, attr, entry[attr], "")

    def id_array(self, subject, entry, key):
        value = entry.get(key, [])
        if not is_array(value) or not all(is_str(v) for v in value):
            self.fail("wrong-type", subject, f"{key} must be an array of layer ids")

    def layer(self, subject, entry):
        self.unknown_keys(subject, entry, LAYER_KEYS)
        self.entry_id("layer", subject, entry)
        ident = entry.get("id")
        if valid_id(ident) and (ident.split("/")[0] not in LAYER_ROOTS or ident == NOT_A_LAYER):
            self.fail(
                "not-a-layer", ident,
                f"a [[layer]] id lives under profiles/{{{','.join(LAYER_ROOTS)}}} and is not {NOT_A_LAYER}",
            )
        if "type" not in entry:
            self.fail("required-key", subject, "type")
        elif not is_str(entry["type"]) or entry["type"] not in self.types:
            self.fail("unknown-type", subject, f"type = {show(entry['type'])} is not a [types] name")
        if "description" not in entry:
            self.fail("required-key", subject, "description")
        elif not is_str(entry["description"]) or not entry["description"].strip():
            self.fail("wrong-type", subject, "description must be a non-empty string")
        if "base" in entry:
            self.base(subject, entry["base"])
        self.id_array(subject, entry, "conflicts")
        self.id_array(subject, entry, "requires")
        if "has_files" in entry and not is_bool(entry["has_files"]):
            self.fail("wrong-type", subject, f"has_files must be a boolean, got {show(entry['has_files'])}")
        if "services" in entry:
            self.services(subject, entry["services"])

    def base(self, subject, base):
        if not is_table(base):
            self.fail("wrong-type", subject, "base must be a table of attribute = [allowed values]")
            return
        for attr, values in base.items():
            if attr not in ATTRIBUTES:
                self.fail("unknown-attribute", subject, f"base key {attr} is not an [attributes] name")
            elif not is_array(values):
                self.fail("wrong-type", subject, f"base {attr} must be an array of allowed values")
            else:
                for value in values:
                    self.attribute_value(subject, attr, value, "base ")

    def services(self, subject, services):
        if not is_array(services) or not all(is_table(s) for s in services):
            self.fail("wrong-type", subject, "services must be an array of { openrc = ..., systemd = ... }")
            return
        for n, service in enumerate(services):
            where = f"services[{n}]"
            for key in service:
                if key not in SERVICE_KEYS:
                    self.fail("unknown-key", subject, f"{where} key {key}")
            for key in SERVICE_KEYS:
                if key not in service:
                    self.fail("services", subject, f"{where} lacks {key}")
                elif not is_str(service[key]) or not service[key]:
                    self.fail("services", subject, f"{where} {key} must be a non-empty string")

    # --- identity: ids, directories, profiles.desc, conflicts ---------------

    def duplicate_ids(self):
        seen = set()
        reported = set()
        for _, ident in self.ids:
            if ident in seen and ident not in reported:
                self.fail("duplicate-id", ident, "declared more than once")
                reported.add(ident)
            seen.add(ident)

    def unique_ids(self, kind=None):
        """The valid ids in first-occurrence order, optionally of one kind."""
        out = []
        for k, ident in self.ids:
            if (kind is None or k == kind) and ident not in out:
                out.append(ident)
        return out

    def symlink_in(self, rel):
        """The first path below profiles/ on the way to `rel` that is a
        symlink, or None. Nothing is read through a symlink: it could point
        out of the tree."""
        path = self.profiles
        for part in rel.split("/"):
            path = path / part
            if path.is_symlink():
                return path.relative_to(self.profiles).as_posix()
        return None

    def directories_of_ids(self):
        """R4.3: every catalog id names a directory under profiles/ holding eapi."""
        for ident in self.unique_ids():
            directory = self.profiles / ident
            link = self.symlink_in(ident)
            if link is not None:
                if link not in self.walked_symlinks:
                    self.fail("symlink", ident, f"profiles/{link} is a symlink; a profile directory must be a real directory")
            elif not directory.is_dir():
                self.fail("no-directory", ident, f"profiles/{ident} does not exist")
            elif not (directory / "eapi").is_file():
                self.fail("no-eapi", ident, f"profiles/{ident} holds no eapi file")

    def layer_directories(self):
        """Every layer directory, sorted: under profiles/{targets,features},
        holding eapi, not features/branding. A directory without eapi is a
        grouping folder (features/hardware) and needs no exemption list."""
        def unreadable(err):
            # A directory os.walk cannot list would hide an undeclared layer:
            # that is an internal error (exit 2), never a silent pass.
            raise err

        found = []
        for root in LAYER_ROOTS:
            if (self.profiles / root).is_symlink():
                self.fail("symlink", root, f"profiles/{root} is a symlink")
                continue
            if not (self.profiles / root).exists():
                continue  # no layer of this root yet: nothing to walk
            if not (self.profiles / root).is_dir():
                self.fail("not-a-directory", root, f"profiles/{root} is not a directory")
                continue
            for dirpath, dirnames, filenames in os.walk(self.profiles / root, onerror=unreadable):
                dirnames.sort()
                for name in list(dirnames):
                    if os.path.islink(os.path.join(dirpath, name)):
                        rel = Path(dirpath, name).relative_to(self.profiles).as_posix()
                        self.fail("symlink", rel, f"profiles/{rel} is a symlink; a layer must be a real directory")
                        self.walked_symlinks.add(rel)
                        dirnames.remove(name)
                rel = Path(dirpath).relative_to(self.profiles).as_posix()
                if "eapi" in filenames and rel != NOT_A_LAYER:
                    found.append(rel)
        return found

    def entries_of_directories(self):
        """R4.2: every layer directory has a [[layer]] entry."""
        declared = set(self.unique_ids("layer"))
        for rel in self.layer_dirs:
            if rel not in declared:
                self.fail("no-entry", rel, f"profiles/{rel} holds eapi but has no [[layer]] entry")

    def desc_presets(self):
        """The amd64 lines of profiles.desc as {id: status-or-None} in file
        order, or None when the file is absent. Comments, blank lines and other
        arches are skipped; fields are split on any whitespace."""
        path = self.tree / PROFILES_DESC
        if not path.is_file():
            return None
        out = {}
        for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
            fields = raw.split("#", 1)[0].split()
            if len(fields) >= 2 and fields[0] == ARCH and fields[1] not in out:
                out[fields[1]] = fields[2] if len(fields) >= 3 else None
        return out

    def desc_matches_presets(self):
        """R4.4: [[preset]] ids == the amd64 lines of profiles.desc, both ways."""
        desc = self.desc_presets()
        if desc is None:
            self.fail("no-profiles-desc", PROFILES_DESC, "missing, the presets cannot be compared")
            return
        presets = self.unique_ids("preset")
        for ident in presets:
            if ident not in desc:
                self.fail("preset-not-in-desc", ident, f"[[preset]] entry with no {ARCH} line in {PROFILES_DESC}")
        for ident in desc:
            if ident not in presets:
                self.fail("desc-not-in-catalog", ident, f"{ARCH} line in {PROFILES_DESC} with no [[preset]] entry")
        # One fact, one source: eselect reads the status from profiles.desc and
        # `bentoo profile` reads it from the catalog, so the two must agree.
        for subject, entry in self.presets:
            ident = entry.get("id")
            if not valid_id(ident) or ident not in desc:
                continue
            if desc[ident] is None:
                self.fail("desc-status", ident, f"the {ARCH} line in {PROFILES_DESC} has no status column")
            elif is_str(entry.get("status")) and entry["status"] != desc[ident]:
                self.fail(
                    "status-mismatch", ident,
                    f"catalog status = {show(entry['status'])} but {PROFILES_DESC} says {desc[ident]}",
                )

    def layer_references(self):
        """R4.6: a conflict is declared by both layers, and conflicts and
        requires name declared layers. A one-sided conflict names both."""
        refs = {}
        for subject, entry in self.layers:
            if not valid_id(entry.get("id")):
                continue  # already reported as bad-id: no cascading lines
            if subject in refs:
                continue  # a duplicate id, already reported: judge the first
            refs[subject] = {}
            for key in ("conflicts", "requires"):
                value = entry.get(key, [])
                refs[subject][key] = [v for v in value if is_str(v)] if is_array(value) else []
        for a, lists in refs.items():
            for key in ("conflicts", "requires"):
                if a in lists[key]:
                    # One reading for every implementation: a layer naming
                    # itself is a catalog error, never a rule to interpret.
                    self.fail(f"self-{key[:-1] if key == 'conflicts' else 'require'}", a, f"lists itself in {key}")
            for b in lists["conflicts"]:
                if b not in refs:
                    self.fail("conflict-unknown", a, f"conflicts with {b}, which has no [[layer]] entry")
                elif a not in refs[b]["conflicts"]:
                    self.fail("conflict-one-sided", a, f"lists {b} in conflicts, but {b} does not list {a}")
            for b in lists["requires"]:
                if b not in refs:
                    self.fail("requires-unknown", a, f"requires {b}, which has no [[layer]] entry")

    def layout_conf(self):
        """`key = value` pairs of metadata/layout.conf ({} when absent)."""
        path = self.tree / "metadata" / "layout.conf"
        out = {}
        if path.is_file():
            for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
                line = raw.split("#", 1)[0]
                if "=" in line:
                    key, value = line.split("=", 1)
                    out[key.strip()] = value.strip()
        return out

    def repo_names(self):
        """(own name or None, master names) as Portage reads them: the name
        from layout.conf repo-name first, then profiles/repo_name."""
        layout = self.layout_conf()
        own = layout.get("repo-name") or None
        repo_file = self.profiles / "repo_name"
        if own is None and repo_file.is_file():
            own = repo_file.read_text(encoding="utf-8", errors="replace").strip() or None
        return own, set(layout.get("masters", "").split())

    def resolve_parent(self, directory, line, own, masters):
        """(target, None) for a line of this repository, (None, None) for a
        master's line (out of scope: --static never reads another repo), or
        (None, reason) when the line is a gap."""
        if line.startswith("/"):
            return None, "an absolute path is host-specific, never a line of this repository"
        if ":" in line:
            name, path = line.split(":", 1)
            if name and name != own:
                if name in masters:
                    return None, None
                if own is None:
                    return None, f"repository {name!r} is not a master, and this repository's own name is unknown"
                return None, f"repository {name!r} is neither this repository ({own}) nor a master"
            target = os.path.join(self.profiles, path)
        else:
            target = os.path.join(directory, line)
        target = os.path.normpath(target)
        root = os.path.normpath(self.profiles)
        if os.path.commonpath([root, target]) != root:
            return None, "leaves the repository"
        return target, None

    def parents(self):
        """A `parent` file is optional (absent = no inheritance). When present,
        every line must resolve, inside this repository's profiles/, to a
        directory: `:path` and `<this repo>:path` (under profiles/), or a path
        relative to the profile directory. A master's line (`gentoo:...`) is out
        of scope: --static never reads another repository. Any other repository
        name, an absolute path, or a path leaving profiles/ is a gap."""
        own, masters = self.repo_names()
        dirs = set(self.unique_ids()) | set(self.layer_dirs)
        if (self.profiles / NOT_A_LAYER).is_dir():
            dirs.add(NOT_A_LAYER)
        for rel in sorted(dirs):
            if self.symlink_in(rel) is not None:
                continue  # already reported; nothing is read through a symlink
            directory = self.profiles / rel
            parent = directory / "parent"
            if parent.is_symlink():
                self.fail("symlink", rel, "the parent file is a symlink")
                continue
            if not parent.is_file():
                continue
            lines = parent_lines(parent)
            if not lines:
                self.fail("parent", rel, "the parent file is empty (Portage rejects it)")
            for line in lines:
                target, reason = self.resolve_parent(directory, line, own, masters)
                if reason is not None:
                    self.fail("parent", rel, f"{line}: {reason}")
                elif target is None:
                    continue  # a master's line
                elif os.path.realpath(target) != target:
                    self.fail("parent", rel, f"{line} goes through a symlink")
                elif not os.path.isdir(target):
                    self.fail("parent", rel, f"{line} resolves to nothing")
                elif target == os.path.normpath(self.profiles) or not os.path.isfile(os.path.join(target, "eapi")):
                    # `:` is profiles/ itself and `..` can be a grouping folder:
                    # both exist, neither is a profile directory.
                    self.fail("parent", rel, f"{line} is not a profile directory (no eapi)")


# --- fragments: layers/<id>/etc/**/<x>.d/<file> (design.md C4) ---------------


def _fragments(self):
    """R5.1-R5.5: every file under layers/ belongs to a declared layer, sits
    directly in a `<x>.d` directory below that layer's etc/, carries `bentoo-`
    in its name, is a regular file with no execute bit and no symlink on the
    way; a layer has a tree exactly when it declares has_files = true."""
    root = self.tree / "layers"
    if root.is_symlink():
        self.fail("symlink", "layers", "layers/ is a symlink")
        return
    layer_ids = {}
    for _, entry in self.layers:
        ident = entry.get("id")
        if valid_id(ident) and ident not in layer_ids:
            layer_ids[ident] = entry.get("has_files") is True

    def owner(parts):
        # The longest declared id that is a whole-segment prefix: nvidia
        # never owns layers/.../nvidia-legacy/.
        for n in range(len(parts), 0, -1):
            ident = "/".join(parts[:n])
            if ident in layer_ids:
                return ident, parts[n:]
        return None, parts

    def unknown_subject(parts):
        # The id a tree would belong to: the path up to its etc/ (or up to the
        # file's directory when there is no etc/).
        cut = parts.index("etc") if "etc" in parts[:-1] else len(parts) - 1
        return "/".join(parts[:cut]) or parts[0]

    def unreadable(err):
        raise err

    trees = set()
    unknown = set()
    if root.is_dir():
        for dirpath, dirnames, filenames in os.walk(root, onerror=unreadable):
            dirnames.sort()
            here = Path(dirpath)
            for name in list(dirnames):
                path = here / name
                rel = path.relative_to(root).as_posix()
                if path.is_symlink():
                    # Above or inside a layer's tree alike: never followed.
                    self.fail("symlink", f"layers/{rel}", "a symlinked directory under layers/ is never followed")
                    dirnames.remove(name)
            for name in sorted(filenames):
                path = here / name
                parts = path.relative_to(root).as_posix().split("/")
                ident, inner = owner(parts)
                if ident is None:
                    if "etc" in parts[:-1]:
                        unknown.add(unknown_subject(parts))
                    else:
                        self.fail(
                            "fragment-location", f"layers/{'/'.join(parts)}",
                            "outside any layers/<id>/etc/ of a declared layer",
                        )
                    continue
                trees.add(ident)
                self.fragment(f"layers/{'/'.join(parts)}", path, inner)
    for ident in sorted(unknown):
        self.fail("unknown-tree", ident, f"layers/{ident} has no [[layer]] entry (features/branding is not a layer)")
    for ident in layer_ids:
        # A tree is the files a layer owns, not a directory: git never commits
        # an empty directory, and a nested id's directory holds its child's
        # tree. So the verdict is the same here as on a clean clone.
        has_tree = ident in trees
        if has_tree and not layer_ids[ident]:
            self.fail("has-files", ident, f"layers/{ident} exists but the entry does not declare has_files = true")
        elif layer_ids[ident] and not has_tree:
            self.fail("has-files", ident, f"has_files = true but layers/{ident} holds no fragment")


def _fragment(self, shown, path, inner):
    """One file of a declared layer's tree; `inner` is its path below
    layers/<id>/."""
    if path.is_symlink():
        self.fail("symlink", shown, "a fragment must be a regular file, not a symlink")
        return
    if not path.is_file():
        self.fail("not-a-file", shown, "a fragment must be a regular file")
        return
    directory = inner[-2] if len(inner) >= 3 else ""
    if inner[0] != "etc" or len(inner) < 3 or not (directory.endswith(".d") and len(directory) > 2):
        self.fail("fragment-location", shown, "must sit directly in a <name>.d directory below layers/<id>/etc/")
    if "bentoo-" not in inner[-1]:
        self.fail("fragment-name", shown, "the file name must contain bentoo-")
    if path.stat().st_mode & 0o111:
        self.fail("fragment-mode", shown, "a fragment must not carry an execute bit")


CatalogCheck.fragments = _fragments
CatalogCheck.fragment = _fragment


def static(tree):
    failures = CatalogCheck(tree, load_catalog(tree)).run()
    for line in failures:
        print(line)
    return GAP if failures else CLEAN


# --- the composition validity rule (design.md "Data Models") --------------------


def compose(tree, preset_id, layer_args):
    """Print the ordered parent lines of a valid selection (CLEAN), or name
    every broken rule (GAP). The catalog must pass the --static checks first:
    a parent composed over a broken catalog would be a guess (NOTHING)."""
    # For --compose, exit 1 means "this selection breaks a rule". A catalog
    # that does not even parse is not that: it goes to stderr as exit 2.
    try:
        catalog = load_catalog(tree, stream=sys.stderr)
    except SystemExit as stop:
        if stop.code == GAP:
            print("compose: the catalog fails --static; nothing composed", file=sys.stderr)
            return NOTHING
        raise
    failures = CatalogCheck(tree, catalog).run()
    if failures:
        print("compose: the catalog fails --static; nothing composed:", file=sys.stderr)
        for line in failures:
            print(line, file=sys.stderr)
        return NOTHING

    presets = {e["id"]: e for e in catalog.get("preset", [])}
    layers = {}
    order = {}
    for n, entry in enumerate(catalog.get("layer", [])):
        if entry["id"] not in layers:
            layers[entry["id"]] = entry
            order[entry["id"]] = n
    types = catalog["types"]

    problems = []
    if preset_id not in presets:
        what = "a layer, not a preset" if preset_id in layers else "not a [[preset]] in the catalog"
        problems.append(f"compose: unknown-preset: {one_line(preset_id)}: {what}")
    selected = []
    for ident in layer_args:
        if ident in selected:
            continue  # a layer given twice is one layer
        if ident not in layers:
            what = "a preset, and a selection holds exactly one" if ident in presets else "not a [[layer]] in the catalog"
            problems.append(f"compose: unknown-layer: {one_line(ident)}: {what}")
            continue
        selected.append(ident)
    if problems:
        for line in problems:
            print(line)
        return GAP

    # R4.12: type rank (an integer, compared as one), then declaration order.
    selected.sort(key=lambda i: (types[layers[i]["type"]]["rank"], order[i]))

    # R4.7: at most one layer per exclusive type.
    by_type = {}
    for ident in selected:
        by_type.setdefault(layers[ident]["type"], []).append(ident)
    for name in sorted(by_type, key=lambda t: types[t]["rank"]):
        if types[name]["exclusive"] and len(by_type[name]) > 1:
            problems.append(
                f"compose: exclusive: {name}: at most one {name} per system, got {', '.join(by_type[name])}"
            )
    # R4.8: no selected pair declares a conflict (checked both ways: --static
    # already guarantees the declaration is symmetric).
    for i, a in enumerate(selected):
        for b in selected[i + 1:]:
            if b in layers[a].get("conflicts", []) or a in layers[b].get("conflicts", []):
                problems.append(f"compose: conflict: {a} conflicts with {b}")
    # R4.9: every requires is selected (whole ids: games-vr is not games).
    for ident in selected:
        for need in layers[ident].get("requires", []):
            if need not in selected:
                problems.append(f"compose: requires: {ident} requires {need}, which is not selected")
    # R4.10: every base constraint holds for the preset's attributes.
    if preset_id in presets:
        preset = presets[preset_id]
        for ident in selected:
            for attr, allowed in layers[ident].get("base", {}).items():
                if not any(same(preset[attr], a) for a in allowed):
                    problems.append(
                        f"compose: base: {ident} needs {attr} in {show(allowed)}, "
                        f"preset {preset_id} has {attr} = {show(preset[attr])}"
                    )
    if problems:
        for line in problems:
            print(line)
        return GAP
    print(f"bentoo:{preset_id}")
    for ident in selected:
        print(f"bentoo:{ident}")
    return CLEAN


def main(argv):
    # Resolved once, here: every later comparison (commonpath, realpath) needs
    # an absolute, physical root, whatever relative or symlinked path the
    # caller handed in.
    tree = Path(os.path.realpath(argv[1]))
    sub = argv[2]
    if sub == "static":
        return static(tree)
    if sub == "compose":
        return compose(tree, argv[3], argv[4:])
    print(f"internal error: unknown subcommand {sub!r}", file=sys.stderr)
    return NOTHING


try:
    status = main(sys.argv)
except Exception as err:  # a crash must never read as a gap
    print(f"internal error: {type(err).__name__}: {err}", file=sys.stderr)
    sys.exit(NOTHING)
# A subcommand that forgot its return (None), or returned False, 1 or any
# other value, must not pass through: None and False would exit 0, 1 would be
# folded into "internal error" only by accident. bool is excluded by name
# because it is an int subclass (False == 0, True == 1).
if type(status) is not int or status not in (CLEAN, NOTHING, GAP):
    print(f"internal error: {sys.argv[2]!r} returned {status!r}", file=sys.stderr)
    status = NOTHING
sys.exit(status)
PY
	case $rc in
	0) return 0 ;;
	3) return "$GAP" ;;
	2) return 2 ;;
	esac
	printf '%s: internal error: the catalog reader exited %d\n' "$PROG" "$rc" >&2
	return 2
}

### modes ############################################################

run_static() { catalog_py static; }

# Placeholders: the behaviour arrives with later tasks. Each says so and exits
# 2 ("nothing compared"), never 0, so an unfinished mode cannot pass a commit.
not_yet() {
	printf '%s: %s is not implemented yet (%s)\n' "$PROG" "$MODE" "$1" >&2
	return 2
}

run_compose() { catalog_py compose "$@"; }
run_staged() { not_yet 'task 5'; }
run_full() { not_yet 'task 5'; }

# run_self_test -- the top-level *.bats of the suite next to this script, never
# integration/ (it reads the real tree and Portage) and never -r. bats gets a
# scratch BENTOO_TREE so no case can fall back to the checkout, and a run that
# counted zero tests fails: zero assertions is not a pass.
run_self_test() {
	local -a files=()
	local f count rc=0

	for f in "$SUITE_DIR"/*.bats; do
		if [ -f "$f" ]; then files+=("$f"); fi
	done
	if ((${#files[@]} == 0)); then
		printf '%s: nothing compared: no *.bats in %s\n' "$PROG" "$SUITE_DIR" >&2
		return 2
	fi

	mkdir -- "$WORK/tree" || {
		printf '%s: cannot create the scratch tree %s\n' "$PROG" "$WORK/tree" >&2
		return 2
	}
	export BENTOO_TREE=$WORK/tree
	export CHECK_PROFILE_MATRIX=$SCRIPT_PATH

	if ! count=$(bats --count "${files[@]}"); then
		printf '%s: bats could not count the tests in %s\n' "$PROG" "$SUITE_DIR" >&2
		return 2
	fi
	if ! [[ $count =~ ^[0-9]+$ ]] || ((count == 0)); then
		printf '%s: nothing compared: bats reports %s tests in %s\n' \
			"$PROG" "${count:-no}" "$SUITE_DIR" >&2
		return 2
	fi

	run_child bats "${files[@]}" || rc=$?
	if ((rc != 0)); then
		printf '%s: --self-test failed: bats exited %d\n' "$PROG" "$rc" >&2
		return "$GAP"
	fi
	return 0
}

### main #############################################################

main() {
	install_traps
	parse_args "$@"
	check_prerequisites
	case $MODE in
	--static | --staged | --full | --compose) resolve_tree ;;
	esac
	make_workdir

	# The mode runs as main's LAST command, never as the left side of || or &&
	# nor as an `if` condition: in those positions bash ignores errexit for the
	# whole function body, and a failing step inside the mode would go
	# unnoticed. Its status leaves through errexit or main's return, and
	# on_exit maps it to the public one.
	case $MODE in
	--static) run_static ;;
	--staged) run_staged ;;
	--full) run_full ;;
	--compose) run_compose "${COMPOSE_ARGS[@]}" ;;
	--self-test) run_self_test ;;
	esac
}

main "$@"
