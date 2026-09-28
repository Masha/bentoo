# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

MY_PN="${PN}-nodejs"
MY_P="${MY_PN}-${PV}"

# The npm tarball carries only the compiled server. Its runtime dependencies
# are resolved by npm at install time, which the Portage sandbox forbids, so
# they ship as a second distfile generated offline from this exact release.
# Upstream publishes no npm-shrinkwrap.json; --before is what pins the
# transitive tree (normally >= 7 days in the past; 2026-09-28 was a deliberate
# same-day refresh, requested by the maintainer), and the resolved tree
# is recorded in node_modules/.package-lock.json inside the tarball:
#   tar xzf ${MY_P}.tgz && cd package
#   npm pkg delete devDependencies scripts
#   npm install --omit=dev --ignore-scripts --no-audit --no-fund \
#       --before=2026-09-28
#   tar --sort=name --mtime='2026-09-28 00:00:00Z' --owner=0 --group=0 \
#       --numeric-owner --format=gnu -cf - node_modules \
#       | xz -T1 -9e > ${PN}-node_modules-${PVR}.tar.xz
# Every bump must regenerate and upload this tarball, and redo the LICENSE
# survey from node_modules/.package-lock.json.
NODE_MODULES="${PN}-node_modules-${PVR}.tar.xz"

DESCRIPTION="Language server for Dockerfiles (docker-langserver)"
HOMEPAGE="https://github.com/rcjsuen/dockerfile-language-server-nodejs"
SRC_URI="
	https://registry.npmjs.org/${MY_PN}/-/${MY_P}.tgz
	https://distfiles.obentoo.org/${NODE_MODULES}
"
S="${WORKDIR}/package"

# The server and every vendored module are MIT.
LICENSE="MIT"
SLOT="0"
# Pure JavaScript, no install scripts and no native addons in the vendored
# tree, so nothing here is arch-specific.
KEYWORDS="~amd64 ~arm64"

RDEPEND="net-libs/nodejs:*"

src_install() {
	insinto /usr/share/${PN}
	doins -r bin lib package.json

	# npm's .bin shims are symlinks to helper CLIs nothing here runs.
	rm -r "${WORKDIR}"/node_modules/.bin || die
	doins -r "${WORKDIR}"/node_modules

	# package.json points bin at bin/docker-langserver, meant to be reached
	# through node_modules/.bin; the launcher uses an absolute path instead.
	cat > "${T}"/docker-langserver <<-EOF || die
		#!/bin/sh
		exec node /usr/share/${PN}/bin/docker-langserver "\$@"
	EOF
	dobin "${T}"/docker-langserver

	dodoc README.md CHANGELOG.md
}
