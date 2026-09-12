# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module

DESCRIPTION="HTTP load testing tool driven by a constant request rate"
HOMEPAGE="https://github.com/tsenart/vegeta"
SRC_URI="https://github.com/tsenart/vegeta/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
# Vendored dependency tree, generated with `go mod vendor` and hosted by the
# overlay, so the build carries a checksum and needs no network.
SRC_URI+=" https://distfiles.obentoo.org/${P}-vendor.tar.xz"

LICENSE="MIT"
# Dependent (bundled, statically linked) Go module licenses
LICENSE+=" Apache-2.0 BSD BSD-2 MPL-2.0"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

BDEPEND=">=dev-lang/go-1.22"

src_compile() {
	local go_ldflags=(
		-X "main.Version=${PV}"
		-X "main.Commit=gentoo-${PV}"
	)
	ego build -trimpath -ldflags "${go_ldflags[*]}" -o vegeta .
}

src_test() {
	ego test ./...
}

src_install() {
	dobin vegeta
	einstalldocs
}
