#!/usr/bin/env bash
# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
#
# Integration test for app-eselect/eselect-nodejs.
#
# WHAT IT PROVES
#
# Two of this module's failure modes are *silent*: when they break, nothing
# errors out, and the damage only surfaces much later somewhere else. Neither
# is catchable by reading the code, so both get pinned here.
#
#   1. Ordering. Lexicographically "node10" sorts before "node9", so a plain
#      `sort` in find_targets makes "the highest installed slot" the wrong slot
#      - `eselect nodejs update` would activate node9 on a box that also has
#      node26, with no message at all. Assertions (a), (g) and (i).
#
#   2. Directory replacement. Given a real directory at /usr/include/node (the
#      leftover of the unslotted net-libs/nodejs:0, whose src_install did
#      `dodir /usr/include/node/deps/{v8,uv}`), `ln` neither replaces it nor
#      refuses: it descends and creates /usr/include/node/node. node-gyp then
#      resolves the wrong headers and says nothing. NOTE that `ln -sfn` does
#      NOT fix this - verified on GNU coreutils 9.11, -n only helps when the
#      destination is already a *symlink* to a directory. The module therefore
#      removes such a directory explicitly in remove_symlinks(). Assertion (c)
#      pins that removal.
#
# KNOWN COVERAGE LIMIT
#
# No assertion here can single out ln's -n flag, and none pretends to. do_set
# and do_cleanup both call remove_symlinks() before create_symlinks(), so the
# destination is already gone by the time ln runs and -n never gets to matter.
# Measured: downgrading -sfn to -sf on its own keeps every assertion green;
# doing it *and* disabling the symlink removal turns (h) red. The two are
# independent guarantees of the same outcome, which is what (h) checks.
#
# HOW IT WORKS
#
# It fabricates a throwaway EROOT under $TMPDIR holding node-{9,10,26} stubs,
# installs the module into a throwaway HOME, and drives the *real* /usr/bin/
# eselect binary against it with --root=. Driving the real binary (rather than
# sourcing the module by hand) is deliberate: it exercises `inherit`, the
# do_action dispatcher and the describe_* surface exactly as production does.
#
# Nothing outside the temp tree is written. Assertion (n) proves it by
# fingerprinting the host's /etc/profile.env and /etc/env.d before and after.
#
# TWO HAZARDS THIS SCRIPT DEFUSES - both hit in practice, both silent-ish
#
#   PACKAGE_MANAGER=paludis is a SAFETY MEASURE, not a preference. do_set ends
#   with `do_action env update noldconfig`, and eselect's env_update() shells
#   out to portage's `env-update` with NO root argument - eselect never exports
#   ROOT. So a naive `eselect --root=<fabricated> nodejs set node26`
#   regenerates the *developer's own* /etc/profile.env. Under
#   PACKAGE_MANAGER=paludis that call returns 127 and env.eselect falls back to
#   its own shell implementation, which is correctly ${EROOT}-scoped. A test
#   that mutates the developer's /etc is a defect, not a test.
#
#   The fabricated root needs a tmp/ directory. env.eselect's
#   create_profile_env() does `mktemp "${ROOT}/tmp/profile.XXXXXX"`; without it
#   `set` dies with "Couldn't create temporary file!" and exits 250 even though
#   the switch itself succeeded.
#
# USAGE
#
#   bash scripts/test-eselect-nodejs.sh
#
#   ESELECT_NODEJS_MODULE=<path>   drive a different copy of the module. This
#                                  is what makes mutation testing possible
#                                  without ever editing the file in the repo:
#                                  copy it to a temp dir, break one line, point
#                                  this variable at the copy, and watch the
#                                  matching assertion go red.
#   ESELECT_NODEJS_KEEP_TMP=1      keep the fabricated tree for inspection.
#                                  Off by default; the tree is always removed
#                                  otherwise, including on failure.
#
# Exit status: 0 when every assertion passes, 1 when any fails, 2 on a missing
# precondition (no eselect, no module).

set -euo pipefail

# Every glob below is either a listing or a "does the slot ship this" probe,
# and an unmatched pattern must expand to nothing rather than to itself.
shopt -s nullglob

### preconditions ###################################################

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)

# Located relative to this script, never by absolute path, so the test runs
# from any checkout.
MODULE=${ESELECT_NODEJS_MODULE:-${REPO_ROOT}/app-eselect/eselect-nodejs/files/nodejs.eselect-1}

if ! command -v eselect >/dev/null 2>&1; then
	printf 'precondition failed: eselect is not installed\n' >&2
	exit 2
fi
if [[ ! -f ${MODULE} ]]; then
	printf 'precondition failed: no eselect module at %s\n' "${MODULE}" >&2
	exit 2
fi
if ! bash -n "${MODULE}" 2>/dev/null; then
	printf 'precondition failed: %s is not syntactically valid bash\n' \
		"${MODULE}" >&2
	bash -n "${MODULE}" || true
	exit 2
fi

### scratch tree ####################################################

WORK=$(mktemp -d "${TMPDIR:-/tmp}/eselect-nodejs-test.XXXXXX")
ROOTFS="${WORK}/root"
FAKE_HOME="${WORK}/home"

# Invoked by the EXIT trap below, so the fabricated tree goes away on a pass,
# on a failed assertion and on an unexpected error alike. ShellCheck's
# reachability pass does not follow trap handlers past the explicit `exit` at
# the end of this script, hence the disable.
# shellcheck disable=SC2329
cleanup() {
	local status=$?
	if [[ -n ${ESELECT_NODEJS_KEEP_TMP:-} ]]; then
		printf '\nkept fabricated tree: %s\n' "${WORK}"
	else
		rm -rf -- "${WORK}"
	fi
	return "${status}"
}
trap cleanup EXIT

mkdir -p -- "${FAKE_HOME}/.eselect/modules"
cp -- "${MODULE}" "${FAKE_HOME}/.eselect/modules/nodejs.eselect"

### the managed paths, restated ####################################
#
# Deliberately a second, independent copy of the module's NODEJS_LINKS list:
# if the module ever drops a managed path, the harness still looks for it and
# the assertion goes red. Relative to the fabricated root.
MANAGED_RELPATHS=(
	"usr/bin/node"
	"usr/bin/npm"
	"usr/bin/npx"
	"usr/include/node"
	"usr/share/bash-completion/completions/npm"
)
MANAGED_ENVFILE="etc/env.d/50nodejs"

### assertion bookkeeping ###########################################

ASSERT_TOTAL=0
FAILURES=()
ASSERT_CONTEXT=""

# q <string>
# Render a value for display: newlines flattened, empty made visible.
q() {
	local s=${1//$'\n'/ \\n }
	printf '%s' "${s:-(empty)}"
}

# assert_eq <id> <description> <expected> <actual>
# Never aborts: a later assertion may still carry information, and each phase
# rebuilds its own root anyway. The script's exit status carries the verdict.
assert_eq() {
	local id=$1 desc=$2 expected=$3 actual=$4

	ASSERT_TOTAL=$(( ASSERT_TOTAL + 1 ))

	if [[ ${actual} == "${expected}" ]]; then
		printf '  [PASS] (%s) %s\n' "${id}" "${desc}"
		ASSERT_CONTEXT=""
		return 0
	fi

	printf '  [FAIL] (%s) %s\n' "${id}" "${desc}"
	printf '         expected: %s\n' "$(q "${expected}")"
	printf '         observed: %s\n' "$(q "${actual}")"
	if [[ -n ${ASSERT_CONTEXT} ]]; then
		printf '         context : %s\n' "$(q "${ASSERT_CONTEXT}")"
	fi
	FAILURES+=( "($(printf '%s' "${id}")) ${desc} | expected: $(q "${expected}") | observed: $(q "${actual}")" )
	ASSERT_CONTEXT=""
	return 0
}

section() {
	printf '\n%s\n' "$*"
}

### fabricated root #################################################

# make_slot <major> [nonpm]
# One installed slot, laid out exactly the way net-libs/nodejs:<major> does:
# everything under /usr/lib64/node-<major>/. "nonpm" reproduces a slot built
# with USE=-npm, which ships neither npm, npx nor the completion.
make_slot() {
	local major=$1 variant=${2:-full}
	local prefix="${ROOTFS}/usr/lib64/node-${major}"

	mkdir -p -- "${prefix}/bin" "${prefix}/include/node" \
		"${prefix}/share/man/man1" \
		"${prefix}/share/bash-completion/completions"

	printf '#!/bin/sh\necho v%s.0.0\n' "${major}" >"${prefix}/bin/node"
	chmod +x -- "${prefix}/bin/node"

	printf '#define NODE_MAJOR_VERSION %s\n' "${major}" \
		>"${prefix}/include/node/node_version.h"
	printf '.TH NODE 1 "slot %s"\n' "${major}" \
		>"${prefix}/share/man/man1/node.1"

	[[ ${variant} == nonpm ]] && return 0

	printf '#!/bin/sh\necho npm from slot %s\n' "${major}" >"${prefix}/bin/npm"
	printf '#!/bin/sh\necho npx from slot %s\n' "${major}" >"${prefix}/bin/npx"
	chmod +x -- "${prefix}/bin/npm" "${prefix}/bin/npx"
	printf '# npm completion, slot %s\n' "${major}" \
		>"${prefix}/share/bash-completion/completions/npm"
	return 0
}

# build_root <major>...
# A fresh fabricated EROOT. Each phase calls this so that a failure in one
# phase cannot contaminate the next.
build_root() {
	rm -rf -- "${ROOTFS}"
	# tmp/ is required by env.eselect - see the header.
	mkdir -p -- "${ROOTFS}/tmp" "${ROOTFS}/etc/env.d" "${ROOTFS}/usr/bin" \
		"${ROOTFS}/usr/include" "${ROOTFS}/usr/share/man/man1" \
		"${ROOTFS}/usr/share/bash-completion/completions"

	local major
	for major in "$@"; do
		make_slot "${major}"
	done
}

### driving the module ##############################################

MODULE_OUT=""
MODULE_ERR=""
MODULE_RC=0

# run_module [-b] <action> [args...]
# Drives the real eselect binary. -b adds --brief. Captures stdout, stderr and
# the exit status separately: do_show's contract is specifically about which
# stream carries what.
run_module() {
	local -a globals=( "--colour=no" "--root=${ROOTFS}" )
	if [[ ${1:-} == -b ]]; then
		globals+=( "--brief" )
		shift
	fi

	local errfile="${WORK}/stderr.out"

	MODULE_RC=0
	MODULE_OUT=$(
		HOME="${FAKE_HOME}" \
		PACKAGE_MANAGER=paludis \
		eselect "${globals[@]}" nodejs "$@" 2>"${errfile}"
	) || MODULE_RC=$?
	MODULE_ERR=$(<"${errfile}")
	rm -f -- "${errfile}"
	return 0
}

# module_context
# What the last invocation printed - attached to a failing assertion so a red
# never has to be reproduced by hand.
module_context() {
	printf 'rc=%d; stdout=[%s]; stderr=[%s]' "${MODULE_RC}" \
		"$(q "${MODULE_OUT}")" "$(q "${MODULE_ERR}")"
}

### observing the fabricated tree ###################################

# yesno <command>...
yesno() {
	if "$@"; then printf 'yes'; else printf 'no'; fi
}

# dir_entries <dir>
dir_entries() {
	local dir=$1 entry names=""
	for entry in "${dir}"/*; do
		names+="${entry##*/} "
	done
	names=${names% }
	printf '%s' "${names:-(empty)}"
}

# path_state <path>
# What actually sits at a managed path, in one line. The whole point of (c) is
# that the two interesting shapes - "symlink into the slot" and "real directory
# with a link buried inside it" - must be told apart, so both are spelled out.
path_state() {
	local path=$1 target resolved

	if [[ -L ${path} ]]; then
		target=$(readlink -- "${path}")
		if resolved=$(realpath -e -- "${path}" 2>/dev/null); then
			printf 'symlink %s => %s' "${target}" "${resolved#"${ROOTFS}"}"
		else
			printf 'DANGLING symlink %s' "${target}"
		fi
	elif [[ -d ${path} ]]; then
		printf 'REAL DIRECTORY containing: %s' "$(dir_entries "${path}")"
	elif [[ -e ${path} ]]; then
		printf 'regular file'
	else
		printf 'absent'
	fi
}

# dangling_summary
# Managed paths that are symlinks to something that no longer exists.
dangling_summary() {
	local -a found=()
	local rel path

	for rel in "${MANAGED_RELPATHS[@]}"; do
		path="${ROOTFS}/${rel}"
		[[ -L ${path} && ! -e ${path} ]] && found+=( "/${rel}" )
	done
	for path in "${ROOTFS}/usr/share/man/man1"/node.1*; do
		[[ -L ${path} && ! -e ${path} ]] && found+=( "${path#"${ROOTFS}"}" )
	done

	if [[ ${#found[@]} -eq 0 ]]; then
		printf 'none'
	else
		printf '%s' "${found[*]}"
	fi
}

# reported_removals
# The paths cleanup said it removed, relative to the fabricated root.
#
# Pinning the module's own report, not only the end state, is deliberate.
# do_cleanup removes *every* managed path once it decides to act, so a detector
# that finds only some of the dangling links still leaves a correct tree behind
# and no end-state assertion can tell the two apart. The detector still matters:
# one that finds none at all makes cleanup a silent no-op on a broken tree.
# Verified - inverting only the first of find_dangling_links' two loops leaves
# every end-state assertion green.
reported_removals() {
	local -a found=()
	local line

	while IFS= read -r line; do
		[[ ${line} == "Removing dangling link "* ]] || continue
		line=${line#Removing dangling link }
		found+=( "${line#"${ROOTFS}"}" )
	done <<<"${MODULE_OUT}"

	if [[ ${#found[@]} -eq 0 ]]; then
		printf 'none'
	else
		printf '%s' "${found[*]}"
	fi
}

# surviving_summary
# Every managed path plus the env file that still exists in any shape.
surviving_summary() {
	local -a found=()
	local rel path

	for rel in "${MANAGED_RELPATHS[@]}"; do
		path="${ROOTFS}/${rel}"
		[[ -e ${path} || -L ${path} ]] && found+=( "/${rel}" )
	done
	for path in "${ROOTFS}/usr/share/man/man1"/node.1*; do
		found+=( "${path#"${ROOTFS}"}" )
	done
	path="${ROOTFS}/${MANAGED_ENVFILE}"
	[[ -e ${path} || -L ${path} ]] && found+=( "/${MANAGED_ENVFILE}" )

	if [[ ${#found[@]} -eq 0 ]]; then
		printf 'none'
	else
		printf '%s' "${found[*]}"
	fi
}

# manpage_links
manpage_links() {
	local -a found=()
	local path
	for path in "${ROOTFS}/usr/share/man/man1"/node.1*; do
		found+=( "${path##*/}" )
	done
	if [[ ${#found[@]} -eq 0 ]]; then
		printf 'none'
	else
		printf '%s' "${found[*]}"
	fi
}

# manpath_value
manpath_value() {
	local file="${ROOTFS}/${MANAGED_ENVFILE}"
	if [[ ! -f ${file} ]]; then
		printf 'no env file'
		return 0
	fi
	local line
	while IFS= read -r line; do
		[[ ${line} == MANPATH=* ]] || continue
		line=${line#MANPATH=\"}
		printf '%s' "${line%\"}"
		return 0
	done <"${file}"
	printf 'no MANPATH key'
}

# host_etc_fingerprint
# Read-only. Hazard 1 is only actually defused if this is identical before and
# after the run.
host_etc_fingerprint() {
	{
		md5sum /etc/profile.env /etc/profile.csh 2>/dev/null || true
		find /etc/env.d -maxdepth 1 -type f -print0 2>/dev/null \
			| sort -z \
			| xargs -0 -r md5sum 2>/dev/null || true
	} | md5sum | cut -d' ' -f1
}

### phases ##########################################################

phase_discovery() {
	section "Phase 1 - discovery and ordering (slots 9, 10, 26)"
	build_root 9 10 26

	run_module -b list
	local listed
	listed=$(printf '%s' "${MODULE_OUT}" | tr '\n' ' ')
	listed="rc=${MODULE_RC}; ${listed% }"
	ASSERT_CONTEXT=$(module_context)
	assert_eq a \
		"list orders slots by numeric version (sort -V), not lexicographically" \
		"rc=0; node9 node10 node26" "${listed}"

	# The numbered list do_set indexes into must follow the same order, or the
	# numbers on screen and the slot that gets activated drift apart.
	run_module set 1
	local set_rc=${MODULE_RC} set_ctx
	set_ctx=$(module_context)
	run_module show
	ASSERT_CONTEXT="set: ${set_ctx} / show: $(module_context)"
	assert_eq i \
		"the numbered index follows the same order: 'set 1' activates node9" \
		"rc=0; node9" "rc=${set_rc}; ${MODULE_OUT}"
}

phase_set() {
	section "Phase 2 - set retargeting, show contract, env file"
	build_root 9 10 26

	# Nothing active yet: the state every consumer's pkg_postinst branches on.
	run_module show
	ASSERT_CONTEXT=$(module_context)
	assert_eq f \
		"show prints zero bytes, nothing on stderr and exits 0 when no slot is active" \
		"rc=0; stdout=; stderr=" \
		"rc=${MODULE_RC}; stdout=${MODULE_OUT}; stderr=${MODULE_ERR}"

	run_module set node26
	local set_rc=${MODULE_RC}
	ASSERT_CONTEXT=$(module_context)
	assert_eq b \
		"set node26 points /usr/bin/node at the node-26 slot" \
		"rc=0; symlink ../lib64/node-26/bin/node => /usr/lib64/node-26/bin/node" \
		"rc=${set_rc}; $(path_state "${ROOTFS}/usr/bin/node")"

	run_module show
	ASSERT_CONTEXT=$(module_context)
	assert_eq e \
		"show then prints exactly the active slot name, nothing on stderr, exit 0" \
		"rc=0; stdout=node26; stderr=" \
		"rc=${MODULE_RC}; stdout=${MODULE_OUT}; stderr=${MODULE_ERR}"

	ASSERT_CONTEXT="env file: $(path_state "${ROOTFS}/${MANAGED_ENVFILE}")"
	assert_eq l \
		"/etc/env.d/50nodejs records the active slot's man root (R7.3)" \
		"/usr/lib64/node-26/share/man" "$(manpath_value)"
}

phase_directory_replacement() {
	section "Phase 3 - a real directory at /usr/include/node (R3.3)"
	build_root 9 10 26

	# Exactly what the unslotted net-libs/nodejs:0 leaves behind.
	mkdir -p -- "${ROOTFS}/usr/include/node/deps/v8" \
		"${ROOTFS}/usr/include/node/deps/uv"
	printf '/* leftover of net-libs/nodejs:0 */\n' \
		>"${ROOTFS}/usr/include/node/node.h"

	# A stale compressed manpage from a previous slot, sitting where the new
	# uncompressed one is about to land.
	printf 'stale\n' >"${ROOTFS}/usr/share/man/man1/node.1.gz"

	run_module set node26
	local set_rc=${MODULE_RC}
	ASSERT_CONTEXT="$(module_context); nested /usr/include/node/node present: $(yesno test -e "${ROOTFS}/usr/include/node/node")"
	assert_eq c \
		"set replaces a REAL directory at /usr/include/node instead of linking beneath it" \
		"rc=0; symlink ../lib64/node-26/include/node => /usr/lib64/node-26/include/node" \
		"rc=${set_rc}; $(path_state "${ROOTFS}/usr/include/node")"

	ASSERT_CONTEXT=$(module_context)
	assert_eq k \
		"a stale node.1.gz does not survive beside the new node.1" \
		"node.1" "$(manpage_links)"
}

phase_repoint() {
	section "Phase 4 - re-pointing over an existing symlink"
	build_root 9 10 26

	run_module set node26
	local first_rc=${MODULE_RC} first_ctx
	first_ctx=$(module_context)

	# /usr/include/node is now a symlink TO A DIRECTORY - the shape that makes
	# a second switch land inside the previously active slot when nothing
	# guards against it. The module guards twice (remove_symlinks clears the
	# path, and ln carries -n); this asserts the outcome, which is what a
	# consumer sees. See KNOWN COVERAGE LIMIT in the header.
	run_module set node10
	ASSERT_CONTEXT="set node26: ${first_ctx} / set node10: $(module_context); node-26 include dir now holds: $(dir_entries "${ROOTFS}/usr/lib64/node-26/include")"
	assert_eq h \
		"re-pointing over a symlink-to-directory lands in the new slot, not inside the old one" \
		"rc=0; rc=0; symlink ../lib64/node-10/include/node => /usr/lib64/node-10/include/node" \
		"rc=${first_rc}; rc=${MODULE_RC}; $(path_state "${ROOTFS}/usr/include/node")"
}

phase_update() {
	section "Phase 5 - update picks the highest slot"
	build_root 9 10 26

	run_module update
	ASSERT_CONTEXT=$(module_context)
	assert_eq g \
		"update activates the highest slot (node26), which a lexicographic sort would miss" \
		"rc=0; symlink ../lib64/node-26/bin/node => /usr/lib64/node-26/bin/node" \
		"rc=${MODULE_RC}; $(path_state "${ROOTFS}/usr/bin/node")"
}

phase_optional_npm() {
	section "Phase 6 - a slot built with USE=-npm"
	build_root 10 26
	rm -rf -- "${ROOTFS}/usr/lib64/node-9"
	make_slot 9 nonpm

	run_module set node26
	local first_rc=${MODULE_RC} first_ctx
	first_ctx=$(module_context)

	run_module set node9
	ASSERT_CONTEXT="set node26: ${first_ctx} / set node9: $(module_context); /usr/bin/npm: $(path_state "${ROOTFS}/usr/bin/npm")"
	assert_eq j \
		"switching to a slot without npm leaves no link pointing into the previous slot" \
		"rc=0; rc=0; dangling=none; npm=absent" \
		"rc=${first_rc}; rc=${MODULE_RC}; dangling=$(dangling_summary); npm=$(path_state "${ROOTFS}/usr/bin/npm")"
}

phase_cleanup() {
	section "Phase 7 - cleanup after an unmerged slot (R3.4)"
	build_root 10 26

	run_module set node26
	local set_ctx
	set_ctx=$(module_context)

	# The slot is unmerged while active: every managed link now dangles.
	rm -rf -- "${ROOTFS}/usr/lib64/node-26"
	local was_dangling
	was_dangling=$(dangling_summary)

	run_module cleanup
	local repaired
	repaired=$(yesno grep -qF "Switching Node.js to node10 ..." <<<"${MODULE_OUT}")

	ASSERT_CONTEXT="set: ${set_ctx} / cleanup: $(module_context)"
	assert_eq o \
		"cleanup names every managed path that was dangling, not just some of them" \
		"${was_dangling}" "$(reported_removals)"

	ASSERT_CONTEXT="set: ${set_ctx} / cleanup: $(module_context)"
	assert_eq d \
		"cleanup drops the dangling links and re-points at the highest remaining slot" \
		"rc=0; dangling=none; repaired=yes; symlink ../lib64/node-10/bin/node => /usr/lib64/node-10/bin/node" \
		"rc=${MODULE_RC}; dangling=$(dangling_summary); repaired=${repaired}; $(path_state "${ROOTFS}/usr/bin/node")"

	# ... and the last slot going away must take the whole managed set with it.
	rm -rf -- "${ROOTFS}/usr/lib64/node-10"
	run_module cleanup
	ASSERT_CONTEXT=$(module_context)
	assert_eq m \
		"cleanup after the last slot removes every managed path and the env file" \
		"rc=0; surviving=none" \
		"rc=${MODULE_RC}; surviving=$(surviving_summary)"
}

### run #############################################################

printf 'module          : %s\n' "${MODULE}"
printf 'eselect         : %s\n' "$(command -v eselect)"
printf 'fabricated root : %s\n' "${ROOTFS}"

HOST_ETC_BEFORE=$(host_etc_fingerprint)
printf 'host /etc digest: %s\n' "${HOST_ETC_BEFORE}"

phase_discovery
phase_set
phase_directory_replacement
phase_repoint
phase_update
phase_optional_npm
phase_cleanup

section "Phase 8 - host safety"
HOST_ETC_AFTER=$(host_etc_fingerprint)
ASSERT_CONTEXT="a difference here means eselect's env_update() reached the real /etc - see PACKAGE_MANAGER=paludis in this script's header"
assert_eq n \
	"the host's /etc/profile.env and /etc/env.d are byte-identical after the run" \
	"${HOST_ETC_BEFORE}" "${HOST_ETC_AFTER}"

### verdict #########################################################

if [[ ${#FAILURES[@]} -eq 0 ]]; then
	printf '\n%d assertions, all passed\n' "${ASSERT_TOTAL}"
	exit 0
fi

printf '\n%d assertions, %d FAILED:\n' "${ASSERT_TOTAL}" "${#FAILURES[@]}"
for failure in "${FAILURES[@]}"; do
	printf '  - %s\n' "${failure}"
done
exit 1
