# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module

DESCRIPTION="Finds and verifies leaked credentials across git history and many sources"
HOMEPAGE="https://github.com/trufflesecurity/trufflehog"
SRC_URI="https://github.com/trufflesecurity/trufflehog/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
# Vendored dependency tree, generated with `go mod vendor` and hosted by the
# overlay, so the build carries a checksum and needs no network.
SRC_URI+=" https://distfiles.obentoo.org/${P}-vendor.tar.xz"

LICENSE="AGPL-3"
# Dependent (bundled, statically linked) Go module licenses
LICENSE+=" Apache-2.0 BSD BSD-2 CC0-1.0 ISC LGPL-3 MIT MPL-2.0 public-domain"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

BDEPEND=">=dev-lang/go-1.25"

# The suite reaches live credential-verification endpoints.
RESTRICT="test"

src_compile() {
	local version_pkg="github.com/trufflesecurity/trufflehog/v3/pkg/version"
	local go_ldflags=(
		-X "${version_pkg}.BuildVersion=${PV}"
	)
	ego build -trimpath -ldflags "${go_ldflags[*]}" -o trufflehog .
}

src_install() {
	dobin trufflehog
	einstalldocs
}
