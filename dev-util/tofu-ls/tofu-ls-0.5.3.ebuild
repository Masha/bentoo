# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module optfeature

DESCRIPTION="OpenTofu Language Server"
HOMEPAGE="https://github.com/opentofu/tofu-ls"
SRC_URI="https://github.com/opentofu/tofu-ls/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
# Vendored dependency tree, generated with `go mod vendor` and hosted by the
# overlay (see scripts/go-vendor.sh). It carries a checksum in the Manifest, so
# the build needs no network and stays inside the sandbox.
SRC_URI+=" https://distfiles.obentoo.org/${P}-vendor.tar.xz"

LICENSE="MPL-2.0"
# Dependent (bundled, statically linked) Go module licenses, surveyed from the
# modules `go version -m` lists for the built binary.
LICENSE+=" Apache-2.0 BSD ISC MIT"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

BDEPEND=">=dev-lang/go-1.26.0"

# Upstream release builds embed provider schemas produced by
# `go generate ./internal/schemas`, which downloads tofu and every provider it
# lists. That cannot run in the sandbox, so this build embeds none: completion
# for provider blocks comes from the schemas of initialized modules
# (`tofu init`), read through the tofu CLI.

src_compile() {
	# The version is embedded from version/VERSION by go:embed.
	ego build -trimpath -o tofu-ls .
}

src_test() {
	ego test ./...
}

src_install() {
	dobin tofu-ls
	dodoc README.md CHANGELOG.md
}

pkg_postinst() {
	optfeature "provider schemas, validation and formatting of initialized modules" app-admin/opentofu
}
