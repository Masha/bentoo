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
# This is Microsoft's npm build, installed as published. dev-lang/typescript
# is the same compiler built from source; both own /usr/bin/tsc, so they
# block each other. Pick this one for the npm launcher and the dist/ IPC API,
# which the source package does not install.
#
# There is no tsserver.js and no lib/typescript.js any more, and the package's
# main export only reports the version. Consumers that drive tsserver or load
# the JavaScript compiler API (typescript-language-server, editor plugins,
# ts-node and friends) must depend on <dev-lang/typescript-7, which keeps the
# 6.x series from ::gentoo installable.

MY_PN="${PN%-bin}"
MY_P="${MY_PN}-${PV}"

DESCRIPTION="Superset of JavaScript with optional static typing (native Go compiler, binary)"
HOMEPAGE="
	https://www.typescriptlang.org/
	https://github.com/microsoft/TypeScript/
"
# The distfile names are the ones dev-lang/typescript used while it carried
# this npm build, so DISTDIR caches stay valid.
SRC_URI="
	https://registry.npmjs.org/${MY_PN}/-/${MY_P}.tgz
	https://registry.npmjs.org/@typescript/typescript-linux-x64/-/typescript-linux-x64-${PV}.tgz
		-> ${MY_P}-linux-x64.tgz
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
KEYWORDS="-* ~amd64"
# lib/tsc is already stripped by upstream, and lib/tsc.sig is a detached
# signature over the exact bytes of that file; stripping again can only
# break the match.
RESTRICT="strip"

# engines.node in package.json.
RDEPEND="
	>=net-libs/nodejs-16.20.0:*
	!dev-lang/typescript
"

QA_PREBUILT="usr/lib/node_modules/typescript/node_modules/@typescript/typescript-linux-x64/lib/tsc"

src_unpack() {
	# Both tarballs extract to package/, so the platform one gets its own
	# directory.
	unpack "${MY_P}.tgz"

	mkdir "${WORKDIR}/platform" || die
	pushd "${WORKDIR}/platform" >/dev/null || die
	unpack "${MY_P}-linux-x64.tgz"
	popd >/dev/null || die
}

src_compile() {
	# Prebuilt; nothing to compile.
	:
}

src_install() {
	# Same location as the 6.x series, which is installed with
	# npm --global --prefix=/usr: always lib/, never lib64/.
	local dest=/usr/lib/node_modules/${MY_PN}
	local platdir=${dest}/node_modules/@typescript/typescript-linux-x64

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
	# The executable itself, under the name both TypeScript 7 packages share:
	# consumers that need the binary rather than the Node launcher (Chromium
	# copies it into its tree) resolve /usr/bin/tsgo with realpath.
	dosym -r "${platdir}"/lib/tsc /usr/bin/tsgo

	dodoc README.md NOTICE.txt
}
