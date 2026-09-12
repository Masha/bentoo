# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module

MY_PN="sh"

DESCRIPTION="A shell parser, formatter and interpreter (POSIX shell, bash, mksh)"
HOMEPAGE="https://github.com/mvdan/sh"
SRC_URI="https://github.com/mvdan/sh/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
# Vendored dependency tree, generated with `go mod vendor` and hosted by the
# overlay. It carries a checksum in the Manifest, so the build needs no network
# and stays inside the sandbox -- unlike an `ego mod download` at build time.
SRC_URI+=" https://distfiles.obentoo.org/${P}-vendor.tar.xz"
S="${WORKDIR}/${MY_PN}-${PV}"

LICENSE="BSD"
# Dependent (bundled, statically linked) Go module licenses
LICENSE+=" Apache-2.0 MIT"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

BDEPEND=">=dev-lang/go-1.26"

# shfmt reports its version through debug.ReadBuildInfo(), which for a build
# from a tarball says "(devel)". The patch bakes in the real version and only
# prefers the build info when it carries something meaningful. Without it the
# installed binary cannot answer `shfmt --version`.
PATCHES=(
	"${FILESDIR}"/${P}-report-real-version.patch
)

src_compile() {
	ego build -trimpath -o shfmt ./cmd/shfmt
}

src_test() {
	ego test ./cmd/... ./syntax/...
}

src_install() {
	dobin shfmt
	einstalldocs
}
