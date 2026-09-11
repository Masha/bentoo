# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Kimi CLI, Moonshot AI's terminal coding agent"
HOMEPAGE="https://github.com/MoonshotAI/kimi-cli"
KIMI_BASE="https://github.com/MoonshotAI/kimi-cli/releases/download/${PV}"
# Upstream also ships "-onedir" variants of the same builds; those unpack to a
# directory tree instead of a single binary and are not used here.
SRC_URI="
	amd64? (
		${KIMI_BASE}/kimi-${PV}-x86_64-unknown-linux-gnu.tar.gz
			-> ${P}-amd64.tar.gz
	)
	arm64? (
		${KIMI_BASE}/kimi-${PV}-aarch64-unknown-linux-gnu.tar.gz
			-> ${P}-arm64.tar.gz
	)
"
S="${WORKDIR}"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
RESTRICT="bindist mirror strip"

QA_PREBUILT="*"

src_install() {
	exeinto /opt/kimi-cli-bin
	doexe kimi

	dosym -r /opt/kimi-cli-bin/kimi /opt/bin/kimi
}
