# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Static type checker and language server for Python"
HOMEPAGE="https://microsoft.github.io/pyright/ https://github.com/microsoft/pyright"
# Upstream distributes the built checker through npm only (the PyPI "pyright"
# is a third-party wrapper that downloads this same tarball at runtime).
# dist/ is a webpack bundle with every runtime module inlined; the only
# declared dependency, fsevents, is an optional macOS-only binding.
SRC_URI="https://registry.npmjs.org/${PN}/-/${P}.tgz"
S="${WORKDIR}/package"

# MIT: pyright and most bundled modules; Apache-2.0 (and MIT): the typeshed
# stubs in dist/typeshed-fallback; ISC: anymatch, glob-parent; BSD: smol-toml,
# source-map; BSD-2: @yarnpkg/fslib, @yarnpkg/libzip; 0BSD: tslib.
LICENSE="MIT 0BSD Apache-2.0 BSD BSD-2 ISC"
SLOT="0"
# Pure JavaScript: nothing here is architecture-specific.
KEYWORDS="~amd64 ~arm64"

RDEPEND="net-libs/nodejs:*"

src_install() {
	insinto /usr/share/${PN}
	# index.js and langserver.index.js locate dist/ through __dirname.
	doins -r dist index.js langserver.index.js package.json

	# package.json points bin at the two entry scripts, which are meant to be
	# reached through node_modules/.bin; the launchers use absolute paths.
	local bin entry
	for bin in pyright:index.js pyright-langserver:langserver.index.js; do
		entry=${bin#*:}
		bin=${bin%%:*}
		cat > "${T}/${bin}" <<-EOF || die
			#!/bin/sh
			exec node /usr/share/${PN}/${entry} "\$@"
		EOF
		dobin "${T}/${bin}"
	done

	dodoc README.md
}
