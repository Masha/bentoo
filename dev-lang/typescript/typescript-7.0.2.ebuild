# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# TypeScript 7 is the native port of the compiler, written in Go and kept in
# the tsc/ directory of the TypeScript repository (formerly
# microsoft/typescript-go). This builds that compiler, cmd/tsgo, from source;
# dev-lang/typescript-bin installs Microsoft's prebuilt npm build of it. Both
# own /usr/bin/tsc, so they block each other.
#
# Only the compiler is installed: no Node launcher and no dist/ IPC API, which
# npm builds from TypeScript sources with a JavaScript toolchain. There is no
# tsserver.js and no JavaScript compiler API in 7.x at all; consumers that
# need either must depend on <dev-lang/typescript-7, which keeps the 6.x
# series from ::gentoo installable.
#
# Every divergence below follows from that rewrite; ::gentoo's counterpart is
# the 6.x JavaScript compiler, a different artifact rather than an older copy.
# BENTOO-DIVERGENCE: EAPI - 8, where ::gentoo's 6.0.3 is 9. Nothing here needs
# an EAPI 9 feature, and this ebuild was never derived from that one.
# BENTOO-DIVERGENCE: INHERIT - go-module; 6.x is plain JavaScript run by node.
# BENTOO-DIVERGENCE: DEFINED_PHASES - the go-module phases plus src_test; 6.x
# only overrides src_compile and src_install around npm.
# BENTOO-DIVERGENCE: SRC_URI - the repository tarball plus a `go mod vendor`
# tree hosted on distfiles.obentoo.org; 6.x installs the npm tarball.
# BENTOO-DIVERGENCE: S - the Go module lives in tsc/ of the repository.
# BENTOO-DIVERGENCE: LICENSE - the Go modules linked into the executable and
# the material in lib.*.d.ts, itemised at LICENSE below; 6.x is Apache-2.0 only.
# BENTOO-DIVERGENCE: KEYWORDS - ~amd64 only, the overlay's platform baseline.
# BENTOO-DIVERGENCE: RDEPEND - no nodejs: the compiler is a static Go
# executable. Blocks dev-lang/typescript-bin, which installs the same files.
# BENTOO-DIVERGENCE: BDEPEND - Go instead of npm.
# BENTOO-DIVERGENCE: metadata.xml - the longdescription states the 6.x/7.x API
# split and the source/binary split; maintainer is ours.

inherit go-module

MY_P="TypeScript-${PV}"

DESCRIPTION="Superset of JavaScript with optional static typing (native Go compiler)"
HOMEPAGE="
	https://www.typescriptlang.org/
	https://github.com/microsoft/TypeScript/
"
SRC_URI="https://github.com/microsoft/TypeScript/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
# Vendored dependency tree, generated with `go mod vendor` in tsc/ and hosted
# by the overlay; its top directory is ${MY_P}/tsc/vendor. scripts/go-vendor.sh
# expects go.mod at the top of the source tarball, so it cannot regenerate this
# one: on a bump, run `go mod vendor` in tsc/ and tar ${MY_P}/tsc/vendor by
# hand.
SRC_URI+=" https://distfiles.obentoo.org/${P}-vendor.tar.xz"
S="${WORKDIR}/${MY_P}/tsc"

# Apache-2.0: TypeScript itself and github.com/mackerelio/go-osstat.
# Bundled into the Go executable (see NOTICE.txt):
#   BSD: golang.org/x/{sync,sys,term,text}, github.com/go-json-experiment/json
#   BSD-2: github.com/zeebo/xxh3
#   MIT: github.com/klauspost/cpuid/v2
# Installed alongside it: MIT for the DefinitelyTyped and Khronos WebGL
# declarations; W3C, CC-BY-4.0 (WHATWG DOM) and Unicode-DFS-2016 for material
# in the lib.*.d.ts files.
LICENSE="Apache-2.0 BSD BSD-2 CC-BY-4.0 MIT Unicode-DFS-2016 W3C"
SLOT="0"
KEYWORDS="~amd64"

RDEPEND="!dev-lang/typescript-bin"
# tsc/go.mod: go 1.26.
BDEPEND=">=dev-lang/go-1.26"

src_compile() {
	# The flags of upstream's release build (Herebyfile.mjs, buildTsgo),
	# minus `-ldflags=-s -w`: stripping is Portage's job. `noembed` makes the
	# executable read the lib.*.d.ts files from its own directory -- after
	# resolving symlinks -- instead of compiling them in, which is how the npm
	# build ships and what Chromium relies on to substitute its patched copies.
	CGO_ENABLED=0 ego build -trimpath -tags noembed -o tsgo ./cmd/tsgo
}

src_test() {
	# The compiler's own unit tests; the conformance suites need the
	# TypeScript git submodule, which the release tarball does not carry.
	ego test -tags noembed ./internal/core/... ./internal/tspath/... \
		./internal/scanner/... ./internal/parser/...
}

src_install() {
	local dest=/usr/lib/${PN}

	exeinto "${dest}"
	newexe tsgo tsc
	insinto "${dest}"
	doins internal/bundled/libs/*.d.ts

	dosym -r "${dest}"/tsc /usr/bin/tsc
	# The name both TypeScript 7 packages share for the executable itself; see
	# dev-lang/typescript-bin.
	dosym -r "${dest}"/tsc /usr/bin/tsgo

	dodoc README.md NOTICE.txt
}
