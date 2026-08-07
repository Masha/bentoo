# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module

DESCRIPTION="Advanced Go linter (staticcheck) and structlayout tools"
HOMEPAGE="https://staticcheck.dev/ https://github.com/dominikh/go-tools"
SRC_URI="https://github.com/dominikh/go-tools/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
# The upstream project is go-tools; ${PN} is the name of its flagship command.
S="${WORKDIR}/go-tools-${PV}"

LICENSE="MIT"
# Dependent (bundled, statically linked) Go module licenses, per
# LICENSE-THIRD-PARTY: golang.org/x/*, gogrep and gosmith are all BSD.
LICENSE+=" BSD"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

# Go modules are downloaded in src_unpack (upstream publishes no vendor tarball
# and bentoo hosts no deps tarball for it), so the network sandbox must be
# disabled.
RESTRICT="network-sandbox"

BDEPEND=">=dev-lang/go-1.25"

# Every command shipped by cmd/. Note that the repository root also contains
# directories literally named "staticcheck" and "structlayout", so the binaries
# must be built outside ${S} -- "go build -o staticcheck" would otherwise drop
# the binary *inside* that directory.
GO_BINS=(
	staticcheck
	structlayout
	structlayout-optimize
	structlayout-pretty
)

src_unpack() {
	default
	cd "${S}" || die
	ego mod download
}

src_compile() {
	# The version string is a compile-time constant in lintcmd/version
	# (Version="2026.1", MachineVersion="v${PV}"), so no -ldflags -X version
	# injection is required.
	mkdir -p "${T}/bin" || die

	local cmd
	for cmd in "${GO_BINS[@]}"; do
		ego build -o "${T}/bin/${cmd}" "./cmd/${cmd}"
	done
}

src_test() {
	ego test ./...
}

src_install() {
	local cmd
	for cmd in "${GO_BINS[@]}"; do
		dobin "${T}/bin/${cmd}"
	done

	einstalldocs
	dodoc LICENSE-THIRD-PARTY
}
