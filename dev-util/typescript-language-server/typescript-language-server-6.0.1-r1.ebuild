# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Language Server Protocol implementation for TypeScript using tsserver"
HOMEPAGE="https://github.com/typescript-language-server/typescript-language-server"
# Upstream distributes through npm only. lib/cli.mjs is a rollup bundle that
# already inlines every runtime module, so no node_modules tree is needed.
SRC_URI="https://registry.npmjs.org/${PN}/-/${P}.tgz"
S="${WORKDIR}/package"

# Apache-2.0: the server; MIT: code taken from vscode and the bundled
# commander, fs-extra, vscode-languageserver* and friends; ISC: semver, which,
# graceful-fs; BlueOak-1.0.0: isexe.
LICENSE="Apache-2.0 BlueOak-1.0.0 ISC MIT"
SLOT="0"
# Pure JavaScript: nothing here is architecture-specific.
KEYWORDS="~amd64 ~arm64"

# tsserver is not bundled. The server prefers the typescript of the project
# being edited and a tsserver.path from the client, and otherwise falls back to
# require.resolve('typescript'). dev-lang/typescript backs that fallback, so
# the server also works on plain JavaScript projects with no typescript of
# their own. TypeScript 7 is the native (Go) port and ships neither tsserver.js
# nor lib/typescript.js, so the fallback needs the last JavaScript series.
RDEPEND="
	<dev-lang/typescript-7
	>=net-libs/nodejs-22.22.2:*
"

src_install() {
	insinto /usr/share/${PN}
	doins -r lib package.json

	# require.resolve walks up from lib/cli.mjs, so a node_modules entry next
	# to it is what makes the system typescript the "bundled" fallback.
	# dev-lang/typescript is installed with npm --global --prefix=/usr, which
	# always uses lib/, never lib64/.
	dosym -r /usr/lib/node_modules/typescript \
		/usr/share/${PN}/node_modules/typescript

	# package.json points bin at lib/cli.mjs, which is meant to be reached
	# through node_modules/.bin; the launcher uses an absolute path instead.
	cat > "${T}"/${PN} <<-EOF || die
		#!/bin/sh
		exec node /usr/share/${PN}/lib/cli.mjs "\$@"
	EOF
	dobin "${T}"/${PN}

	dodoc README.md
}
