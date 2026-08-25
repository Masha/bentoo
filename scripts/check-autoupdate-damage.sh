#!/usr/bin/env bash
# Assert that the autoupdate applier did not rewrite more than it was asked to.
#
#     scripts/check-autoupdate-damage.sh [--staged] [--all]
#
# The applier does a textual pass over each record it bumps. Twice this month
# that pass reached past its target, and both times the damage was invisible at
# review: the file still parses, the ebuild still sources, pkgcheck stays clean,
# and the failure surfaces days later somewhere else entirely.
#
# CLASS 1 -- a deleted `enabled = false`.
#   Some records are pinned OFF on purpose. dev-libs/icu-compat and
#   media-libs/libjxl-compat exist only to carry an old ABI for
#   www-client/orion-bin, and both derive SLOT from the version. Bumping one
#   does not update it, it ERASES the slot orion-bin depends on. On 2026-08-12
#   (b165e5745) the applier deleted both lines; the symptom arrived 12 days
#   later as `there are no ebuilds to satisfy "dev-libs/icu-compat:77"`.
#   8dd837928 restored them and wrote the check down; the applier did it again
#   the same day. A removed line here is always a bug, never an intention.
#
# CLASS 2 -- a 40-hex literal clobbered with EGIT_COMMIT.
#   app-editors/zed pins seven vendored git dependencies by commit, each a
#   different upstream. The applier rewrites every 40-hex string in the ebuild,
#   not just the EGIT_COMMIT= line, so all seven end up holding the zed commit.
#   Those values are the left-hand side of the sed that turns `git = {…rev=X}`
#   into `path = {…}`; with the wrong SHA the sed matches nothing, exits 0, and
#   the `|| die` never fires. cargo then needs the network in a sandbox that has
#   none. Five occurrences in six bumps.
#
#   The check is not zed-specific and must not become so: an ebuild references
#   its own commit as ${EGIT_COMMIT} everywhere after the assignment, so the
#   literal appearing twice is the signature of the damage, whatever the package.
#
# Exit: 0 clean · 1 damage found · 2 usage or environment problem.

set -euo pipefail

# Derived from this script's own location, not the caller's cwd: the checks
# belong to THIS repository, and resolving them against wherever the caller
# happens to stand would silently check something else and pass.
REPO="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
STAGED="no"
SCOPE="changed"
FOUND=0

usage() {
	printf 'usage: %s [--staged] [--all]\n' "${0##*/}" >&2
	exit 2
}

for arg in "$@"; do
	case "${arg}" in
	--staged) STAGED="yes" ;;
	--all) SCOPE="all" ;;
	-h | --help) usage ;;
	*)
		printf 'unknown option: %s\n' "${arg}" >&2
		usage
		;;
	esac
done

_diff() {
	if [[ "${STAGED}" == "yes" ]]; then
		git -C "${REPO}" diff --cached "$@"
	else
		git -C "${REPO}" diff "$@"
	fi
}

# _blob <path> — the content about to be committed, which is the index when
# --staged and the working tree otherwise. Reading the wrong one would let a
# hook pass on a file whose staged revision still carries the damage.
_blob() {
	local path="$1"
	if [[ "${STAGED}" == "yes" ]]; then
		git -C "${REPO}" show ":${path}" 2>/dev/null || true
	else
		cat "${REPO}/${path}" 2>/dev/null || true
	fi
}

# --- class 1 ---------------------------------------------------------------

check_enabled_false() {
	local removed
	removed="$(_diff -- .autoupdate/packages.toml | grep -c '^-enabled = false' || true)"
	if ((removed == 0)); then
		printf 'ok    packages.toml: no pinned record was re-enabled\n'
		return 0
	fi
	printf 'FAIL  packages.toml: %s pinned record(s) lost the enabled = false pin\n' "${removed}"
	printf '        those records are pinned OFF on purpose; a bump erases the\n'
	printf '        SLOT another package depends on. Restore with:\n'
	printf '          git checkout -- .autoupdate/packages.toml\n'
	FOUND=1
}

# --- class 2 ---------------------------------------------------------------

# ACMR, not ACM: every applier bump lands as a RENAME (foo-1.2.ebuild ->
# foo-1.3.ebuild, similarity 96-100%), so a filter without R prints "ebuilds:
# none in scope" on exactly the commits this check exists for -- a silent pass,
# not a clean one. Observed on the 2026-08-24 bump: ten renamed ebuilds, none
# examined.
_ebuild_list() {
	if [[ "${SCOPE}" == "all" ]]; then
		git -C "${REPO}" ls-files '*.ebuild'
	else
		_diff --name-only --diff-filter=ACMR -- '*.ebuild'
	fi
}

check_commit_literals() {
	local -a ebuilds=()
	mapfile -t ebuilds < <(_ebuild_list)
	if ((${#ebuilds[@]} == 0)); then
		printf 'ok    ebuilds: none in scope\n'
		return 0
	fi

	local path content commit count bad=0
	for path in "${ebuilds[@]}"; do
		content="$(_blob "${path}")"
		[[ -n "${content}" ]] || continue
		commit="$(printf '%s' "${content}" | sed -n 's/^EGIT_COMMIT="\([0-9a-f]\{40\}\)".*/\1/p' | head -n 1)"
		[[ -n "${commit}" ]] || continue
		count="$(printf '%s' "${content}" | grep -c "${commit}" || true)"
		((count > 1)) || continue
		printf 'FAIL  %s: EGIT_COMMIT literal appears %s times, expected 1\n' "${path}" "${count}"
		printf '%s' "${content}" | grep -n "${commit}" | grep -v '^[0-9]*:EGIT_COMMIT=' |
			sed 's/^/        /' | head -n 12
		printf '        re-derive those from GIT_CRATES, not from EGIT_COMMIT\n'
		bad=1
	done

	if ((bad == 0)); then
		printf 'ok    ebuilds: %s checked, no clobbered commit literal\n' "${#ebuilds[@]}"
		return 0
	fi
	FOUND=1
}

# --- main ------------------------------------------------------------------

check_enabled_false
check_commit_literals

if ((FOUND == 0)); then
	exit 0
fi
printf '\nautoupdate damage found — see the lines marked FAIL\n'
exit 1
