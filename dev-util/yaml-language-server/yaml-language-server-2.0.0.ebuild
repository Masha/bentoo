# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# The npm tarball carries only the compiled server. Its runtime dependencies
# are resolved by npm at install time, which the Portage sandbox forbids, so
# they ship as a second distfile generated offline from this exact release.
# Upstream publishes no npm-shrinkwrap.json; --before is what pins the
# transitive tree (>= 7 days in the past; 2.0.0 itself was published
# 2026-10-16, but the root package comes from the local tgz so --before does
# not touch it), and the resolved tree
# is recorded in node_modules/.package-lock.json inside the tarball:
#   tar xzf ${P}.tgz && cd package
#   npm pkg delete devDependencies scripts
#   npm install --omit=dev --ignore-scripts --no-audit --no-fund \
#       --before=2026-10-09
#   tar --sort=name --mtime='2026-10-09 00:00:00Z' --owner=0 --group=0 \
#       --numeric-owner --format=gnu -cf - node_modules \
#       | xz -T1 -9e > ${PN}-node_modules-${PVR}.tar.xz
# Every bump must regenerate and upload this tarball, and redo the LICENSE
# survey below from node_modules/.package-lock.json.
NODE_MODULES="${PN}-node_modules-${PVR}.tar.xz"

DESCRIPTION="Language server for YAML with JSON Schema support"
HOMEPAGE="https://github.com/redhat-developer/yaml-language-server"
SRC_URI="
	https://registry.npmjs.org/${PN}/-/${P}.tgz
	https://distfiles.obentoo.org/${NODE_MODULES}
"
S="${WORKDIR}/package"

# MIT: the server and most of node_modules. Vendored: ISC (yaml),
# BSD (fast-uri). prettier is a bundle whose THIRD-PARTY-NOTICES.md adds
# ISC, BSD, BSD-2, Apache-2.0 and BlueOak-1.0.0.
LICENSE="MIT Apache-2.0 BSD BSD-2 BlueOak-1.0.0 ISC"
SLOT="0"
# Pure JavaScript, no install scripts and no native addons in the vendored
# tree, so nothing here is arch-specific.
KEYWORDS="~amd64"

# engines.node in package.json; 2.0.0 is ESM and its launcher imports
# package.json with an import attribute.
RDEPEND=">=net-libs/nodejs-22.13.0:*"

src_install() {
	insinto /usr/share/${PN}
	# 2.0.0 ships ESM only: the server is out/src (it was out/server/src,
	# beside a test suite and lib/ builds, up to 1.x).
	doins -r bin l10n out package.json

	# npm's .bin shims are symlinks to helper CLIs nothing here runs.
	rm -r "${WORKDIR}"/node_modules/.bin || die
	insinto /usr/share/${PN}
	doins -r "${WORKDIR}"/node_modules

	# package.json points bin at bin/yaml-language-server, meant to be
	# reached through node_modules/.bin; the launcher uses an absolute path.
	cat > "${T}"/${PN} <<-EOF || die
		#!/bin/sh
		exec node /usr/share/${PN}/bin/${PN} "\$@"
	EOF
	dobin "${T}"/${PN}

	dodoc README.md CHANGELOG.md
}
