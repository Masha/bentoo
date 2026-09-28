# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# TypeScript 7 is the native port of the compiler, written in Go. The
# "typescript" npm package is now only a thin JavaScript launcher (bin/tsc)
# plus the unstable IPC API under dist/; the compiler itself is a prebuilt,
# statically linked Go executable shipped in a per-platform package,
# @typescript/typescript-<os>-<arch>, that the launcher resolves through
# Node's module resolution.
#
# There is no tsserver.js and no lib/typescript.js any more, and the package's
# main export only reports the version. Consumers that drive tsserver or load
# the JavaScript compiler API (typescript-language-server, editor plugins,
# ts-node and friends) must depend on <dev-lang/typescript-7, which keeps the
# 6.x series from ::gentoo installable in the same slot.

DESCRIPTION="Superset of JavaScript with optional static typing (native Go compiler)"
HOMEPAGE="
	https://www.typescriptlang.org/
	https://github.com/microsoft/TypeScript/
	https://github.com/microsoft/typescript-go/
"

TS_PLATFORM_URI="https://registry.npmjs.org/@typescript/typescript"
# Gentoo arch -> npm platform package (linux-${process.arch}).
# Not packaged:
# - ppc64: npm's linux-ppc64 build is little-endian only (ELFv2, ppc64le),
#   while the ppc64 keyword also covers big-endian systems, where it would
#   install a compiler that cannot execute.
# - x86: upstream publishes no linux-ia32 package.
# - s390, mips: linux-s390x / linux-mips64el exist upstream but are untested;
#   mips would also need a guard, as mips64el is one ABI of several.
SRC_URI="
	https://registry.npmjs.org/${PN}/-/${P}.tgz
	amd64? (
		${TS_PLATFORM_URI}-linux-x64/-/typescript-linux-x64-${PV}.tgz
			-> ${P}-linux-x64.tgz
	)
	arm? (
		${TS_PLATFORM_URI}-linux-arm/-/typescript-linux-arm-${PV}.tgz
			-> ${P}-linux-arm.tgz
	)
	arm64? (
		${TS_PLATFORM_URI}-linux-arm64/-/typescript-linux-arm64-${PV}.tgz
			-> ${P}-linux-arm64.tgz
	)
	loong? (
		${TS_PLATFORM_URI}-linux-loong64/-/typescript-linux-loong64-${PV}.tgz
			-> ${P}-linux-loong64.tgz
	)
	riscv? (
		${TS_PLATFORM_URI}-linux-riscv64/-/typescript-linux-riscv64-${PV}.tgz
			-> ${P}-linux-riscv64.tgz
	)
"
S="${WORKDIR}/package"

# Apache-2.0: TypeScript itself and github.com/mackerelio/go-osstat.
# Bundled into the Go executable (see NOTICE.txt):
#   BSD: golang.org/x/{sync,sys,term,text}, github.com/go-json-experiment/json
#   BSD-2: github.com/zeebo/xxh3
#   MIT: github.com/klauspost/cpuid/v2
# Shipped alongside it: MIT for the vendored vscode-jsonrpc, DefinitelyTyped
# and Khronos WebGL declarations; W3C, CC-BY-4.0 (WHATWG DOM) and
# Unicode-DFS-2016 for material in the lib.*.d.ts files.
LICENSE="Apache-2.0 BSD BSD-2 CC-BY-4.0 MIT Unicode-DFS-2016 W3C"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm ~arm64 ~loong ~riscv"
# lib/tsc is already stripped by upstream, and lib/tsc.sig is a detached
# signature over the exact bytes of that file; stripping again can only
# break the match.
RESTRICT="strip"

# engines.node in package.json.
RDEPEND=">=net-libs/nodejs-16.20.0:*"

QA_PREBUILT="usr/lib/node_modules/typescript/node_modules/@typescript/typescript-linux-*/lib/tsc"

# Print the npm platform name for the arch being built (linux-<node arch>).
ts_platform() {
	if use amd64; then
		echo linux-x64
	elif use arm; then
		echo linux-arm
	elif use arm64; then
		echo linux-arm64
	elif use loong; then
		echo linux-loong64
	elif use riscv; then
		echo linux-riscv64
	else
		die "no TypeScript native compiler package for ARCH=${ARCH}"
	fi
}

src_unpack() {
	# Both tarballs extract to package/, so the platform one gets its own
	# directory.
	unpack "${P}.tgz"

	mkdir "${WORKDIR}/platform" || die
	pushd "${WORKDIR}/platform" >/dev/null || die
	unpack "${P}-$(ts_platform).tgz"
	popd >/dev/null || die
}

src_compile() {
	# Prebuilt; nothing to compile.
	:
}

src_install() {
	# Same location as the 6.x series, which is installed with
	# npm --global --prefix=/usr: always lib/, never lib64/.
	local dest=/usr/lib/node_modules/${PN}
	local platform=$(ts_platform)
	local platdir=${dest}/node_modules/@typescript/typescript-${platform}

	insinto "${dest}"
	doins -r bin lib dist vendor package.json
	fperms 0755 "${dest}"/bin/tsc

	# getExePath.js resolves @typescript/typescript-<platform>/package.json
	# from lib/, so a node_modules/ nested inside the package is found first.
	# The Go executable reads the lib.*.d.ts files that sit next to it.
	insinto "${platdir}"
	doins -r "${WORKDIR}"/platform/package/{lib,package.json}
	fperms 0755 "${platdir}"/lib/tsc

	dosym -r "${dest}"/bin/tsc /usr/bin/tsc

	dodoc README.md NOTICE.txt
}
