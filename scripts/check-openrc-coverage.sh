#!/usr/bin/env bash
# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
#
# Report every package that installs a systemd unit without the matching
# OpenRC init script.
#
# WHAT IT IS FOR
#
# bentoo targets OpenRC boxes as much as systemd ones, but nothing in the tree
# enforces that. A package can install a .service and no init script, pass
# pkgcheck, merge cleanly, and leave the daemon simply unstartable on an OpenRC
# host - a gap that only surfaces when a user tries to run the thing. This
# script is the missing check. It classifies every package on one dimension -
# does it install a unit, and if so does it install the OpenRC counterpart at
# the SAME SCOPE - and names each gap.
#
# The criterion, stated once:
#
#   a SYSTEM unit (/usr/lib/systemd/system) pairs with /etc/init.d
#   a USER   unit (/usr/lib/systemd/user)   pairs with /etc/user/init.d
#
# The two scopes carry different severities. A missing system init script is a
# FAIL and drives the exit code: system init scripts are universal in this tree
# and their absence is a plain defect. A missing user-scope script is a WARN,
# printed and counted but not fatal: the user-scope pattern has exactly one
# precedent here (sys-apps/xdg-desktop-portal) and NONE in ::gentoo, so failing
# a build over it would be asserting a convention that does not yet exist.
#
# STRICTLY READ-ONLY
#
# It reads ebuild text and prints a report. It writes no file, creates no
# directory, touches no Manifest or metadata, and never runs git, portage or a
# build. A guard that edits what it measures is not a measurement.
#
# HOW IT CLASSIFIES
#
# By reading the highest-version ebuild of each package - comments stripped and
# elog/ewarn prose skipped, since both talk about these calls without making
# them - and looking for four things:
#
#   1. the install functions, matched as whole words: systemd_dounit,
#      systemd_newunit, systemd_douserunit, systemd_newuserunit,
#      systemd_install_serviced, newinitd, doinitd
#   2. the unit directory handed to a build system, where no install call ever
#      names the unit: systemd_get_systemunitdir, systemdsystemunitdir,
#      SYSTEMD_SERVICES_INSTALL_DIR, systemd-user-unit-dir,
#      systemd_get_userunitdir
#   3. a user-scope script installed as a plain file: exeinto into
#      /etc/user/init.d, then doexe/newexe
#   4. the reviewed allowlist below - a policy exclusion, printed with its
#      reason, never a silent filter
#
# Classification is on the DESTINATION PATH, never on a filename. A vendor
# payload dumped under /opt can carry a .service file (app-backup/duplicati-bin,
# media-sound/audacity-bin, mail-client/betterbird-bin all do) and it is inert
# there, because systemd does not read /opt. Matching "*.service" as a filename
# would count those, and would also count D-Bus activation files, which are not
# units at all (kde-plasma/kameleon-qmk-helper ships one).
#
# WHY EBUILD TEXT AND NOT metadata/md5-cache OR A BUILD
#
# md5-cache was evaluated as the index and rejected: the entry for a package
# that demonstrably installs a unit (metadata/md5-cache/www-misc/warsaw-2.21.5.1)
# carries INHERIT, DEFINED_PHASES, RESTRICT, SRC_URI, LICENSE and KEYWORDS, and
# no field records an installed unit or init script. Building all 318 packages
# and inspecting ${D} would be exact, and a guard that needs 318 builds is not
# a guard.
#
# WHAT THIS STILL MISSES - stated here rather than discovered later
#
#   * a unit that appears only after an upstream bump changes the payload, or
#     that a meson/cmake default starts installing on its own. Text cannot see
#     either; only a build can.
#   * anything installed by a helper sourced from files/.
#   * prose that is not on an elog/ewarn line. A heredoc body - readme.gentoo's
#     DOC_CONTENTS is the usual one - can name newinitd in running text and be
#     read as an install. Measured: no heredoc in this tree does, and every
#     occurrence of a detected token today is a real call.
#   * an init script installed as a plain file via `exeinto /etc/init.d` plus
#     doexe. No package in this tree uses that idiom (measured: zero), so no
#     detector is carried for it; the user-scope twin exists because
#     sys-apps/xdg-desktop-portal actually does it.
#   * USE flags. A unit installed under `if use systemd` counts as installed,
#     because the question is whether the package CAN put a unit on disk with
#     no OpenRC counterpart - not whether one particular profile does.
#   * eclasses that install services on the package's behalf. Only
#     apache-2.eclass and nginx.eclass do this in ::gentoo and bentoo inherits
#     neither, so this is a checked non-concern rather than an assumption.
#
# The guard narrows the window. It does not close it.
#
# USAGE
#
#   bash scripts/check-openrc-coverage.sh                  # whole overlay
#   bash scripts/check-openrc-coverage.sh sci-ml           # one category
#   bash scripts/check-openrc-coverage.sh sci-ml/lemonade  # one package
#   bash scripts/check-openrc-coverage.sh --self-test      # assertions only
#   bash scripts/check-openrc-coverage.sh -h
#
# A row is printed when the package carries a finding, or whenever a filter was
# given. An unfiltered run is a guard: its job is to name gaps, and 300-odd
# PASS/n-a rows would bury the handful that matter. A filter is a question about
# named packages, and the answer has to be printed even when it is PASS. The
# summary counts every package scanned either way, so nothing is invisible.
#
# Exit status:
#   0  every selected package classified, no system-scope gap. Warnings may be
#      present: a user-scope gap is reported without failing the run
#   1  at least one system-scope gap
#   2  a precondition or a usage error, i.e. NOTHING WAS COMPARED. The third
#      code is the important one: an empty report reads exactly like a clean
#      one, and that confusion is what it exists to prevent

set -euo pipefail

# Every glob below lists a package directory. An unmatched pattern must expand
# to nothing rather than to itself: a directory holding no .ebuild is precisely
# how a non-package is recognised, and the literal string "…/*.ebuild" would be
# counted as one ebuild instead of none.
shopt -s nullglob

### where things live ################################################

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
OVERLAY_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)

# Top-level directories that are part of the repository but hold no package.
# The structural rule below (a package is a directory holding at least one
# ebuild) already excludes them; naming them here makes the count of "scanned"
# honest and keeps metadata/md5-cache - which has one subdirectory per category
# and would otherwise be walked in full - out of the loop entirely.
NON_PACKAGE_TOPLEVEL=( metadata profiles scripts licenses eclass )

### the reviewed allowlist ###########################################
#
# A POLICY exclusion, and only that. It is never a place to put a package the
# classifier finds hard: an entry here suppresses a real finding forever, so
# each one is a decision someone made and signed, recorded with the reasoning
# that justified it.
#
# The counter-example is worth keeping in view. net-misc/rustdesk-bin LOOKS
# like a candidate - it does `cp -a etc usr "${ED}"/` and its payload contains
# a .service file - and it is not one. That .service sits at
# usr/share/rustdesk/files/systemd/, where systemd never looks, and the unit
# that really gets installed goes through an explicit systemd_dounit that pass 1
# already catches. Allowlisting it would suppress a package the classifier
# handles correctly AND make its genuine gap permanently unreportable.
declare -A ALLOWLIST=(
	[sys-apps/flatpak]=$'its units are a Type=oneshot updater plus a timer, not a daemon: there\nis nothing to supervise, and an init script wrapping a one-shot would\nshow up as crashed in rc-status. The two files are byte-identical to\n::gentoo\'s. The honest OpenRC analogue is a cron.daily drop-in, which\nwould add a virtual/cron dependency to a package that has none.'
)

### command line #####################################################

SELF_TEST=0
FILTER=""

usage() {
	printf 'Usage: check-openrc-coverage.sh [--self-test] [<category>|<category>/<package>]\n'
	printf '\n'
	printf 'Classify every package on the service dimension: a systemd unit with no\n'
	printf 'OpenRC init script at the same scope. System-scope gaps FAIL (exit 1),\n'
	printf 'user-scope gaps WARN (exit unchanged).\n'
	printf '\n'
	printf 'Exit: 0 no system gap - 1 a system gap - 2 nothing was compared\n'
}

# validate_filter <argument>
# A filter is either <category> or <category>/<package>. Shape is checked here;
# whether it matches anything is the enumeration stage's business. Both checks
# matter for the same reason: a filter that quietly selects nothing produces an
# empty report, and an empty report reads exactly like a clean one.
validate_filter() {
	local filter=$1
	local atom='[A-Za-z0-9][A-Za-z0-9+_.-]*'

	if [[ ${filter} =~ ^${atom}(/${atom})?$ ]]; then
		return 0
	fi

	printf 'not a category or a category/package: %s\n' "${filter}" >&2
	printf 'expected <category> (sci-ml) or <category>/<package> (sci-ml/lemonade)\n' >&2
	return 1
}

parse_args() {
	local arg
	while (( $# )); do
		arg=$1
		case ${arg} in
		--self-test)
			SELF_TEST=1
			;;
		-h|--help)
			usage
			exit 0
			;;
		-*)
			printf 'unknown option: %s\n' "${arg}" >&2
			usage >&2
			return 2
			;;
		*)
			if [[ -n ${FILTER} ]]; then
				printf 'at most one filter is accepted, got %s and %s\n' \
					"${FILTER}" "${arg}" >&2
				return 2
			fi
			validate_filter "${arg}" || return 2
			FILTER=${arg}
			;;
		esac
		shift
	done
}

### preconditions ####################################################

# Anything that would make the sweep compare nothing while still printing a
# clean-looking report. Each one exits 2, never 0.
check_preconditions() {
	local tool

	# A directory that exists but is not a package tree would classify every
	# package as absent and report a spotless overlay having read nothing.
	if [[ ! -f ${OVERLAY_ROOT}/profiles/repo_name ]]; then
		printf 'precondition failed: %s has no profiles/repo_name, so it is not a package tree\n' \
			"${OVERLAY_ROOT}" >&2
		return 2
	fi

	# awk does the comment stripping and sort -V picks the highest version.
	# Without either, every package would classify as carrying no unit - the
	# silent-pass shape this whole script exists to prevent.
	for tool in awk sort; do
		if ! command -v "${tool}" >/dev/null 2>&1; then
			printf 'precondition failed: required tool not found in PATH: %s\n' \
				"${tool}" >&2
			return 2
		fi
	done
}

### reading an ebuild ################################################

# strip_comments <path>
# The ebuild's text with every comment removed, one output line per input line
# so line numbers still refer to the real file.
#
# A comment starts at the first "#" that begins a word: at the start of the
# line, or immediately after whitespace. Nothing else is one. That distinction
# is load-bearing in both directions:
#
#   * ${var#prefix} carries a "#" that is NOT a comment. Cutting there would
#     delete whatever install call shares the line - a false negative, the
#     dangerous direction.
#   * a commented-out `#systemd_dounit foo` must not count as an install - a
#     false positive, which is how a guard loses its reader's trust.
strip_comments() {
	awk '
		{
			if ($0 ~ /^[ \t]*#/) { print ""; next }
			# match() finds the leftmost whitespace-then-# pair, which is the
			# first comment opener. RSTART is the whitespace itself, kept so
			# the preceding token still ends on a separator.
			if (match($0, /[ \t]#/)) { print substr($0, 1, RSTART); next }
			print
		}
	' "$1"
}

### the four detection passes ########################################
#
# Pass 1 matches WHOLE WORDS. A substring test is wrong here and would be wrong
# quietly: `grep -E 'systemd_dounit|newinitd'` misses doinitd (www-misc/warsaw),
# misses systemd_newuserunit (mail-mta/proton-mail-bridge), misses the whole
# build-system class of pass 2, and would have declared this overlay
# four-fifths clean. The boundaries also keep systemd_reenable, systemctl and
# any similarly-named future helper from standing in for an install call.
RE_SYS_UNIT_FN='(^|[^[:alnum:]_])(systemd_dounit|systemd_newunit|systemd_install_serviced)([^[:alnum:]_]|$)'
RE_USER_UNIT_FN='(^|[^[:alnum:]_])(systemd_douserunit|systemd_newuserunit)([^[:alnum:]_]|$)'
RE_INITD_FN='(^|[^[:alnum:]_])(newinitd|doinitd)([^[:alnum:]_]|$)'
RE_EXE_FN='(^|[^[:alnum:]_])(doexe|newexe)([^[:alnum:]_]|$)'
RE_EXEINTO='(^|[^[:alnum:]_])exeinto[[:space:]]+([^[:space:];]+)'

# A line whose first word is one of Gentoo's message functions is PROSE. It
# installs nothing, and its text routinely names the very calls this script
# looks for - `elog "on OpenRC, add one with newinitd foo"` is advice, not an
# init script. Word boundaries alone do not catch that: `newinitd` inside an
# elog IS a whole word, and counting it turns a package that ships a unit and
# no init script into a PASS. That is a false NEGATIVE, the direction that
# matters, and it was reproduced against a fixture before this filter existed.
#
# Measured against the tree: no ebuild in bentoo currently has any detected
# token on a message line, so this filter changes no verdict today. It exists
# so the first one that does is not silently absolved.
#
# `die` is here for the same reason and is safe: `newinitd x || die` starts
# with newinitd, not with die, and so is still read.
RE_MESSAGE_FN='^[[:space:]]*(elog|einfo|einfon|ewarn|eqawarn|eerror|ebegin|eend|ewend|die)([[:space:]]|$)'

# Pass 2 tokens are matched as plain substrings on purpose. They arrive spelled
# `-Dsystemdsystemunitdir=…` and `-DSYSTEMD_SERVICES_INSTALL_DIR="…"`, glued to
# the option prefix, so a word boundary in front would never match.
SYS_UNITDIR_TOKENS=( systemd_get_systemunitdir systemdsystemunitdir SYSTEMD_SERVICES_INSTALL_DIR )
USER_UNITDIR_TOKENS=( systemd-user-unit-dir systemd_get_userunitdir )

# Evidence for the four axes of the package being classified. Each holds
# "<line>: <what matched>" or the empty string. Evidence rather than a boolean
# because a FAIL has to name what it saw: "installs a unit" with no line number
# is an accusation, not a finding.
CLS_SYS_UNIT=""
CLS_USER_UNIT=""
CLS_SYS_INITD=""
CLS_USER_INITD=""

# classify_ebuild <path>
# Fill the four CLS_* variables from one ebuild.
classify_ebuild() {
	local path=$1
	local line token dest
	local lineno=0
	local exe_dest_scope=""

	CLS_SYS_UNIT=""
	CLS_USER_UNIT=""
	CLS_SYS_INITD=""
	CLS_USER_INITD=""

	while IFS= read -r line; do
		lineno=$(( lineno + 1 ))
		[[ -n ${line} ]] || continue

		# Prose first: an elog/ewarn line is advice about these calls, never
		# one of them. See RE_MESSAGE_FN.
		if [[ ${line} =~ ${RE_MESSAGE_FN} ]]; then
			continue
		fi

		# --- pass 1: install functions, whole words ------------------
		if [[ -z ${CLS_SYS_UNIT} && ${line} =~ ${RE_SYS_UNIT_FN} ]]; then
			CLS_SYS_UNIT="${lineno}: ${BASH_REMATCH[2]}"
		fi
		if [[ -z ${CLS_USER_UNIT} && ${line} =~ ${RE_USER_UNIT_FN} ]]; then
			CLS_USER_UNIT="${lineno}: ${BASH_REMATCH[2]}"
		fi
		if [[ -z ${CLS_SYS_INITD} && ${line} =~ ${RE_INITD_FN} ]]; then
			CLS_SYS_INITD="${lineno}: ${BASH_REMATCH[2]}"
		fi

		# --- pass 2: a unit directory handed to a build system -------
		# The unit is written by meson/cmake from this argument and no install
		# call ever names it, so pass 1 cannot see it. Four packages in this
		# tree are only visible here: net-misc/networkmanager,
		# net-misc/modemmanager, net-p2p/qbittorrent and, at user scope,
		# sys-apps/xdg-desktop-portal.
		if [[ -z ${CLS_SYS_UNIT} ]]; then
			for token in "${SYS_UNITDIR_TOKENS[@]}"; do
				if [[ ${line} == *"${token}"* ]]; then
					CLS_SYS_UNIT="${lineno}: ${token}"
					break
				fi
			done
		fi
		if [[ -z ${CLS_USER_UNIT} ]]; then
			for token in "${USER_UNITDIR_TOKENS[@]}"; do
				if [[ ${line} == *"${token}"* ]]; then
					CLS_USER_UNIT="${lineno}: ${token}"
					break
				fi
			done
		fi

		# --- pass 3: a user-scope script installed as a plain file ----
		# exeinto sets the destination and doexe/newexe write into it, so the
		# scope lives on the exeinto line and the install on a later one. Track
		# the destination and classify on IT: this is the "destination path,
		# never a filename" rule applied to the OpenRC side.
		if [[ ${line} =~ ${RE_EXEINTO} ]]; then
			dest=${BASH_REMATCH[2]}
			dest=${dest//\"/}
			dest=${dest//\'/}
			if [[ ${dest} == *etc/user/init.d* ]]; then
				exe_dest_scope="user"
			else
				exe_dest_scope=""
			fi
		elif [[ -z ${CLS_USER_INITD} && ${exe_dest_scope} == "user" && ${line} =~ ${RE_EXE_FN} ]]; then
			CLS_USER_INITD="${lineno}: exeinto /etc/user/init.d + ${BASH_REMATCH[2]}"
		fi
	done < <(strip_comments "${path}")
}

### version selection ################################################

# version_sort_key <version>
# A version rewritten so `sort -V` orders it the way Gentoo does.
#
# GNU sort -V gives "~" a special rank: it sorts before everything, including
# the empty string. That is exactly the relation Gentoo gives its pre-release
# suffixes (1.15.0_pre < 1.15.0), which a raw sort -V gets backwards because
# "1.15.0" is a prefix of "1.15.0_pre". _p and -r go the other way and only
# need to stop being treated as letters.
#
# _pre is rewritten before _p, or _pre would become .pre and lose its rank.
version_sort_key() {
	local v=$1
	v=${v//_alpha/\~a}
	v=${v//_beta/\~b}
	v=${v//_pre/\~c}
	v=${v//_rc/\~d}
	v=${v//_p/.p}
	v=${v//-r/.r}
	printf '%s' "${v}"
}

# highest_version_ebuild <package-dir>
# The one ebuild that speaks for the package.
#
# R3.11: classify once per PACKAGE, not once per ebuild. Two packages here keep
# two versions on purpose - app-editors/zed-bin and app-office/libreoffice each
# carry a stable and a _pre - and a per-ebuild sweep reports both of them twice.
#
# Deliberately the shell glob plus sort -V rather than `ls | sort`: parsing ls
# is against this repo's shell conventions and shellcheck flags it (SC2012).
# The sort is the same sort.
highest_version_ebuild() {
	local dir=$1
	local pn=${dir##*/}
	local f base ver
	local -a ebuilds=( "${dir}"/*.ebuild )
	local -a keyed=()

	(( ${#ebuilds[@]} )) || return 1

	if (( ${#ebuilds[@]} == 1 )); then
		printf '%s' "${ebuilds[0]}"
		return 0
	fi

	for f in "${ebuilds[@]}"; do
		base=${f##*/}
		base=${base%.ebuild}
		ver=${base#"${pn}-"}
		keyed+=( "$(version_sort_key "${ver}")"$'\t'"${f}" )
	done

	# LC_ALL=C because this host is localised (pt_BR) and a collation rule that
	# reorders punctuation would pick a different "highest" version on one
	# machine than on another. A guard whose answer depends on $LANG is not a
	# guard. Byte order is the same everywhere; sort -V's numeric runs are the
	# part that has to be right, and they are locale-independent.
	printf '%s\n' "${keyed[@]}" | LC_ALL=C sort -t$'\t' -k1,1 -V | tail -n 1 | cut -f2-
}

### selection ########################################################

# filter_selects <category/pn>
# An empty filter selects everything, a filter with no slash names a whole
# category, one with a slash names a single package. Shape was already checked.
filter_selects() {
	local key=$1 scope

	if [[ -z ${FILTER} ]]; then
		return 0
	fi

	if [[ ${FILTER} == */* ]]; then
		scope=${key}
	else
		scope=${key%%/*}
	fi

	[[ ${scope} == "${FILTER}" ]]
}

### the sweep ########################################################

# Rows are records: key, system verdict, user verdict, ebuild basename, then
# the four evidence fields. Collected rather than printed as they are produced
# so the rows, the allowlist and the summary can each get their own section
# while the tree is still walked exactly once.
#
# The separator is US (0x1f) and NOT a tab, for a reason that bites silently:
# tab is an IFS whitespace character, so `IFS=$'\t' read` collapses a run of
# tabs into one delimiter and drops leading and trailing ones. Four of the
# eight fields are routinely empty - a package with no user unit has no user
# evidence - and with tabs those empties vanish and every later field shifts
# left by one, so a WARN row would print its verdict against the wrong
# evidence. A non-whitespace separator delimits exactly once per occurrence.
# 0x1f cannot occur in ebuild text.
readonly FS=$'\x1f'

REPORT_ROWS=()
ALLOW_ROWS=()

SCANNED=0          # packages classified
UNIT_PACKAGES=0    # of those, packages installing a unit at either scope
FINDING_ROWS=0     # packages carrying at least one finding
SYS_FAIL=0         # findings: system-scope gaps
USER_WARN=0        # findings: user-scope gaps
SYS_PASS=0
USER_PASS=0
NO_EBUILD_DIRS=0   # package-shaped directories holding no ebuild

# sweep
# Walk the overlay, classify, fill the arrays and the counters. Returns 2 when
# nothing was classified, and never earlier than the end of the walk: stopping
# at the first finding hides the other ten (R3.5).
sweep() {
	local pkg_dir category pn key ebuild
	local sys user matched=0

	for pkg_dir in "${OVERLAY_ROOT}"/*/*/; do
		pkg_dir=${pkg_dir%/}
		pn=${pkg_dir##*/}
		category=${pkg_dir%/*}
		category=${category##*/}
		key="${category}/${pn}"

		# metadata/md5-cache and metadata/news match the */*/ glob and hold
		# hundreds of subdirectories between them. Skipping the known
		# non-package top levels by name is a shortcut, not the rule; the rule
		# is the ebuild test below.
		if [[ " ${NON_PACKAGE_TOPLEVEL[*]} " == *" ${category} "* ]]; then
			continue
		fi

		if ! filter_selects "${key}"; then
			continue
		fi

		# The definition of "package": a directory holding at least one ebuild.
		# A directory that looks like one and holds none (app-emulation/qemu is
		# in this state today, keeping only files/ and metadata.xml) is counted
		# and reported rather than passed over in silence - there is nothing to
		# classify there, and that is a fact about the tree, not a clean result.
		ebuild=$(highest_version_ebuild "${pkg_dir}") || {
			NO_EBUILD_DIRS=$(( NO_EBUILD_DIRS + 1 ))
			continue
		}

		matched=$(( matched + 1 ))
		SCANNED=$(( SCANNED + 1 ))

		classify_ebuild "${ebuild}"

		if [[ -z ${CLS_SYS_UNIT} ]]; then
			sys="n/a"
		elif [[ -n ${CLS_SYS_INITD} ]]; then
			sys="PASS"
		else
			sys="FAIL"
		fi

		if [[ -z ${CLS_USER_UNIT} ]]; then
			user="n/a"
		elif [[ -n ${CLS_USER_INITD} ]]; then
			user="PASS"
		else
			user="WARN"
		fi

		if [[ ${sys} != "n/a" || ${user} != "n/a" ]]; then
			UNIT_PACKAGES=$(( UNIT_PACKAGES + 1 ))
		fi

		local record
		record="${key}${FS}${sys}${FS}${user}${FS}${ebuild##*/}${FS}"
		record+="${CLS_SYS_UNIT}${FS}${CLS_USER_UNIT}${FS}"
		record+="${CLS_SYS_INITD}${FS}${CLS_USER_INITD}"

		# R3.4: an allowlisted package is classified first and excluded second,
		# and the report prints the verdict it WOULD have carried next to the
		# reason it does not count. An exclusion nobody can see is a blind spot
		# wearing a decision's clothes.
		if [[ -n ${ALLOWLIST[${key}]+set} ]]; then
			ALLOW_ROWS+=( "${record}" )
			continue
		fi

		[[ ${sys} == "PASS" ]] && SYS_PASS=$(( SYS_PASS + 1 ))
		[[ ${user} == "PASS" ]] && USER_PASS=$(( USER_PASS + 1 ))

		# Rows count packages, findings count findings, and the two differ:
		# sci-ml/lemonade-bin fails on both axes and is ONE row carrying TWO.
		local findings=0
		if [[ ${sys} == "FAIL" ]]; then
			SYS_FAIL=$(( SYS_FAIL + 1 ))
			findings=$(( findings + 1 ))
		fi
		if [[ ${user} == "WARN" ]]; then
			USER_WARN=$(( USER_WARN + 1 ))
			findings=$(( findings + 1 ))
		fi
		if (( findings > 0 )); then
			FINDING_ROWS=$(( FINDING_ROWS + 1 ))
		fi

		# Printed when it says something, or whenever the caller asked about
		# named packages. See the USAGE note in the header.
		if (( findings > 0 )) || [[ -n ${FILTER} ]]; then
			REPORT_ROWS+=( "${record}" )
		fi
	done

	if (( matched == 0 )); then
		if [[ -n ${FILTER} ]]; then
			printf 'filter %s matched no package under %s\n' \
				"${FILTER}" "${OVERLAY_ROOT}" >&2
		else
			printf 'no directory under %s holds an ebuild\n' "${OVERLAY_ROOT}" >&2
		fi
		printf 'nothing was classified, and an empty report reads exactly like a\n' >&2
		printf 'clean one\n' >&2
		return 2
	fi
}

### the report #######################################################

print_row() { # <record>
	local key sys user file su uu si ui

	IFS=${FS} read -r key sys user file su uu si ui <<<"$1"

	printf '%-38s  system=%-4s  user=%s\n' "${key}" "${sys}" "${user}"

	case ${sys} in
	FAIL)
		printf '    system unit installed at %s:%s\n' "${file}" "${su}"
		printf '    MISSING: an OpenRC init script in /etc/init.d (newinitd or doinitd)\n'
		;;
	PASS)
		printf '    system unit %s:%s, init script %s:%s\n' \
			"${file}" "${su}" "${file}" "${si}"
		;;
	esac

	case ${user} in
	WARN)
		printf '    user unit installed at %s:%s\n' "${file}" "${uu}"
		printf '    MISSING: a user-scope OpenRC script in /etc/user/init.d\n'
		printf '             (exeinto /etc/user/init.d, then newexe or doexe)\n'
		;;
	PASS)
		printf '    user unit %s:%s, user init script %s:%s\n' \
			"${file}" "${uu}" "${file}" "${ui}"
		;;
	esac
}

print_allow_row() { # <record>
	local key sys user file su uu si ui reason_line
	local lead='    reason: '

	IFS=${FS} read -r key sys user file su uu si ui <<<"$1"

	printf '%-38s  system=%-4s  user=%-4s  -> EXCLUDED\n' "${key}" "${sys}" "${user}"
	[[ -n ${su} ]] && printf '    system unit at %s:%s\n' "${file}" "${su}"
	[[ -n ${uu} ]] && printf '    user unit at %s:%s\n' "${file}" "${uu}"
	while IFS= read -r reason_line; do
		printf '%s%s\n' "${lead}" "${reason_line}"
		lead='            '
	done <<<"${ALLOWLIST[${key}]}"
}

print_report() {
	local record

	printf 'openrc-coverage  %s\n' "${OVERLAY_ROOT}"
	printf 'scope            %s\n' "${FILTER:-whole overlay}"
	printf '\n'

	printf '== Rows  (system gap = FAIL and drives the exit code; user gap = WARN and does not)\n\n'
	if (( ${#REPORT_ROWS[@]} == 0 )); then
		printf '(none)\n'
	else
		for record in "${REPORT_ROWS[@]}"; do
			print_row "${record}"
		done
	fi
	printf '\n'

	printf '== Allowlisted by policy  (classified, then excluded - never silently dropped)\n\n'
	if (( ${#ALLOW_ROWS[@]} == 0 )); then
		printf '(none)\n'
	else
		for record in "${ALLOW_ROWS[@]}"; do
			print_allow_row "${record}"
		done
	fi
	printf '\n'

	printf '== Summary\n\n'
	printf '  packages classified          %4d\n' "${SCANNED}"
	printf '    installing a unit          %4d\n' "${UNIT_PACKAGES}"
	printf '    system scope PASS          %4d\n' "${SYS_PASS}"
	printf '    user scope PASS            %4d\n' "${USER_PASS}"
	if (( NO_EBUILD_DIRS > 0 )); then
		printf '  directories with no ebuild   %4d  (nothing to classify)\n' "${NO_EBUILD_DIRS}"
	fi
	printf '  allowlisted                  %4d\n' "${#ALLOW_ROWS[@]}"
	printf '\n'
	# Rows and findings are different numbers and both are printed, because a
	# package can fail on both axes at once. Collapsing them would either list
	# such a package twice or lose its second finding.
	printf '  rows with a finding          %4d\n' "${FINDING_ROWS}"
	printf '  findings                     %4d   (%d system FAIL, %d user WARN)\n' \
		"$(( SYS_FAIL + USER_WARN ))" "${SYS_FAIL}" "${USER_WARN}"
	if (( FINDING_ROWS != SYS_FAIL + USER_WARN )); then
		printf '  %d row(s) carry more than one finding: a package can miss both scopes\n' \
			"$(( SYS_FAIL + USER_WARN - FINDING_ROWS ))"
	fi
	printf '\n'

	if (( SYS_FAIL > 0 )); then
		printf 'RESULT  FAIL  %d system-scope gap(s)' "${SYS_FAIL}"
		(( USER_WARN > 0 )) && printf ', %d user-scope warning(s)' "${USER_WARN}"
		printf '\n'
		return 1
	fi

	if (( USER_WARN > 0 )); then
		printf 'RESULT  PASS  no system-scope gap; %d user-scope warning(s) reported\n' \
			"${USER_WARN}"
		return 0
	fi

	printf 'RESULT  PASS  no gap in %d classified package(s)\n' "${SCANNED}"
	return 0
}

### self test ########################################################

# self_test
# Sub-task 1.2 authors the assertions. The flag and the dispatch exist now so
# the interface design.md publishes is real from the first commit rather than
# appearing later.
#
# It returns 0 while asserting nothing, which is exactly the silent pass this
# script exists to prevent - so it says so, loudly, on stderr.
self_test() {
	printf 'self-test: NO ASSERTIONS YET.\n' >&2
	printf 'self-test: the harness is authored by sub-task 1.2; this exit 0 proves\n' >&2
	printf 'self-test: nothing about the classifier.\n' >&2
	return 0
}

### main #############################################################

main() {
	local rc=0

	parse_args "$@" || rc=$?
	if (( rc != 0 )); then
		return 2
	fi

	if (( SELF_TEST )); then
		self_test
		return $?
	fi

	check_preconditions || return 2

	sweep || return 2

	print_report || return 1
	return 0
}

main "$@"
