# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module systemd

DESCRIPTION="A credential keyring for Claude Code: refresh tokens stay, access tokens go out"
HOMEPAGE="https://github.com/zeo-workspace/kyomei"
SRC_URI="https://github.com/zeo-workspace/kyomei/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64"
IUSE="test"
RESTRICT="!test? ( test )"

# Standard library only: go.mod has no requirements, so there is no EGO_SUM
# and nothing to vendor.
BDEPEND=">=dev-lang/go-1.26"
# `kyomei add` runs `claude auth login` in a scratch configuration directory.
RDEPEND="dev-util/claude-code"

DOCS=( README.md SECURITY.md )

src_compile() {
	# CGO_ENABLED=0 is what upstream ships (README "Build").
	CGO_ENABLED=0 ego build -trimpath \
		-ldflags "-X main.version=${PV}" \
		-o bin/ ./cmd/...
}

src_test() {
	# KYOMEI_CHECK_RUNNING makes gates_test.go skip itself: it runs the whole
	# pre-push gate (staticcheck, gitleaks, opengrep), which is the
	# maintainer's, not a package test.
	KYOMEI_CHECK_RUNNING=1 ego test ./...
}

src_install() {
	dobin bin/kyomei
	# kyomeid and kyomei-hook only print their version so far.
	systemd_douserunit contrib/systemd/kyomei-redeliver.{service,timer}
	einstalldocs
}

pkg_postinst() {
	elog "Add an account with: kyomei add --alias <name>"
	elog "Rewrite badges before they expire (per user):"
	elog "  systemctl --user enable --now kyomei-redeliver.timer"
	elog "Zeo picks the account in Settings > Agent Sandbox > Claude account."
}
