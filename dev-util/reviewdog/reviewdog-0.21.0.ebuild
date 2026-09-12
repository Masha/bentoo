# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module

DESCRIPTION="Posts the output of any linter as review comments, filtered to the diff"
HOMEPAGE="https://github.com/reviewdog/reviewdog"
SRC_URI="https://github.com/reviewdog/reviewdog/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
# Vendored dependency tree, generated with `go mod vendor` and hosted by the
# overlay, so the build carries a checksum and needs no network.
SRC_URI+=" https://distfiles.obentoo.org/${P}-vendor.tar.xz"

LICENSE="MIT"
# Dependent (bundled, statically linked) Go module licenses
LICENSE+=" Apache-2.0 BSD BSD-2 ISC MPL-2.0"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

BDEPEND=">=dev-lang/go-1.25"

# The suite talks to the GitHub and GitLab APIs.
RESTRICT="test"

src_compile() {
	local go_ldflags=(
		-X "github.com/reviewdog/reviewdog/commands.Version=${PV}"
	)
	ego build -trimpath -ldflags "${go_ldflags[*]}" -o reviewdog ./cmd/reviewdog
}

src_install() {
	dobin reviewdog
	einstalldocs
}
