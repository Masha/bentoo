# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module optfeature

DESCRIPTION="Static checker for GitHub Actions workflow files"
HOMEPAGE="https://rhysd.github.io/actionlint/ https://github.com/rhysd/actionlint"
SRC_URI="https://github.com/rhysd/actionlint/archive/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="MIT"
# Dependent (bundled, statically linked) Go module licenses
LICENSE+=" Apache-2.0 BSD MIT"
SLOT="0"
KEYWORDS="~amd64"

# Go modules are downloaded in src_unpack (upstream publishes no vendor
# tarball), so the network sandbox must be disabled.
RESTRICT="network-sandbox"

BDEPEND=">=dev-lang/go-1.25"

src_unpack() {
	default
	cd "${S}" || die
	ego mod download
}

src_compile() {
	local pkg=github.com/rhysd/actionlint
	ego build -trimpath \
		-ldflags "-X ${pkg}.version=${PV} -X '${pkg}.installedFrom=Gentoo package'" \
		-o actionlint ./cmd/actionlint
}

src_test() {
	ego test ./...
}

src_install() {
	dobin actionlint
	dodoc README.md CHANGELOG.md docs/*.md
}

pkg_postinst() {
	optfeature "linting shell scripts in run: steps" dev-util/shellcheck dev-util/shellcheck-bin
	optfeature "linting Python scripts in run: steps" dev-python/pyflakes
}
