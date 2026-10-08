# Copyright 2025-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module

# bentoo: ::gentoo stops at 0.27.3, and chromium 155's devtools-frontend pins
# 0.28.2 (node_modules/esbuild/lib/main.js refuses any other binary). esbuild's
# go.mod has carried exactly one requirement, golang.org/x/sys at
# v0.0.0-20220715151400-c0bba94af5f8, for years and upstream promises never to
# move it (Go 1.13 support), so the vendor tarball ::gentoo already hosts for
# 0.27.3 is the same content this version needs. Reuse it instead of hosting a
# byte-identical copy; if go.mod ever gains a second line, this stops building.
VENDOR_PV="0.27.3"

DESCRIPTION="A modern, extremely fast, JavaScript and CSS bundler and minifier"
HOMEPAGE="https://esbuild.github.io/"
SRC_URI="
	https://github.com/evanw/esbuild/archive/v${PV}.tar.gz -> ${P}.tar.gz
	https://deps.gentoo.zip/dev-util/esbuild/esbuild-${VENDOR_PV}-vendor.tar.xz
"

LICENSE="BSD MIT"
SLOT="${PV}"
KEYWORDS="~amd64 ~arm64"

RESTRICT="test" # tests require more work, but chromium needs esbuild already.

# BENTOO-DIVERGENCE: DEFINED_PHASES - prepare, which moves the reused
# ${VENDOR_PV} vendor tree (see VENDOR_PV above) under ${S}; ::gentoo's own
# vendor tarball for each version unpacks there directly and needs none.
src_prepare() {
	default
	mv "${WORKDIR}/esbuild-${VENDOR_PV}/vendor" "${S}/vendor" ||
		die "Failed to move the ${VENDOR_PV} vendor tree into place"
}

src_compile() {
	# Build using vendored dependencies instead of Makefile
	ego build -mod=vendor -v -ldflags="-s -w" ./cmd/esbuild
}

src_install() {
	newbin esbuild esbuild-${PV}
}

src_test() {
	ego test -mod=vendor -v -ldflags="-s -w" ./cmd/esbuild
}
