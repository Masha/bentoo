# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Built from source instead of installing the npm bundle, for one reason:
# upstream's bundle carries @core-js/pure 4.0.0-alpha.1, whose licence is
# non-commercial and experimental only (see files/${PN}-drop-core-js.patch).
# The patch swaps its four polyfills for the native Node.js methods, and the
# sources are compiled with the plain TypeScript compiler -- upstream's rspack
# build needs per-arch native binaries, tsc is pure JavaScript.
#
# Three distfiles:
#  - the source tag;
#  - the npm tarball, used ONLY for dist/typeshed-fallback: upstream's stub
#    tree with stdlib docstrings merged in ("docstubs"), which its release
#    pipeline generates with a separate Python toolchain. It is .pyi data,
#    no code, and contains no core-js;
#  - ${PN}-node_modules-${PVR}.tar.xz, hosted by the overlay: the runtime
#    dependencies plus the @types packages tsc needs, pinned to the versions
#    resolved in upstream's pnpm-lock.yaml. core-js is deliberately absent.
#    lodash and is-ci are listed although upstream marks them dev-only,
#    because the sources import them at runtime (the bundle inlines them).
#    Regenerate on every bump:
#      v() { yq -o=json ".importers[\"$1\"]" pnpm-lock.yaml | jq -r --arg n "$2" \
#            '((.dependencies // {}) + (.devDependencies // {}))[$n].version' \
#            | sed 's/(.*//'; }
#      # runtime: every "dependencies" entry of packages/pyright-internal
#      # except @core-js/pure, plus lodash and is-ci; build-only: @types/node,
#      # @types/{command-line-args,diff,fs-extra,tmp,lodash} (pyright-internal)
#      # and @types/is-ci (packages/pyright). Pin each one with v(), write
#      # them into a bare package.json, then:
#      npm install --ignore-scripts --no-audit --no-fund --before=<YYYY-MM-DD>
#      tar --sort=name --mtime='<YYYY-MM-DD> 00:00:00Z' --owner=0 --group=0 \
#          --numeric-owner --format=gnu -cf - node_modules \
#          | xz -T1 -9e > ${PN}-node_modules-${PVR}.tar.xz
#    Redo the LICENSE survey below from node_modules/.package-lock.json.
NODE_MODULES="${PN}-node_modules-${PVR}.tar.xz"

inherit edo

DESCRIPTION="Pyright fork with various type checking improvements and Pylance features"
HOMEPAGE="https://docs.basedpyright.com/ https://github.com/DetachHead/basedpyright"
SRC_URI="
	https://github.com/DetachHead/${PN}/archive/refs/tags/v${PV}.tar.gz -> ${P}.gh.tar.gz
	https://registry.npmjs.org/${PN}/-/${P}.tgz
	https://distfiles.obentoo.org/${NODE_MODULES}
"

# MIT: basedpyright/pyright and most of node_modules. Apache-2.0 (and MIT):
# typeshed. Vendored: BSD (@jupyterlab/nbformat, @lumino/*, diff, smol-toml,
# source-map), BSD-2 (@yarnpkg/fslib, @yarnpkg/libzip), ISC (anymatch,
# glob-parent, graceful-fs, pyright-to-gitlab-ci, ts-command-line-args),
# 0BSD (tslib); string-format is WTFPL OR MIT, covered by MIT.
LICENSE="MIT Apache-2.0 BSD BSD-2 ISC 0BSD"
SLOT="0"
# Pure JavaScript: no install scripts, no native addons, compiled by tsc.
KEYWORDS="~amd64 ~arm64"
# The upstream suite runs through jest and an rspack-built test server.
RESTRICT="test"

# >=22: Set.prototype.union replaces the core-js Set (see the patch).
RDEPEND=">=net-libs/nodejs-22:*"
# Upstream pins typescript ~6.0.3.
BDEPEND="=dev-lang/typescript-6.0*"

PATCHES=(
	"${FILESDIR}"/${PN}-drop-core-js.patch
)

src_unpack() {
	default
	# The npm tarball unpacks to "package"; only its stub tree is used.
	mv "${WORKDIR}"/package/dist/typeshed-fallback "${WORKDIR}"/typeshed-fallback || die
	rm -r "${WORKDIR}"/package || die
}

src_compile() {
	ln -s "${WORKDIR}"/node_modules node_modules || die

	edo tsc -p packages/pyright/tsconfig.json

	# tsc keeps the "pyright-internal/*" path alias verbatim, which Node
	# cannot resolve; the bundler did. Only the two entry modules use it.
	local f
	for f in langserver pyright; do
		f=packages/pyright/out/packages/pyright/src/${f}.js
		grep -qF 'require("pyright-internal/' "${f}" || die "no pyright-internal import in ${f}"
		sed -i 's|require("pyright-internal/|require("../../pyright-internal/src/|g' "${f}" || die
		grep -qF 'require("pyright-internal/' "${f}" && die "alias left in ${f}"
	done

	# pyright-to-gitlab-ci ships its converter as TypeScript only; tsc never
	# emits files under node_modules unless they are passed explicitly.
	# --ignoreConfig: TS 6 refuses explicit files while ${S}/tsconfig.json
	# sits in the working directory.
	local gl="${WORKDIR}"/node_modules/pyright-to-gitlab-ci/src
	edo tsc --ignoreConfig --module commonjs --target es2021 --esModuleInterop --skipLibCheck \
		--typeRoots "${WORKDIR}"/node_modules/@types --types node \
		--rootDir "${gl}" --outDir "${gl}" \
		"${gl}"/converter/{index,converter}.ts "${gl}"/types/{index,gitlab,pyright}.ts
}

src_install() {
	local dest=/usr/share/${PN}
	insinto "${dest}"

	# Same shape as the npm package: the entry scripts point __rootDirectory
	# at dist/, where the language server looks for typeshed-fallback.
	local f
	for f in index langserver.index; do
		sed -e "s|require('./dist/pyright-langserver')|require('./out/packages/pyright/src/langserver')|" \
			-e "s|require('./dist/pyright')|require('./out/packages/pyright/src/pyright')|" \
			packages/pyright/${f}.js > "${T}"/${f}.js || die
		grep -qF "require('./out/packages/pyright/src/" "${T}"/${f}.js || die "entry rewrite failed: ${f}.js"
		doins "${T}"/${f}.js
	done

	doins -r packages/pyright/out
	# printVersion() reads "../package.json" relative to pyright-internal/src.
	insinto "${dest}"/out/packages/pyright-internal
	doins packages/pyright-internal/package.json

	insinto "${dest}"/dist
	doins -r "${WORKDIR}"/typeshed-fallback

	# @types were only needed by tsc; npm's .bin shims point at nothing used.
	rm -r "${WORKDIR}"/node_modules/{@types,.bin} || die
	insinto "${dest}"
	doins -r "${WORKDIR}"/node_modules

	local bin
	for bin in ${PN}:index ${PN}-langserver:langserver.index; do
		cat > "${T}"/${bin%%:*} <<-EOF || die
			#!/bin/sh
			exec node ${dest}/${bin#*:}.js "\$@"
		EOF
		dobin "${T}"/${bin%%:*}
	done

	dodoc README.md
}
