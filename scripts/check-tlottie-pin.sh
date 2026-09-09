#!/usr/bin/env bash
# Assert that media-libs/tlottie is pinned to the commit the packaged
# net-im/telegram-desktop actually asks for.
#
# tlottie is a personal repository with NO tags and NO releases, so "the newest
# commit on main" is not a version -- it is just whatever its author pushed
# last. The only authority over which commit is correct is tdesktop itself:
# Telegram/build/prepare/prepare.py carries a `stage('tlottie', ...)` block that
# does `git checkout <sha>`, and that sha is the one the release was built and
# tested against. (The same value is repeated in
# Telegram/build/docker/centos_env/Dockerfile; this check reads prepare.py,
# which is the file upstream edits first.)
#
# .autoupdate/packages.toml cannot catch a drift here, and no amount of
# reconfiguring would let it. Reaching the pin needs three CHAINED reads --
# tdesktop version in the overlay -> raw prepare.py at that tag -> sha -> the
# tlottie commit API for that sha -> date for the _pre<YYYYMMDD> suffix -- and
# the record model composes none of them: base_from takes only
# "file"|"tag"|"commit_message"|"none" and yields a PARALLEL base version, never
# a value chained off the sha, while fallback_* is a failure fallback rather
# than a second axis. So the registry probes dkaraush/tlottie's main branch,
# which is the wrong authority by construction, and its record carries
# hold = true for exactly that reason. What the hold blocks is the apply; the
# check still arms a pending, and that pending is wrong every day upstream is
# ahead of the pin. Measured 2026-09-08: main was at 4b940c79 while tdesktop
# 7.2.7 pinned 758c7cb744 -- two days of drift, already in the queue.
#
# Why the drift is worse than an ordinary stale pin: the ebuild installs
# `dolib.a libtlottie.a`, a STATIC archive linked into the Telegram binary.
# There is no soname, so neither Portage nor revdep-rebuild can observe the
# mismatch. A wrong tlottie does not fail to build and does not trip pkgcheck --
# it silently ships a Telegram whose animation renderer is not the one upstream
# shipped, and a bump therefore has to revbump net-im/telegram-desktop in the
# same commit.
#
# This script is the inverse of what the registry does: it never proposes a
# version, it only asserts that the two pins still agree.
#
# Deliberately NOT wired into .git/hooks/pre-commit, for the same reason as
# check-edk2-dbx-freshness.sh: it needs the network, and a guard that turns red
# offline is a guard people learn to skip. Run it in upstream sweeps, and after
# any telegram-desktop bump.
#
# Usage: bash scripts/check-tlottie-pin.sh [--self-test]
# Exit:  0 the pins agree; 1 they diverge, naming both shas;
#        2 could not determine (network/API), which is NOT a gap.

set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
raw_base='https://raw.githubusercontent.com/telegramdesktop/tdesktop'
commit_api='https://api.github.com/repos/dkaraush/tlottie/commits'

# --- pure helpers -----------------------------------------------------------
# Kept as functions so --self-test can exercise them against fixtures, without
# touching the tree and without the network.

# Strip category prefix and Gentoo revision from an ebuild filename to get the
# upstream tag component. telegram-desktop-7.2.7-r1.ebuild -> 7.2.7, because
# upstream tags v7.2.7 and knows nothing about our -r1.
pv_from_ebuild_name() {
	local base=$1 pv
	base=${base##*/}
	base=${base%.ebuild}
	pv=${base#telegram-desktop-}
	[[ ${pv} != "${base}" ]] || return 1
	printf '%s\n' "${pv%-r+([0-9])}"
}

# Read the sha out of the tlottie stage of a prepare.py. Anchored on the stage
# header and stopped at the next one: `git checkout` appears in most of the
# ~60 stages in that file, so an unanchored grep would return whichever
# dependency happens to come first.
extract_stage_sha() {
	local file=$1 sha
	sha=$(awk "
		/^stage\('tlottie'/ { inside = 1; next }
		inside && /^stage\(/ { exit }
		inside && \$1 == \"git\" && \$2 == \"checkout\" { print \$3; exit }
	" "${file}")
	[[ -n ${sha} ]] || return 1
	printf '%s\n' "${sha}"
}

extract_egit_commit() {
	local file=$1 sha
	sha=$(sed -nE 's/^EGIT_COMMIT="([0-9a-fA-F]+)".*/\1/p' "${file}" | head -n1)
	[[ -n ${sha} ]] || return 1
	printf '%s\n' "${sha}"
}

# The pin in prepare.py is ABBREVIATED (758c7cb744, 10 chars) while the ebuild
# carries the full 40. Compare by prefix, and refuse an abbreviation short
# enough to be ambiguous -- a 4-char "match" is not evidence of anything.
sha_matches() {
	local full=${1,,} abbrev=${2,,}
	(( ${#abbrev} >= 7 )) || return 1
	[[ ${full} == "${abbrev}"* ]]
}

# 2026-09-06T13:36:54Z -> 20260906
iso_date_to_stamp() {
	local iso=$1
	[[ ${iso} =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})T ]] || return 1
	printf '%s%s%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
}

# tlottie-0.1.0_pre20260906.ebuild -> 20260906
stamp_from_tlottie_ebuild_name() {
	local base=$1
	base=${base##*/}
	[[ ${base} =~ _pre([0-9]{8})(-r[0-9]+)?\.ebuild$ ]] || return 1
	printf '%s\n' "${BASH_REMATCH[1]}"
}

# --- self-test --------------------------------------------------------------

if [[ ${1:-} == --self-test ]]; then
	shopt -s extglob
	tmp=$(mktemp -d)
	trap 'rm -rf -- "${tmp}"' EXIT
	fail() { echo "self-test: $*" >&2; exit 1; }

	[[ $(pv_from_ebuild_name telegram-desktop-7.2.7.ebuild) == 7.2.7 ]] ||
		fail "plain PV not extracted"
	[[ $(pv_from_ebuild_name /a/b/telegram-desktop-7.2.7-r1.ebuild) == 7.2.7 ]] ||
		fail "revision not stripped from PV"
	[[ $(pv_from_ebuild_name telegram-desktop-7.2.7-r12.ebuild) == 7.2.7 ]] ||
		fail "multi-digit revision not stripped from PV"
	if pv_from_ebuild_name some-other-package-1.0.ebuild >/dev/null 2>&1; then
		fail "a foreign ebuild name should not yield a PV"
	fi

	# A prepare.py shaped like the real one: several stages, each with its own
	# `git checkout`, tlottie in the middle.
	cat >"${tmp}/prepare.py" <<'PY'
stage('lz4', """
    git clone https://github.com/lz4/lz4.git
    cd lz4
    git checkout deadbeefdeadbeef
""")

stage('tlottie', """
    git clone https://github.com/dkaraush/tlottie.git
    cd tlottie
    git checkout 758c7cb744
win:
    SET "RUSTUP_HOME=%THIRDPARTY_DIR%\\rust\\rustup"
""")

stage('openssl3', """
    git clone https://github.com/openssl/openssl openssl3
    cd openssl3
    git checkout cafebabecafebabe
""")
PY
	[[ $(extract_stage_sha "${tmp}/prepare.py") == 758c7cb744 ]] ||
		fail "the tlottie stage sha was not the one returned"

	# The anchor has to survive tlottie being the LAST stage, too.
	sed '/^stage(.openssl3/,$d' "${tmp}/prepare.py" >"${tmp}/last.py"
	[[ $(extract_stage_sha "${tmp}/last.py") == 758c7cb744 ]] ||
		fail "extraction failed when tlottie is the final stage"

	# And it must report absence rather than borrowing a neighbour's sha: this
	# is how the check learns that upstream dropped tlottie.
	sed '/^stage(.tlottie/,/^""")/d' "${tmp}/prepare.py" >"${tmp}/gone.py"
	if extract_stage_sha "${tmp}/gone.py" >/dev/null 2>&1; then
		fail "a prepare.py without a tlottie stage must not yield a sha"
	fi

	printf 'EGIT_COMMIT="758c7cb74444f1c3c9923065c40fdb3aad8b7d60"\n' >"${tmp}/a.ebuild"
	[[ $(extract_egit_commit "${tmp}/a.ebuild") == 758c7cb74444f1c3c9923065c40fdb3aad8b7d60 ]] ||
		fail "EGIT_COMMIT not extracted"
	printf 'NOTHING=1\n' >"${tmp}/b.ebuild"
	if extract_egit_commit "${tmp}/b.ebuild" >/dev/null 2>&1; then
		fail "extraction should fail when EGIT_COMMIT is absent"
	fi

	sha_matches 758c7cb74444f1c3c9923065c40fdb3aad8b7d60 758c7cb744 ||
		fail "abbreviated pin did not match its full sha"
	sha_matches 758C7CB74444F1C3C9923065C40FDB3AAD8B7D60 758c7cb744 ||
		fail "comparison is not case-insensitive"
	sha_matches 758c7cb74444f1c3c9923065c40fdb3aad8b7d60 4b940c7942 &&
		fail "a different sha was accepted as a match"
	sha_matches 758c7cb74444f1c3c9923065c40fdb3aad8b7d60 758c &&
		fail "a 4-char abbreviation is ambiguous and must be refused"

	[[ $(iso_date_to_stamp 2026-09-06T13:36:54Z) == 20260906 ]] ||
		fail "ISO date not converted to a _pre stamp"
	if iso_date_to_stamp "not a date" >/dev/null 2>&1; then
		fail "a malformed date must not yield a stamp"
	fi

	[[ $(stamp_from_tlottie_ebuild_name tlottie-0.1.0_pre20260906.ebuild) == 20260906 ]] ||
		fail "stamp not read from the ebuild name"
	[[ $(stamp_from_tlottie_ebuild_name tlottie-0.1.0_pre20260906-r1.ebuild) == 20260906 ]] ||
		fail "stamp not read from a revbumped ebuild name"
	if stamp_from_tlottie_ebuild_name tlottie-0.1.0.ebuild >/dev/null 2>&1; then
		fail "a non-snapshot version must not yield a stamp"
	fi

	echo "self-test: OK (17 assertions)"
	exit 0
fi

shopt -s extglob nullglob

# --- our side of the pin ----------------------------------------------------

tlottie_ebuilds=( "${repo}"/media-libs/tlottie/tlottie-*.ebuild )
tdesktop_ebuilds=( "${repo}"/net-im/telegram-desktop/telegram-desktop-*.ebuild )

(( ${#tdesktop_ebuilds[@]} )) ||
	{ echo "no ebuild found under ${repo}/net-im/telegram-desktop" >&2; exit 1; }

if (( ${#tlottie_ebuilds[@]} == 0 )); then
	echo "no ebuild found under ${repo}/media-libs/tlottie" >&2
	echo "  if telegram-desktop still depends on it, the dependency is unsatisfiable" >&2
	exit 1
fi
if (( ${#tlottie_ebuilds[@]} > 1 )); then
	echo "more than one tlottie ebuild is present; each telegram-desktop below" >&2
	echo "  is checked against every one of them, and a pin that matches none" >&2
	echo "  is the gap:" >&2
	printf '    %s\n' "${tlottie_ebuilds[@]##*/}" >&2
fi

rc=0
indeterminate=0

for tdesktop in "${tdesktop_ebuilds[@]}"; do
	name=${tdesktop##*/}

	if ! pv=$(pv_from_ebuild_name "${tdesktop}"); then
		echo "${name}: filename does not parse as telegram-desktop-<PV>.ebuild" >&2
		rc=1
		continue
	fi

	declares_dep=0
	grep -qE '^[[:space:]]*media-libs/tlottie([[:space:]:]|$)' "${tdesktop}" && declares_dep=1

	url="${raw_base}/v${pv}/Telegram/build/prepare/prepare.py"
	prepare=$(curl -sL --fail --max-time 30 -H 'User-Agent: bentoo-autoupdate' "${url}") || prepare=''

	if [[ -z ${prepare} ]]; then
		echo "${name}: could not read prepare.py at v${pv}" >&2
		echo "  ${url}" >&2
		echo "  treating as INDETERMINATE, not as a gap" >&2
		indeterminate=1
		continue
	fi

	prepare_file=$(mktemp)
	printf '%s\n' "${prepare}" >"${prepare_file}"
	upstream_sha=$(extract_stage_sha "${prepare_file}" || true)
	rm -f -- "${prepare_file}"

	# Upstream and the ebuild have to agree on WHETHER tlottie is used at all,
	# before there is any point comparing shas.
	if [[ -z ${upstream_sha} ]]; then
		if (( declares_dep )); then
			echo "${name}: DEPENDs on media-libs/tlottie, but v${pv}'s prepare.py has no" >&2
			echo "  tlottie stage -- upstream dropped it, or the stage was renamed." >&2
			echo "  Drop the dependency, or find what replaced it." >&2
			rc=1
		else
			echo "${name}: v${pv} does not use tlottie, and the ebuild does not depend on it"
		fi
		continue
	fi
	if (( ! declares_dep )); then
		echo "${name}: v${pv}'s prepare.py pins tlottie ${upstream_sha}, but the ebuild" >&2
		echo "  declares no dependency on media-libs/tlottie -- the build will fall back" >&2
		echo "  to whatever it bundles, or fail to find the library." >&2
		rc=1
		continue
	fi

	matched=''
	for tlottie in "${tlottie_ebuilds[@]}"; do
		if ! ours=$(extract_egit_commit "${tlottie}"); then
			echo "${tlottie##*/}: no EGIT_COMMIT found -- the ebuild changed shape," >&2
			echo "  so this check is blind to what it actually packages" >&2
			rc=1
			continue
		fi
		if sha_matches "${ours}" "${upstream_sha}"; then
			matched=${tlottie}
			break
		fi
	done

	if [[ -z ${matched} ]]; then
		echo "${name}: tlottie pin diverged" >&2
		echo "  v${pv} prepare.py asks for : ${upstream_sha}" >&2
		for tlottie in "${tlottie_ebuilds[@]}"; do
			ours=$(extract_egit_commit "${tlottie}" 2>/dev/null || echo '<none>')
			echo "  ${tlottie##*/} carries : ${ours}" >&2
		done
		echo "  The archive is linked STATICALLY into the Telegram binary, so this is" >&2
		echo "  an ABI change with no soname to catch it. Fix by setting EGIT_COMMIT to" >&2
		echo "  the sha above, setting PV to that commit's date, regenerating the" >&2
		echo "  Manifest, and revbumping net-im/telegram-desktop in the SAME commit." >&2
		rc=1
		continue
	fi

	echo "${name}: pin agrees -- v${pv} asks for ${upstream_sha}, ${matched##*/} carries it"

	# Secondary, and deliberately non-fatal on failure: the _pre<YYYYMMDD> in PV
	# has to be the pinned commit's own date. The Manifest already ties the
	# distfile to EGIT_COMMIT, so a wrong stamp ships the right code under a
	# misleading version -- cosmetic to the compiler, actively misleading to the
	# next person deciding whether a bump is needed.
	if ! stamp=$(stamp_from_tlottie_ebuild_name "${matched}"); then
		continue
	fi
	if ! command -v python3 >/dev/null 2>&1; then
		echo "  (skipping the PV date cross-check: python3 not available)"
		continue
	fi
	committed=$(curl -sL --fail --max-time 30 -H 'User-Agent: bentoo-autoupdate' \
		"${commit_api}/${upstream_sha}" 2>/dev/null |
		python3 -c 'import json,sys; print(json.load(sys.stdin)["commit"]["committer"]["date"])' \
		2>/dev/null) || committed=''
	if [[ -z ${committed} ]]; then
		echo "  (skipping the PV date cross-check: the commit API did not answer)"
		continue
	fi
	if ! expected=$(iso_date_to_stamp "${committed}"); then
		echo "  (skipping the PV date cross-check: unparseable date ${committed})"
		continue
	fi
	if [[ ${stamp} != "${expected}" ]]; then
		echo "${matched##*/}: PV date does not match the pinned commit" >&2
		echo "  PV says _pre${stamp}, but ${upstream_sha} was committed ${committed}" >&2
		echo "  Rename the ebuild to _pre${expected} and regenerate the Manifest." >&2
		rc=1
	else
		echo "  PV date _pre${stamp} matches the pinned commit's date"
	fi
done

if (( rc == 0 && indeterminate )); then
	exit 2
fi
exit "${rc}"
