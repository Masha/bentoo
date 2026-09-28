# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit optfeature

# The npm tarball carries only the compiled server. Its runtime dependencies
# are resolved by npm at install time, which the Portage sandbox forbids, so
# they ship as a second distfile generated offline from this exact release.
# Upstream publishes no npm-shrinkwrap.json; --before is what pins the
# transitive tree (keep it at least 7 days in the past), and the resolved tree
# is recorded in node_modules/.package-lock.json inside the tarball:
#   tar xzf ${P}.tgz && cd package
#   npm pkg delete devDependencies scripts
#   npm install --omit=dev --ignore-scripts --no-audit --no-fund \
#       --before=2026-09-20
#   tar --sort=name --mtime='2026-09-20 00:00:00Z' --owner=0 --group=0 \
#       --numeric-owner --format=gnu -cf - node_modules \
#       | xz -T1 -9e > ${PN}-node_modules-${PV}.tar.xz
# Every bump must regenerate and upload this tarball, and redo the LICENSE
# survey below from node_modules/.package-lock.json.
NODE_MODULES="${PN}-node_modules-${PV}.tar.xz"

DESCRIPTION="Language server for Bash"
HOMEPAGE="https://github.com/bash-lsp/bash-language-server"
SRC_URI="
	https://registry.npmjs.org/${PN}/-/${P}.tgz
	https://distfiles.obentoo.org/${NODE_MODULES}
"
S="${WORKDIR}/package"

# MIT: the server, tree-sitter-bash.wasm and most of node_modules.
# Vendored: ISC (fastq, fuzzy-search, glob-parent, semver),
# BSD-2 (@mixmark-io/domino), BlueOak-1.0.0 (minimatch).
LICENSE="MIT BSD-2 BlueOak-1.0.0 ISC"
SLOT="0"
# Pure JavaScript plus WebAssembly (tree-sitter), no install scripts and no
# native addons in the vendored tree, so nothing here is arch-specific.
KEYWORDS="~amd64 ~arm64"

RDEPEND=">=net-libs/nodejs-20:*"

src_install() {
	insinto /usr/share/${PN}
	doins -r out package.json tree-sitter-bash.wasm

	# npm's .bin shims are symlinks to helper CLIs nothing here runs.
	rm -r "${WORKDIR}"/node_modules/.bin || die
	doins -r "${WORKDIR}"/node_modules

	# server.js spawns this script directly for option completion, so it
	# must keep the exec bit that doins drops.
	fperms +x /usr/share/${PN}/out/get-options.sh

	# package.json points bin at out/cli.js, meant to be reached through
	# node_modules/.bin; the launcher uses an absolute path instead.
	cat > "${T}"/${PN} <<-EOF || die
		#!/bin/sh
		exec node /usr/share/${PN}/out/cli.js "\$@"
	EOF
	dobin "${T}"/${PN}

	dodoc README.md CHANGELOG.md
}

pkg_postinst() {
	optfeature "diagnostics (linting)" dev-util/shellcheck dev-util/shellcheck-bin
	optfeature "document formatting" dev-util/shfmt
	optfeature "completion of command options" app-shells/bash-completion
	optfeature "man page documentation on hover" virtual/man
}
