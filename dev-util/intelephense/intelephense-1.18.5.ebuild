# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="PHP language server (freemium; premium features need a licence key)"
HOMEPAGE="https://intelephense.com/ https://github.com/bmewburn/vscode-intelephense"
# npm is the only channel the server ships through; the GitHub repository
# holds the VS Code extension and docs. The tarball is a self-contained
# webpack bundle: every require() left in lib/intelephense.js is a Node
# built-in, so the package.json "dependencies" need no node_modules.
SRC_URI="https://registry.npmjs.org/${PN}/-/${P}.tgz"
S="${WORKDIR}/package"

# Proprietary EULA (licenses/intelephense): personal licence, no
# modification (5a), no reproduction or distribution (5c). Nothing is
# mirrored or shipped as a binary package, and the files are installed
# byte-for-byte as npm serves them.
LICENSE="intelephense"
SLOT="0"
# Pure JavaScript plus TypeScript .d.ts stubs; nothing arch-specific.
KEYWORDS="~amd64 ~arm64"
RESTRICT="bindist mirror"

RDEPEND="net-libs/nodejs:*"

src_install() {
	insinto /usr/share/${PN}
	doins -r lib package.json

	# package.json points bin at lib/intelephense.js, meant to be reached
	# through node_modules/.bin; the launcher uses an absolute path instead
	# and leaves the licensed files untouched.
	cat > "${T}"/${PN} <<-EOF || die
		#!/bin/sh
		exec node /usr/share/${PN}/lib/intelephense.js "\$@"
	EOF
	dobin "${T}"/${PN}

	dodoc README.md CHANGELOG.md
}

pkg_postinst() {
	elog "Editors start the server as 'intelephense --stdio'; run bare it only"
	elog "reports that no connection stream is set."
	elog "Premium features (rename, code actions, inlay hints, ...) need a"
	elog "licence key from https://intelephense.com/, passed by the editor as"
	elog "the 'licenceKey' initialization option."
}
