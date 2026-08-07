#!/usr/bin/env bash
# Assert the sci-biology/foldingathome libsystemd fix against a real installed
# image -- not against the text of the ebuild.
#
# The bug: the prebuilt fah-client carries a DT_NEEDED on libsystemd.so.0 and is
# linked BIND_NOW, so on an OpenRC box (elogind, no systemd) the loader aborts
# before main() and the client never starts. The fix installs a symlink that
# points libsystemd.so.0 at elogind's libelogind.so.0 and bakes a private
# RUNPATH into the binary so that symlink is found with no help from the caller.
#
# Every claim in that sentence is a property of the *installed image*, so this
# script builds the image and inspects it. Grepping the ebuild would only prove
# that the source says the right thing: it would not catch a dosym landing in
# the wrong directory, a patchelf call silently no-opping, an eclass stripping
# the RUNPATH back out, or a USE-flag combination that was never buildable.
#
# It runs `ebuild ... clean install` four times, once per USE combination, and
# asserts 13 properties across the resulting images and build logs:
#
#   (a) USE="elogind -systemd"    the fix path         checks 01-03, 08-13
#   (b) USE="-elogind systemd"    no regression        checks 04-05
#   (c) USE="elogind systemd"     must be refused      check  06
#   (d) USE="-elogind -systemd"   must be refused      check  07
#
# Requirements traced: R1.1 R1.2 (01-03) - R2.1 R2.2 (04-05) - R3.2 (06-07) -
# Unchanged Behavior (08-13).
#
# NOT covered here, stated up front so a green run is not over-read:
#   * the resulting ownership of the three state dirs. Setting it needs root
#     AND an installed acct-user/foldingathome; this host has neither. Check 13
#     proves the fowners CALL is made with the right arguments -- no more. The
#     script prints this caveat again at the end.
#   * arm64 installability. That is a KEYWORDS / $(get_libdir) property, not
#     something an amd64 image can show. No check is faked for it.
#
# Usage: bash verify.sh <path-to-ebuild>
#
#   bash verify.sh .../sci-biology/foldingathome/foldingathome-8.5.6-r1.ebuild
#   bash verify.sh /var/tmp/epic-009/redrepo/sci-biology/foldingathome/foldingathome-8.5.6.ebuild
#
# Env:   PORTAGE_TMPDIR   where builds land (default /var/tmp/epic-009)
#
# Exit:  0  every check passed
#        1  at least one check failed
#        2  a precondition failed -- nothing meaningful ran. A distinct code on
#           purpose: "nothing ran" must never be read as "all green".

set -euo pipefail

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------

# Builds land here. Deliberately /var/tmp and never a session scratchpad: deep
# tmpdirs have broken unrelated builds in this overlay by pushing AF_UNIX socket
# paths past SUN_LEN (~101 chars), and that surfaces as a bogus toolchain error.
PORTAGE_TMPDIR=${PORTAGE_TMPDIR:-/var/tmp/epic-009}
CONFIGROOT=${PORTAGE_TMPDIR}/cr
LOGDIR=${PORTAGE_TMPDIR}/verify-logs
REAL_PORTAGE_CONF=/etc/portage

# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

checks_run=0
checks_failed=0

pass() { # <id> <name> <detail>
	checks_run=$(( checks_run + 1 ))
	printf 'PASS  %-2s %-19s %s\n' "$1" "$2" "$3"
}

fail() { # <id> <name> <detail>
	checks_run=$(( checks_run + 1 ))
	checks_failed=$(( checks_failed + 1 ))
	printf 'FAIL  %-2s %-19s %s\n' "$1" "$2" "$3"
}

note()    { printf 'NOTE  %s\n' "$*"; }
section() { printf '\n== %s\n' "$*"; }

precondition() {
	printf 'PRECONDITION  %s\n' "$*" >&2
	printf 'PRECONDITION  nothing was verified; exiting 2 (neither pass nor fail)\n' >&2
	exit 2
}

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------

(( $# == 1 )) || precondition "usage: ${0##*/} <path-to-ebuild> (got $# argument(s))"

EBUILD=$1
[[ -r ${EBUILD} ]]      || precondition "ebuild not readable: ${EBUILD}"
[[ ${EBUILD} == *.ebuild ]] || precondition "not an ebuild path: ${EBUILD}"

# Resolve to an absolute path: ebuild(1) is run from this script's cwd, and the
# derived image path must agree with what portage picks.
EBUILD=$(cd -- "$(dirname -- "${EBUILD}")" && pwd)/$(basename -- "${EBUILD}")

PF=$(basename -- "${EBUILD}" .ebuild)
PKGDIR=$(dirname -- "${EBUILD}")
PN=$(basename -- "${PKGDIR}")
CATEGORY=$(basename -- "$(dirname -- "${PKGDIR}")")

# This script asserts foldingathome-specific behaviour. Pointing it at another
# package is a usage error, not a failing check.
[[ ${PN} == foldingathome ]] ||
	precondition "this script only verifies sci-biology/foldingathome, got ${CATEGORY}/${PN}"

for tool in ebuild readelf readlink patchelf; do
	command -v "${tool}" >/dev/null 2>&1 ||
		precondition "required tool not found in PATH: ${tool}"
done
unset tool

# patchelf above is not optional: without it the elogind path cannot be built at
# all, so its absence is a broken environment rather than a broken ebuild.

[[ ${PORTAGE_TMPDIR} == /* ]] || precondition "PORTAGE_TMPDIR must be absolute: ${PORTAGE_TMPDIR}"
mkdir -p "${PORTAGE_TMPDIR}" 2>/dev/null ||
	precondition "PORTAGE_TMPDIR not creatable: ${PORTAGE_TMPDIR}"
[[ -w ${PORTAGE_TMPDIR} ]] || precondition "PORTAGE_TMPDIR not writable: ${PORTAGE_TMPDIR}"

[[ -d ${REAL_PORTAGE_CONF} && -r ${REAL_PORTAGE_CONF}/make.conf ]] ||
	precondition "host portage config missing: ${REAL_PORTAGE_CONF}/make.conf"

# ---------------------------------------------------------------------------
# Config root
# ---------------------------------------------------------------------------

# Three host facts stop `ebuild ... install` from completing as a normal user,
# and all three are neutralised by a private PORTAGE_CONFIGROOT rather than by
# touching /etc/portage:
#
#   1. elogind is USE-masked by this host's profile (targets/systemd/use.mask).
#      Unmasked nowhere, USE="elogind -systemd" would leave BOTH flags off and
#      REQUIRED_USE would reject the build -- silently turning the fix path into
#      a false red instead of exercising it.
#   2. fowners needs acct-user/foldingathome, which is not installed and cannot
#      be without root. FEATURES=unprivileged downgrades the failed chown to a
#      warning instead of killing the install phase midway.
#   3. portage's post-install uid fix wants chown(image/opt, 0, 0), impossible
#      as a normal user. PORTAGE_INST_UID/GID point it at the caller instead.
#
# Rebuilt from scratch on every run so a fresh clone works, and idempotent so a
# prepared tree is left semantically untouched. The identity is derived, never
# hardcoded.
ensure_configroot() {
	local dest=${CONFIGROOT}/etc/portage
	local entry name

	mkdir -p "${dest}/profile" 2>/dev/null ||
		precondition "config root not creatable: ${dest}"

	# Everything the host already configures (profile, repos.conf, keywords,
	# package.use, ...) is shared by symlink; only the two overrides below are
	# real files. Copying would let the two drift.
	shopt -s nullglob
	for entry in "${REAL_PORTAGE_CONF}"/*; do
		name=${entry##*/}
		[[ ${name} == make.conf || ${name} == profile ]] && continue
		ln -sfn "${entry}" "${dest}/${name}"
	done
	shopt -u nullglob

	printf -- '-elogind\n' >"${dest}/profile/use.mask"

	{
		printf 'source %s/make.conf\n' "${REAL_PORTAGE_CONF}"
		# shellcheck disable=SC2016  # ${FEATURES} must reach make.conf unexpanded
		printf '%s\n' 'FEATURES="${FEATURES} unprivileged"'
		printf 'PORTAGE_USERNAME="%s"\n' "$(id -un)"
		printf 'PORTAGE_GRPNAME="%s"\n'  "$(id -gn)"
		printf 'PORTAGE_INST_UID="%s"\n' "$(id -u)"
		printf 'PORTAGE_INST_GID="%s"\n' "$(id -g)"
	} >"${dest}/make.conf"
}

# `[[ ... ]] && continue` inside the loop above is safe under errexit only
# because a failing left-hand side of an AND list that is not the final command
# is exempt; every other conditional in this script uses an explicit `if`.

# ---------------------------------------------------------------------------
# Build driver
# ---------------------------------------------------------------------------

# Image of the build currently under inspection. `ebuild clean` wipes this path,
# and every USE combination reuses it, so each build must be inspected before
# the next one starts.
IMG=

image_path() { printf '%s/portage/%s/%s/image' "${PORTAGE_TMPDIR}" "${CATEGORY}" "${PF}"; }

# Strip the image prefix so a FAIL line reads /etc/init.d/fah-client rather than
# sixty characters of build path.
rel() { printf '%s' "${1#"${IMG}"}"; }

run_build() { # <use-string> <log-path> -> ebuild's exit status
	local use=$1 log=$2 rc=0

	PORTAGE_CONFIGROOT="${CONFIGROOT}" \
	PORTAGE_TMPDIR="${PORTAGE_TMPDIR}" \
	NOCOLOR=true \
	USE="${use}" \
		ebuild "${EBUILD}" clean install >"${log}" 2>&1 || rc=$?

	return "${rc}"
}

show_tail() { # <log-path> <lines>
	printf '      ---- last %s lines of %s ----\n' "$2" "$1"
	# `|| true`: this runs from inside a failure branch, and a missing log must
	# not abort the remaining checks -- one red never hides the rest.
	if [[ -f $1 ]]; then
		tail -n "$2" -- "$1" | sed 's/^/      | /' || true
	else
		printf '      | (log file absent)\n'
	fi
	printf '      ---- end ----\n'
}

# ---------------------------------------------------------------------------
# ELF helpers
# ---------------------------------------------------------------------------

# The dynamic section, always under the C locale. This host's readelf is
# localised (pt_BR renders DT_RUNPATH's label as "Runpath da biblioteca:"), so
# anything matching on the English label would silently find nothing and report
# a false FAIL. Matching happens on the locale-stable tag name in parentheses,
# and LC_ALL=C makes that guarantee explicit instead of lucky.
elf_dyn() { LC_ALL=C readelf -d "$1" 2>/dev/null || true; }

# Substring tests on the captured text, never `readelf | grep -q`: grep -q exits
# on first match, readelf takes SIGPIPE, and pipefail then reports the pipeline
# as failed -- inverting the answer exactly when the tag IS present.
dyn_has_tag() { [[ $1 == *"($2)"* ]]; }

dyn_runpaths() { # <dynamic-section-text> -> one bracketed value per line
	local line value
	while IFS= read -r line; do
		[[ ${line} == *"(RUNPATH)"* ]] || continue
		[[ ${line} == *\[*\]* ]] || continue
		value=${line##*\[}
		printf '%s\n' "${value%%\]*}"
	done <<<"$1"
}

# $(get_libdir) on the target profile: the dosym in the ebuild spells the
# elogind path with it, so the expected symlink target has to follow.
expected_libdir() {
	local abi='' libdir=''
	if command -v portageq >/dev/null 2>&1; then
		abi=$(portageq envvar DEFAULT_ABI 2>/dev/null || true)
		if [[ -n ${abi} ]]; then
			libdir=$(portageq envvar "LIBDIR_${abi}" 2>/dev/null || true)
		fi
	fi
	# Fallback: this host's profile is amd64 no-multilib, where get_libdir
	# resolves to lib64. Hardcoding it keeps the check honest if portageq is
	# unusable, rather than comparing against an empty string.
	printf '%s' "${libdir:-lib64}"
}

# ---------------------------------------------------------------------------
# Path assertions
# ---------------------------------------------------------------------------

path_ok() { # <flag> <path>
	case $1 in
		# -L uses lstat and never follows the link. That matters twice here:
		# the /usr/bin entries point at paths that only resolve on a merged
		# system, and the libsystemd.so.0 link points at a library this
		# systemd host does not have.
		-L) [[ -L $2 ]] ;;
		-f) [[ -f $2 ]] ;;
		-d) [[ -d $2 ]] ;;
		*)  return 2 ;;
	esac
}

assert_paths() { # <id> <name> <flag> <path>...
	local id=$1 name=$2 flag=$3
	shift 3
	local p
	local missing=()
	local shown=()

	for p in "$@"; do
		shown+=( "$(rel "${p}")" )
		if ! path_ok "${flag}" "${p}"; then
			missing+=( "$(rel "${p}")" )
		fi
	done

	if (( ${#missing[@]} == 0 )); then
		pass "${id}" "${name}" "present: ${shown[*]}"
	else
		fail "${id}" "${name}" "missing: ${missing[*]}"
	fi
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

ensure_configroot

[[ -n ${LOGDIR} && ${LOGDIR} == */verify-logs ]] || precondition "refusing to clear ${LOGDIR}"
rm -rf -- "${LOGDIR}"
mkdir -p "${LOGDIR}" || precondition "log dir not creatable: ${LOGDIR}"

LIBDIR=$(expected_libdir)

printf '%-15s %s\n' 'ebuild'         "${EBUILD}"
printf '%-15s %s/%s (PF=%s)\n' 'package' "${CATEGORY}" "${PN}" "${PF}"
printf '%-15s %s\n' 'PORTAGE_TMPDIR' "${PORTAGE_TMPDIR}"
printf '%-15s %s\n' 'configroot'     "${CONFIGROOT}"
printf '%-15s %s\n' 'logs'           "${LOGDIR}"
printf '%-15s %s\n' 'get_libdir'     "${LIBDIR}"
# Printed so a reviewer can replay any single build by hand.
printf '%-15s PORTAGE_CONFIGROOT=%s PORTAGE_TMPDIR=%s NOCOLOR=true \\\n' \
	'build command' "${CONFIGROOT}" "${PORTAGE_TMPDIR}"
printf '%-15s   USE="<combination>" ebuild %s clean install\n' '' "${EBUILD}"

# ---------------------------------------------------------------------------
# (a) USE="elogind -systemd" -- the fix path
# ---------------------------------------------------------------------------

section '(a) USE="elogind -systemd" -- the fix path'

LOG_A=${LOGDIR}/a-elogind.log
rc=0
run_build 'elogind -systemd' "${LOG_A}" || rc=$?
printf 'build         exit %s   (%s)\n' "${rc}" "${LOG_A}"
if (( rc != 0 )); then
	fail '--' 'build-a' "ebuild clean install exited ${rc}, expected 0"
	show_tail "${LOG_A}" 30
fi

IMG=$(image_path)
printf 'image         %s\n' "${IMG}"

BIN_A=${IMG}/opt/foldingathome/fah-client
LINK=${IMG}/opt/foldingathome/lib/libsystemd.so.0
WANT_RUNPATH=/opt/foldingathome/lib
WANT_TARGET=../../../usr/${LIBDIR}/libelogind.so.0

# --- 01  R1.2: the override travels in the ELF, so no caller env var is needed.
if [[ ! -f ${BIN_A} ]]; then
	fail '01' 'runpath-elogind' "binary absent from image: $(rel "${BIN_A}")"
else
	DYN_A=$(elf_dyn "${BIN_A}")
	runpaths=()
	mapfile -t runpaths < <(dyn_runpaths "${DYN_A}")
	if (( ${#runpaths[@]} == 0 )); then
		fail '01' 'runpath-elogind' "no DT_RUNPATH entry; expected ${WANT_RUNPATH}"
	elif [[ " ${runpaths[*]} " == *" ${WANT_RUNPATH} "* ]]; then
		pass '01' 'runpath-elogind' "DT_RUNPATH = ${WANT_RUNPATH}"
	else
		fail '01' 'runpath-elogind' "DT_RUNPATH = ${runpaths[*]}; expected ${WANT_RUNPATH}"
	fi
fi

# --- 02/03  R1.1: libsystemd.so.0 must resolve to elogind's implementation.
if ! path_ok -L "${LINK}"; then
	if [[ -e ${LINK} ]]; then
		fail '02' 'libsystemd-symlink' "exists but is not a symlink: $(rel "${LINK}")"
	else
		fail '02' 'libsystemd-symlink' "absent: $(rel "${LINK}")"
	fi
	fail '03' 'libsystemd-target' "cannot read target, link absent or not a symlink"
else
	pass '02' 'libsystemd-symlink' "$(rel "${LINK}") is a symlink"

	# Textual comparison only. libelogind.so.0 does not exist on this systemd
	# build host, so the link is legitimately dangling: readlink -f, test -e,
	# test -L on the resolved path or ls -L would every one report a false FAIL.
	got_target=$(readlink -- "${LINK}")
	if [[ ${got_target} == "${WANT_TARGET}" ]]; then
		pass '03' 'libsystemd-target' "-> ${got_target}"
	else
		fail '03' 'libsystemd-target' "-> ${got_target}; expected ${WANT_TARGET}"
	fi
fi

# --- 08-12  Unchanged Behavior, asserted against this same image.
assert_paths '08' 'openrc-files' -f \
	"${IMG}/etc/init.d/fah-client" \
	"${IMG}/etc/conf.d/fah-client"

assert_paths '09' 'systemd-unit' -f \
	"${IMG}/usr/lib/systemd/system/fah-client.service"

assert_paths '10' 'state-dirs' -d \
	"${IMG}/etc/fah-client" \
	"${IMG}/var/lib/fah-client" \
	"${IMG}/var/log/fah-client"

# The desktop file really is xdg-open-foldingathome.desktop: make_desktop_entry
# names it after the exec command, not after the binary.
assert_paths '11' 'polkit-desktop-icon' -f \
	"${IMG}/usr/share/polkit-1/rules.d/10-fah-client.rules" \
	"${IMG}/usr/share/applications/xdg-open-foldingathome.desktop" \
	"${IMG}/usr/share/pixmaps/fah-client.png"

assert_paths '12' 'usr-bin-symlinks' -L \
	"${IMG}/usr/bin/fah-client" \
	"${IMG}/usr/bin/fahctl"

# --- 13  the fowners CALL. See the coverage note at the end: this proves the
# arguments, never the resulting ownership.
# shellcheck disable=SC2016  # portage reverse-expands the path, so ${D} is literal output
expected_chowns=(
	'chown foldingathome:foldingathome ${D}/etc/fah-client'
	'chown foldingathome:foldingathome ${D}/var/lib/fah-client'
	'chown foldingathome:foldingathome ${D}/var/log/fah-client'
)
missing_chowns=()
for want in "${expected_chowns[@]}"; do
	if ! grep -qF -- "${want}" "${LOG_A}"; then
		missing_chowns+=( "${want##*foldingathome }" )
	fi
done
if (( ${#missing_chowns[@]} == 0 )); then
	pass '13' 'fowners-calls' 'all three fowners foldingathome:foldingathome calls logged'
else
	fail '13' 'fowners-calls' "no fowners call logged for: ${missing_chowns[*]}"
fi

# ---------------------------------------------------------------------------
# (b) USE="-elogind systemd" -- the systemd path must stay clean
# ---------------------------------------------------------------------------

section '(b) USE="-elogind systemd" -- no regression on systemd'

LOG_B=${LOGDIR}/b-systemd.log
rc=0
run_build '-elogind systemd' "${LOG_B}" || rc=$?
printf 'build         exit %s   (%s)\n' "${rc}" "${LOG_B}"
if (( rc != 0 )); then
	fail '--' 'build-b' "ebuild clean install exited ${rc}, expected 0"
	show_tail "${LOG_B}" 30
fi

IMG=$(image_path)
BIN_B=${IMG}/opt/foldingathome/fah-client
LIBSUBDIR=${IMG}/opt/foldingathome/lib

# --- 04  R2.1: no library symlink is installed under /opt/foldingathome.
if [[ -e ${LIBSUBDIR} || -L ${LIBSUBDIR} ]]; then
	fail '04' 'systemd-no-libdir' "present but must not be: $(rel "${LIBSUBDIR}")"
else
	pass '04' 'systemd-no-libdir' "$(rel "${LIBSUBDIR}") absent"
fi

# --- 05  R2.2: the binary keeps resolving through the normal loader search path.
if [[ ! -f ${BIN_B} ]]; then
	fail '05' 'systemd-no-runpath' "binary absent from image: $(rel "${BIN_B}")"
else
	DYN_B=$(elf_dyn "${BIN_B}")
	tags=()
	if dyn_has_tag "${DYN_B}" RUNPATH; then tags+=( RUNPATH ); fi
	if dyn_has_tag "${DYN_B}" RPATH;   then tags+=( RPATH );   fi
	if (( ${#tags[@]} == 0 )); then
		pass '05' 'systemd-no-runpath' 'no DT_RUNPATH and no DT_RPATH'
	else
		fail '05' 'systemd-no-runpath' "unexpected ELF tag(s): ${tags[*]}"
	fi
fi

# ---------------------------------------------------------------------------
# (c)/(d) invalid USE combinations -- R3.2
# ---------------------------------------------------------------------------

section '(c)/(d) invalid USE combinations must be refused'

assert_required_use() { # <id> <name> <use-string> <log-path>
	local id=$1 name=$2 use=$3 log=$4 rc=0

	run_build "${use}" "${log}" || rc=$?

	if (( rc == 0 )); then
		fail "${id}" "${name}" "USE=\"${use}\" built successfully; expected a refusal"
		return
	fi
	# Match the bare token only. The full expression now carries the
	# python_single_target constraint appended by python-single-r1 and will keep
	# changing; pinning the whole string would make this check brittle.
	if grep -q 'REQUIRED_USE' "${log}"; then
		pass "${id}" "${name}" "USE=\"${use}\" refused (exit ${rc}, output names REQUIRED_USE)"
	else
		fail "${id}" "${name}" "USE=\"${use}\" exited ${rc} but output never names REQUIRED_USE (${log})"
	fi
}

assert_required_use '06' 'reject-both'    'elogind systemd'   "${LOGDIR}/c-both.log"
assert_required_use '07' 'reject-neither' '-elogind -systemd' "${LOGDIR}/d-neither.log"

# ---------------------------------------------------------------------------
# Coverage gaps -- printed on every run, green or red
# ---------------------------------------------------------------------------

section 'Coverage gaps'

note 'ownership NOT VERIFIED. The Unchanged Behavior statement says the three'
note '  state dirs end up owned foldingathome:foldingathome. Setting that owner'
note '  needs root AND an installed acct-user/foldingathome; this host has'
note '  neither, so FEATURES=unprivileged turns fowners into a logged no-op.'
note '  Check 13 proves the fowners CALL carries the right arguments. The'
note '  ownership of the merged result is out of reach here and is untested.'
printf '\n'
note 'arm64 installability NOT VERIFIED, and no check is faked for it. It is a'
# shellcheck disable=SC2016  # $(get_libdir) is prose here, not a command to run
note '  KEYWORDS / $(get_libdir) property: an amd64 image cannot show it. The'
note '  symlink target checked at 03 is the amd64 spelling of that same'
note "  \$(get_libdir) expression (${LIBDIR}), which is as close as this host gets."

# ---------------------------------------------------------------------------
# Verdict -- decided here, at the end, so one red never hides the rest
# ---------------------------------------------------------------------------

section 'Result'

if (( checks_failed == 0 )); then
	printf 'RESULT  PASS  %d/%d checks green\n' "${checks_run}" "${checks_run}"
	exit 0
fi

printf 'RESULT  FAIL  %d of %d checks red\n' "${checks_failed}" "${checks_run}"
exit 1
