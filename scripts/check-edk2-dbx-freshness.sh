#!/usr/bin/env bash
# Assert that sys-firmware/edk2's bundled Secure Boot revocation list (DBX) is
# the newest one Microsoft has published.
#
# edk2 carries TWO independent release trains and the ebuild pins both. PV
# follows tianocore's "edk2-stableYYYYMM" tag; SBO_VER follows
# microsoft/secureboot_objects, which ships the signed DBXUpdate.bin that
# secureboot_auto_sign enrolls. Nothing couples them -- a version bump moves PV
# and leaves SBO_VER wherever it was.
#
# .autoupdate/packages.toml cannot catch this. Its aux_var/aux_pattern pair is
# documented in bentoolkit's config.go as "applied to the SAME response body
# used for version detection", and the DBX lives in a different repository
# entirely; there is no aux_url, and base_url resolves a snapshot's base
# version, not a second pin. So the registry probes PV, reports "up to date",
# and says nothing about a revocation list that is months stale.
#
# That is the failure this script exists for, and it is worse than an ordinary
# stale pin: DBX is what REVOKES known-compromised bootloaders. Falling behind
# does not break a build or trip pkgcheck -- it silently ships a machine that
# still trusts binaries Microsoft has already revoked. Measured on 2026-09-01:
# the overlay sat on 1.6.4 while v1.6.5 had been out since 2026-07-07, and the
# amd64 blob had grown 24053 -> 24629 bytes, i.e. real new revocations.
#
# Deliberately NOT wired into .git/hooks/pre-commit: it needs the network, and a
# guard that turns red on a plane is a guard people learn to skip. Run it in
# upstream sweeps, and after any edk2 version bump.
#
# Usage: bash scripts/check-edk2-dbx-freshness.sh [--self-test]
# Exit:  0 pin is current; 1 pin is behind, naming both versions;
#        2 could not determine (network/API), which is NOT a gap.

set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
api='https://api.github.com/repos/microsoft/secureboot_objects/releases/latest'

# Extract SBO_VER from an ebuild. Kept as a function so --self-test can exercise
# it against fixtures without touching the tree or the network.
extract_sbo_ver() {
	local file=$1 ver
	ver=$(sed -nE 's/^SBO_VER="([^"]+)".*/\1/p' "${file}" | head -n1)
	[[ -n ${ver} ]] || return 1
	printf '%s\n' "${ver}"
}

# Compare "1.6.4" against "1.6.5" numerically, component by component. sort -V
# would do it, but it also happily orders strings that are not versions at all,
# which is how a silently-empty capture becomes a passing comparison.
version_lt() {
	[[ $1 != "$2" ]] && [[ $(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1) == "$1" ]]
}

if [[ ${1:-} == --self-test ]]; then
	tmp=$(mktemp -d)
	trap 'rm -rf -- "${tmp}"' EXIT

	printf 'SBO_VER="1.6.5" # comment\n' >"${tmp}/a.ebuild"
	[[ $(extract_sbo_ver "${tmp}/a.ebuild") == 1.6.5 ]] ||
		{ echo "self-test: extraction failed on a well-formed ebuild" >&2; exit 1; }

	printf 'NOTHING=1\n' >"${tmp}/b.ebuild"
	if extract_sbo_ver "${tmp}/b.ebuild" >/dev/null 2>&1; then
		echo "self-test: extraction should fail when SBO_VER is absent" >&2; exit 1
	fi

	version_lt 1.6.4 1.6.5 || { echo "self-test: 1.6.4 < 1.6.5 not detected" >&2; exit 1; }
	version_lt 1.6.10 1.6.9 && { echo "self-test: 1.6.10 wrongly ordered below 1.6.9" >&2; exit 1; }
	version_lt 1.6.5 1.6.5 && { echo "self-test: equal versions must not compare lt" >&2; exit 1; }

	echo "self-test: OK"
	exit 0
fi

shopt -s nullglob
ebuilds=( "${repo}"/sys-firmware/edk2/edk2-*.ebuild )
shopt -u nullglob
(( ${#ebuilds[@]} )) || { echo "no ebuild found under ${repo}/sys-firmware/edk2" >&2; exit 1; }

latest=$(curl -sL --max-time 30 -H 'User-Agent: bentoo-autoupdate' "${api}" |
	sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v?([0-9][0-9.]*)".*/\1/p' | head -n1) || true

if [[ -z ${latest} ]]; then
	echo "could not read the latest secureboot_objects release from ${api}" >&2
	echo "treating as INDETERMINATE, not as a gap" >&2
	exit 2
fi

rc=0
for ebuild in "${ebuilds[@]}"; do
	name=$(basename "${ebuild}")
	if ! pinned=$(extract_sbo_ver "${ebuild}"); then
		echo "${name}: no SBO_VER found -- the ebuild changed shape, this check is blind" >&2
		rc=1
		continue
	fi
	if version_lt "${pinned}" "${latest}"; then
		echo "${name}: DBX pin is behind -- SBO_VER=${pinned}, upstream v${latest}" >&2
		echo "  bump SBO_VER, revbump the ebuild, and regenerate the Manifest:" >&2
		echo "  the blobs are fetched per version, so the DIST entries change too." >&2
		rc=1
	else
		echo "${name}: SBO_VER=${pinned} is current (upstream v${latest})"
	fi
done
exit "${rc}"
