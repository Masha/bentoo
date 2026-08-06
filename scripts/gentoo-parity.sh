#!/usr/bin/env bash
# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
#
# Report where every bentoo package diverges from its ::gentoo counterpart.
#
# WHAT IT IS FOR
#
# An overlay that shadows ::gentoo accumulates silent drift: a package is forked
# for one reason, ::gentoo later ships the same fix, and the overlay copy stays
# behind forever because nothing ever compares the two. This script is that
# missing comparison. It reads the metadata of both trees, names every axis on
# which they differ, and writes the result to a report a human can act on.
#
# STRICTLY READ-ONLY
#
# It reads two package trees and writes two report files under .epic/. It never
# writes inside a package directory, never touches ::gentoo, and never runs git.
# A parity check that edits what it is measuring is not a measurement.
#
# USAGE
#
#   bash scripts/gentoo-parity.sh                    # full sweep, writes the reports
#   bash scripts/gentoo-parity.sh kde-plasma         # restrict to one category
#   bash scripts/gentoo-parity.sh kde-plasma/kwin    # restrict to one package
#   bash scripts/gentoo-parity.sh --self-test        # assertions only, no report
#
#   GENTOO_REPO=<path>   the ::gentoo tree to compare against
#                        (default /var/db/repos/gentoo)
#
# Exit status:
#   0  the sweep found nothing to act on, or every self-test assertion passed
#   1  a divergence needing action was found, or a self-test assertion failed
#   2  a precondition or a usage error - nothing was compared
#   3  the pipeline is still a skeleton; some stage is not implemented yet.
#      Temporary, and gone once the last stage below is filled in.

set -euo pipefail

### where things live ################################################

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
OVERLAY_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd -P)

# Overridable so the sweep can run against a checkout somewhere else - a
# container, a second sync, a machine that keeps its trees elsewhere.
GENTOO_REPO=${GENTOO_REPO:-/var/db/repos/gentoo}

# Both reports live with the story that produced them. .epic/ is gitignored,
# which is exactly why the script itself lives in scripts/ instead: the report
# is a snapshot, the guard that regenerates it has to outlive the story.
REPORT_DIR="${OVERLAY_ROOT}/.epic/stories/007-gentoo-parity-baseline"
PARITY_DATA="${REPORT_DIR}/parity-data.tsv"
PARITY_REPORT="${REPORT_DIR}/parity-report.md"

### command line #####################################################

SELF_TEST=0
FILTER=""

usage() {
	printf 'Usage: gentoo-parity.sh [--self-test] [<category>|<category>/<package>]\n'
	printf 'Env:   GENTOO_REPO   path to the ::gentoo tree (default /var/db/repos/gentoo)\n'
}

# validate_filter <argument>
# A filter is either <category> or <category>/<package>. Shape is checked here;
# whether it matches anything is the package-set stage's business. Both checks
# matter for the same reason: a filter that quietly selects nothing produces an
# empty report, and an empty report reads exactly like a clean one.
validate_filter() {
	local filter=$1
	local atom='[A-Za-z0-9][A-Za-z0-9+_.-]*'

	if [[ ${filter} =~ ^${atom}(/${atom})?$ ]]; then
		return 0
	fi

	printf 'not a category or a category/package: %s\n' "${filter}" >&2
	printf 'expected <category> (kde-plasma) or <category>/<package> (kde-plasma/kwin)\n' >&2
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

# Enforced for a sweep. The self-test only PROBES this, and deliberately does
# not gate on it: --self-test has to stay runnable on a machine with no
# ::gentoo checkout at all. Its assertions are measurements of two real trees,
# so without one they all fail with an empty observed value and a note saying
# why - which is the honest outcome, not a reason to refuse to run.
check_preconditions() {
	if [[ ! -d ${GENTOO_REPO} ]]; then
		printf 'precondition failed: no ::gentoo tree at %s\n' "${GENTOO_REPO}" >&2
		printf '  point GENTOO_REPO at a synced checkout, e.g.\n' >&2
		printf '  GENTOO_REPO=/path/to/gentoo bash scripts/gentoo-parity.sh\n' >&2
		return 2
	fi

	# A directory that exists but is not a repository would make every overlay
	# package look overlay-only, and the sweep would report total divergence
	# while having compared against nothing. Refuse instead.
	if [[ ! -f ${GENTOO_REPO}/profiles/repo_name ]]; then
		printf 'precondition failed: %s has no profiles/repo_name, so it is not a package tree\n' \
			"${GENTOO_REPO}" >&2
		return 2
	fi

	# The comparison reads metadata, not ebuilds. No md5-cache on either side
	# means there is nothing to compare, which is not the same as "no drift".
	# This is the coarse "does a cache exist at all" gate; whether a given
	# package's cache entry is stale is the md5-cache stage's job.
	local tree
	for tree in "${GENTOO_REPO}" "${OVERLAY_ROOT}"; do
		if [[ ! -d ${tree}/metadata/md5-cache ]]; then
			printf 'precondition failed: %s has no metadata/md5-cache to compare\n' \
				"${tree}" >&2
			return 2
		fi
	done
}

### pipeline #########################################################
#
# One function per stage, in execution order, each an obvious seam. Every stage
# is declared here and implemented later; until then it registers itself as
# pending so that an incomplete run can never be mistaken for a clean one.

PENDING_STAGES=()

# stage_pending <stage name>
stage_pending() {
	local stage=$1
	printf '  [PENDING] %s\n' "${stage}"
	PENDING_STAGES+=( "${stage}" )
}

### what the stages publish ##########################################
#
# The pipeline's entire output surface. A stage writes here; nothing reads a
# stage's internals. That is what lets the self-test assert on results rather
# than re-deriving them - an assertion that walked the two trees itself would
# still be green with every stage below deleted, and would be testing coreutils
# instead of this script.
#
# All of it is empty until the stage named beside each one is implemented,
# which is precisely why all eleven assertions are red today.

PARITY_SHARED_PACKAGES=()  # <category>/<pn> present in both trees      - stage 1
PARITY_SCOPE_EBUILDS=()    # <category>/<pf>, overlay side, in scope    - stage 1
PARITY_BASELINES=()        # <category>/<pf> TAB <baseline PV> TAB <distance>
                           #                                           - stage 2
PARITY_BEHIND=()           # <category>/<pn> whose overlay PV trails    - stage 2
PARITY_MD5_COVERED=()      # <category>/<pf> cached on BOTH sides       - stage 3
PARITY_IDENTICAL=()        # <category>/<pf> byte-identical to baseline - stage 6
PARITY_ROWS=()             # one divergence row per (ebuild, axis)      - stages 4-6

# A PARITY_ROWS entry carries the columns parity-data.tsv carries, tab
# separated, in this order (design.md -> sub-task 6.1):
#
#   1 category/pn   2 overlay PV      3 baseline PV      4 distance
#   5 axis          6 overlay value   7 ::gentoo value   8 verdict
#
# Stages 4 and 5 append rows; stage 6 fills column 8. Values must arrive with
# tabs and newlines already stripped - the report format has no escaping, and a
# row that splits is a row nobody notices is wrong.

# Where the # BENTOO-DIVERGENCE: tag parser reads an ebuild from, keyed by
# <category>/<pf>. Empty during a sweep: the tag belongs in the ebuild, which
# is the whole point of putting it there.
#
# It exists for one reason. The overlay carries zero tags today (measured
# 2026-08-06), and R7 makes this story read-only, so the only honest way to
# assert "JUSTIFIED once tagged" is to tag a copy the overlay never sees. The
# self-test writes that copy under $TMPDIR and registers it here.
#
# Sub-task 5.2's parser must resolve an ebuild through this map FIRST and fall
# back to ${OVERLAY_ROOT}/<category>/<pn>/<pf>.ebuild. That single lookup is
# the entire seam.
declare -A PARITY_TAG_SOURCE=()

# Stage 1. Enumerate the overlay's packages, honouring FILTER, and split them
# into those ::gentoo also carries and those it does not. Must fail loudly when
# a filter matches zero packages.
# Publishes: PARITY_SHARED_PACKAGES, PARITY_SCOPE_EBUILDS.
build_package_sets() {
	stage_pending 'build package sets'
}

# Stage 2. For each shared package, pick the ::gentoo version to compare
# against - the baseline the overlay copy is drifting from.
# Publishes: PARITY_BASELINES, PARITY_BEHIND.
select_baseline() {
	stage_pending 'select baseline'
}

# Stage 3. Confirm each side's md5-cache entry actually describes the ebuild on
# disk. Comparing a stale cache entry reports drift that does not exist, and
# hides drift that does.
# Publishes: PARITY_MD5_COVERED.
verify_md5_cache() {
	stage_pending 'verify md5-cache'
}

# Stage 4. Compare the metadata axes of overlay and baseline.
# Publishes: PARITY_ROWS (appends; column 8 left to stage 6).
compare_axes() {
	stage_pending 'compare axes'
}

# Stage 5. Compare what md5-cache does not carry: patches under files/,
# metadata.xml, and the tags read from the ebuild text.
# Publishes: PARITY_ROWS (appends; column 8 left to stage 6).
compare_auxiliary_files() {
	stage_pending 'compare auxiliary files'
}

# Stage 6. Turn the raw differences into a verdict per package.
# Publishes: PARITY_IDENTICAL, and column 8 of every PARITY_ROWS entry. Reads
# PARITY_TAG_SOURCE before the tracked ebuild when looking for a tag.
assign_verdicts() {
	stage_pending 'assign verdicts'
}

# Stage 7. Write the machine-readable table and the human-readable report.
write_reports() {
	stage_pending "write reports (${PARITY_DATA}, ${PARITY_REPORT})"
}

run_sweep() {
	check_preconditions || return 2

	printf 'overlay  : %s\n' "${OVERLAY_ROOT}"
	printf '::gentoo : %s\n' "${GENTOO_REPO}"
	printf 'filter   : %s\n' "${FILTER:-(none - full sweep)}"
	printf 'reports  : %s\n' "${REPORT_DIR}"
	printf '\n'

	build_package_sets
	select_baseline
	verify_md5_cache
	compare_axes
	compare_auxiliary_files
	assign_verdicts
	write_reports

	if (( ${#PENDING_STAGES[@]} )); then
		printf '\n%d pipeline stage(s) are not implemented yet:\n' \
			"${#PENDING_STAGES[@]}" >&2
		local stage
		for stage in "${PENDING_STAGES[@]}"; do
			printf '  - %s\n' "${stage}" >&2
		done
		printf 'nothing was compared and no report was written: an empty report\n' >&2
		printf 'would read as "no divergences found"\n' >&2
		return 3
	fi

	# The verdict lands here: non-zero when any package needs action.
	return 0
}

### self-test ########################################################
#
# Everything --self-test writes: one copy of one ebuild, under $TMPDIR, removed
# again before it returns. No report, and nothing anywhere near either package
# tree - see prepare_tag_scratch for why the copy has to exist at all.

ASSERT_TOTAL=0
FAILURES=()

# The one ebuild A09 needs a tag on. Pinned rather than discovered: the
# assertion is about a specific hand-inspected divergence, so a version that
# moved on is a stale assertion to re-measure, not a lookup to make dynamic.
SELF_TEST_TAGGED_PKG='kde-plasma/spectacle'
SELF_TEST_TAGGED_PV='6.7.4'

# q <value>
# Render a value for a report line: newlines flattened, empty made visible. On
# the first run every observed value IS empty, which is exactly the moment a
# line that prints nothing is least readable.
q() {
	local s=${1//$'\n'/ \\n }
	printf '%s' "${s:-(empty)}"
}

# assert_eq <id> <description> <expected> <actual>
# Never aborts. The value of this harness is the whole picture of what is and
# is not implemented; stopping at the first red hides the other ten.
assert_eq() {
	local id=$1 desc=$2 expected=$3 actual=$4

	ASSERT_TOTAL=$(( ASSERT_TOTAL + 1 ))

	if [[ ${actual} == "${expected}" ]]; then
		printf '  [PASS] (%s) %s\n' "${id}" "${desc}"
		return 0
	fi

	printf '  [FAIL] (%s) %s\n' "${id}" "${desc}"
	printf '         expected: %s\n' "$(q "${expected}")"
	printf '         observed: %s\n' "$(q "${actual}")"
	FAILURES+=( "(${id}) ${desc} | expected: $(q "${expected}") | observed: $(q "${actual}")" )
	return 0
}

### querying what the pipeline published ##############################

# baselines_at_distance <distance>
# How many ebuilds select_baseline placed at <distance>. The distance is the
# last of the three columns.
baselines_at_distance() {
	local wanted=$1 line distance count=0

	for line in "${PARITY_BASELINES[@]}"; do
		distance=${line##*$'\t'}
		if [[ ${distance} == "${wanted}" ]]; then
			count=$(( count + 1 ))
		fi
	done
	printf '%d' "${count}"
}

# verdict_count <verdict>
# How many divergence rows carry <verdict>. The verdict is the last column.
verdict_count() {
	local wanted=$1 row verdict count=0

	for row in "${PARITY_ROWS[@]}"; do
		verdict=${row##*$'\t'}
		if [[ ${verdict} == "${wanted}" ]]; then
			count=$(( count + 1 ))
		fi
	done
	printf '%d' "${count}"
}

# select_rows <category/pn> <PV> <axis> <value> <column>
# Query the divergence table. An empty <PV>, <axis> or <value> matches
# anything. <value> is matched as a substring of the overlay and ::gentoo
# values joined, so an assertion can pin what a row SAYS without pinning how
# the stage that emitted it chose to format the two sides.
#
# Prints the distinct values of <column> across every matching row - sorted,
# space separated - or the placeholder below. Never nothing: an observed value
# of "" would silently agree with an expected value of "".
select_rows() {
	local want_pkg=$1 want_pv=$2 want_axis=$3 want_value=$4 column=$5
	local row pkg opv distance axis overlay gentoo verdict picked out
	local -a hits=()

	for row in "${PARITY_ROWS[@]}"; do
		IFS=$'\t' read -r pkg opv _ distance axis overlay gentoo verdict <<<"${row}"

		[[ ${pkg} == "${want_pkg}" ]] || continue
		[[ -z ${want_pv} || ${opv} == "${want_pv}" ]] || continue
		[[ -z ${want_axis} || ${axis} == "${want_axis}" ]] || continue
		[[ -z ${want_value} || "${overlay} ${gentoo}" == *"${want_value}"* ]] || continue

		case ${column} in
		axis)     picked=${axis} ;;
		verdict)  picked=${verdict} ;;
		distance) picked=${distance} ;;
		overlay)  picked=${overlay} ;;
		gentoo)   picked=${gentoo} ;;
		*)        picked="(select_rows: no column named ${column})" ;;
		esac
		hits+=( "${picked}" )
	done

	if (( ${#hits[@]} == 0 )); then
		printf '(no matching divergence row)'
		return 0
	fi

	out=$(printf '%s\n' "${hits[@]}" | sort -u | tr '\n' ' ')
	printf '%s' "${out% }"
}

# arch_set <KEYWORDS value>
# A keyword list reduced to a comparable set: ~ stripped, sorted, deduplicated.
#
# Deliberately a second implementation of the normalisation the comparator
# performs, rather than a call into it. A harness that reuses the code under
# test agrees with it by construction - including when both are wrong.
arch_set() {
	printf '%s\n' "$1" | tr ' ' '\n' | sed -e 's/^~//' -e '/^$/d' | sort -u | tr '\n' ' '
}

# keywords_false_positives
# KEYWORDS rows that say nothing: both sides carry the same arch set once the ~
# is stripped. ::gentoo stabilises and the overlay does not, so an unnormalised
# comparison emits one of these for essentially every shared package. They are
# the noise the arch-set normalisation exists to remove, and every one that
# survives is a reader trained to skim the report.
keywords_false_positives() {
	local row axis overlay gentoo count=0

	for row in "${PARITY_ROWS[@]}"; do
		IFS=$'\t' read -r _ _ _ _ axis overlay gentoo _ <<<"${row}"
		[[ ${axis} == KEYWORDS ]] || continue
		if [[ "$(arch_set "${overlay}")" == "$(arch_set "${gentoo}")" ]]; then
			count=$(( count + 1 ))
		fi
	done
	printf '%d' "${count}"
}

### driving the pipeline for the self-test ############################

# prepare_tag_scratch <scratch dir>
# A09 asserts a verdict no ebuild in the tree can currently produce: the
# overlay carries zero # BENTOO-DIVERGENCE: tags (measured 2026-08-06), and R7
# makes this story read-only - a guard that edits an ebuild to test its own tag
# parser is editing what it measures.
#
# So the tag goes on a COPY under the scratch directory, registered in
# PARITY_TAG_SOURCE. The overlay is only ever read. This is the seam sub-task
# 5.2 fills: its parser looks an ebuild up in that map before falling back to
# the tracked file, and nothing else about the pipeline changes.
#
# Called BEFORE the stages run, so the override is in place when the verdicts
# are assigned.
prepare_tag_scratch() {
	local scratch=$1
	local category=${SELF_TEST_TAGGED_PKG%%/*}
	local pn=${SELF_TEST_TAGGED_PKG##*/}
	local pf="${pn}-${SELF_TEST_TAGGED_PV}"
	local src="${OVERLAY_ROOT}/${SELF_TEST_TAGGED_PKG}/${pf}.ebuild"
	local copy="${scratch}/${pf}.ebuild"

	if [[ ! -f ${src} ]]; then
		printf '  [NOTE] no %s to copy, so A09 can only fail\n' "${src}"
		printf '         either the package moved on, or the assertion needs repinning\n'
		return 0
	fi

	cp -- "${src}" "${copy}"
	printf '\n# BENTOO-DIVERGENCE: PATCHES - opencv5 fix not in ::gentoo yet\n' >>"${copy}"
	PARITY_TAG_SOURCE["${category}/${pf}"]=${copy}

	printf '  [SEAM] tag source %s -> %s\n' \
		"${category}/${pf}" "${PARITY_TAG_SOURCE["${category}/${pf}"]}"
}

# self_test_pipeline
# Drives the real stages, in the sweep's order. write_reports is deliberately
# not called: the self-test proves the numbers, it does not publish them.
#
# check_preconditions is probed rather than enforced. --self-test must stay
# runnable with no ::gentoo checkout, but the eleven facts below are
# measurements of two real trees and cannot be confirmed without one. A missing
# tree therefore says so and skips the stages, leaving every measurement empty
# and failing. Staying silent would be worse: eleven reds that look like the
# script disagreeing with the numbers, when it never got to look.
self_test_pipeline() {
	if ! check_preconditions 2>/dev/null; then
		printf '  [NOTE] no usable ::gentoo tree at %s\n' "${GENTOO_REPO}"
		printf '         every measurement below reads empty and fails: that is a\n'
		printf '         missing precondition, not a disagreement with the numbers\n'
		return 0
	fi

	build_package_sets
	select_baseline
	verify_md5_cache
	compare_axes
	compare_auxiliary_files
	assign_verdicts
}

### the eleven assertions #############################################
#
# design.md's Testing Strategy table, executable. The numbers were measured by
# hand on 2026-08-05 and re-measured on 2026-08-06. A run that does not
# reproduce them is wrong, or the measurement is stale and gets RE-MEASURED and
# recorded - never loosened until it agrees.
#
# Each one increments ASSERT_TOTAL and appends to FAILURES on failure, so the
# verdict below stays as written:
#
#   assert_eq <id> <description> <expected> <actual>
#
# Two rules hold for all eleven:
#
#   READ THE PIPELINE, NOT THE TREES. Every observed value comes from what a
#   stage published. An assertion that counted the ebuilds itself would be
#   green with every stage deleted, which is worse than having no assertion.
#
#   NEVER PASS ON NOTHING. Where the expected value is 0, it is paired with a
#   denominator or with a signal known to exist, because "0 out of nothing" and
#   "0 out of 319" are otherwise the same string - and the first is the state
#   this script is in today. An assertion that goes green before the logic it
#   guards exists is a defect, not progress.
self_test_assertions() {
	local scratch
	scratch=$(mktemp -d "${TMPDIR:-/tmp}/gentoo-parity-selftest.XXXXXX")

	printf 'overlay  : %s\n' "${OVERLAY_ROOT}"
	printf '::gentoo : %s\n' "${GENTOO_REPO}"
	printf 'scratch  : %s\n' "${scratch}"
	printf '\npipeline\n'

	prepare_tag_scratch "${scratch}"
	self_test_pipeline

	printf '\nassertions\n'

	# --- what is being compared at all --------------------------------

	assert_eq A01 \
		'shared packages: the overlay packages ::gentoo also carries' \
		'232' "${#PARITY_SHARED_PACKAGES[@]}"

	# 319 is design.md's figure. An independent count on 2026-08-06 using the
	# same definition - every .ebuild inside a shared package - returned 321,
	# while 232 / 82 / 76 / 67 all reproduced exactly. Encoded as designed and
	# flagged rather than quietly adjusted: sub-task 7.1 re-measures and
	# records which is right. Two ebuilds is a bump, not a rounding error.
	assert_eq A02 \
		'ebuilds in scope: every overlay ebuild inside a shared package' \
		'319' "${#PARITY_SCOPE_EBUILDS[@]}"

	# Paired with its denominator: 0/0 and 319/319 must not read alike.
	assert_eq A07 \
		'md5-cache coverage: an entry exists on both sides for every ebuild in scope' \
		'319/319' "${#PARITY_MD5_COVERED[@]}/${#PARITY_SCOPE_EBUILDS[@]}"

	# --- what each ebuild is compared against -------------------------

	assert_eq A03 \
		'exact-distance ebuilds: ::gentoo carries the same PV' \
		'76' "$(baselines_at_distance exact)"

	# The live-ebuild trap, and the reason this one carries a denominator:
	# including 9999 in the version sort made a first pass report 34 packages
	# as behind ::gentoo when none are. Zero behind out of zero baselines
	# selected is the bug looking exactly like the fix.
	assert_eq A06 \
		'packages behind ::gentoo: none, once live ebuilds leave the version sort' \
		'behind=0 baselines=319' \
		"behind=${#PARITY_BEHIND[@]} baselines=${#PARITY_BASELINES[@]}"

	# --- what the comparison concluded --------------------------------

	assert_eq A04 \
		'byte-identical ebuilds: cmp against the exact baseline agrees' \
		'67' "${#PARITY_IDENTICAL[@]}"

	assert_eq A05 \
		'REDUNDANT verdicts: one per byte-identical ebuild, its axis rows suppressed' \
		'67' "$(verdict_count REDUNDANT)"

	# PYTHON_COMPAT never reaches md5-cache under that name - python-any-r1
	# expands it into the BDEPEND any-of block - so at kwin-6.7.4 the only
	# trace is dev-lang/python:3.15, which ::gentoo requires and the overlay
	# does not (verified 2026-08-06; it is the ONLY md5-cache difference the
	# two copies have). Matched on the value rather than on an axis name so
	# the assertion survives whichever axis sub-task 3.3 files it under.
	assert_eq A08 \
		'kwin-6.7.4 PYTHON_COMPAT drift is ALIGN: the overlay is behind, not customised' \
		'ALIGN' "$(select_rows kde-plasma/kwin 6.7.4 '' dev-lang/python verdict)"

	# The one verdict that needs a tag, and the tag lives on the scratch copy
	# prepare_tag_scratch made. PATCHES is an ebuild-level axis on purpose: it
	# is where the tag can sit. The same divergence also shows up under the
	# file-level files/ axis, which by design carries no justification
	# mechanism at all (design.md, decided at the Phase 1 gate).
	assert_eq A09 \
		'spectacle-6.7.4 PATCHES is JUSTIFIED once a tag names that axis' \
		'JUSTIFIED' \
		"$(select_rows "${SELF_TEST_TAGGED_PKG}" "${SELF_TEST_TAGGED_PV}" PATCHES '' verdict)"

	# Both halves are needed. Zero false positives is trivially true when no
	# KEYWORDS row was ever emitted, so the assertion also demands the signal
	# the normalisation must NOT suppress: mesa keeps ~amd64-linux and
	# ~x86-linux, which ::gentoo does not carry, and that survives ~ stripping
	# (verified 2026-08-06). No PV is pinned - mesa is bumped daily here.
	assert_eq A10 \
		'KEYWORDS: no row explainable by ~ alone, and mesa still reports its real one' \
		'false-positives=0 mesa-signal=KEYWORDS' \
		"false-positives=$(keywords_false_positives) mesa-signal=$(select_rows media-libs/mesa '' KEYWORDS '' axis)"

	# ::gentoo inherits cargo and flag-o-matic at this PV and the overlay
	# inherits neither: the overlay ebuild predates an upstream refactor made
	# at the same version. Matched on cargo appearing in the row's values, so
	# the assertion holds whether the stage reports the full INHERIT set or
	# only the delta.
	assert_eq A11 \
		'kdeplasma-addons-6.7.4 INHERIT divergence is detected: ::gentoo has cargo and flag-o-matic, the overlay neither' \
		'INHERIT' \
		"$(select_rows kde-plasma/kdeplasma-addons 6.7.4 INHERIT cargo axis)"

	rm -rf -- "${scratch}"
}

run_self_test() {
	self_test_assertions

	# A harness that ran nothing must not report success. "0 assertions, all
	# passed" is the single most misleading line a guard can print, and every
	# way of getting there - assertions not written yet, a phase that silently
	# returned early - is a defect worth an exit code.
	if (( ASSERT_TOTAL == 0 )); then
		printf 'the self-test ran no assertions, so it proved nothing\n' >&2
		return 1
	fi

	if (( ${#FAILURES[@]} == 0 )); then
		printf '\n%d assertions, all passed\n' "${ASSERT_TOTAL}"
		return 0
	fi

	printf '\n%d assertions, %d FAILED:\n' "${ASSERT_TOTAL}" "${#FAILURES[@]}"
	local failure
	for failure in "${FAILURES[@]}"; do
		printf '  - %s\n' "${failure}"
	done
	return 1
}

### run ##############################################################

main() {
	local rc=0

	parse_args "$@" || exit $?

	if (( SELF_TEST )); then
		run_self_test || rc=$?
		exit "${rc}"
	fi

	run_sweep || rc=$?
	exit "${rc}"
}

main "$@"
