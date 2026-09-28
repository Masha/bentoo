# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit optfeature

# Upstream publishes the compiled server on npm under another name.
MY_PN="${PN}-server"
MY_P="${MY_PN}-${PV}"

# The npm tarball carries only the compiled server. Its runtime dependencies
# are resolved by npm at install time, which the Portage sandbox forbids, so
# they ship as a second distfile generated offline from this exact release.
# Upstream publishes no npm-shrinkwrap.json; --before is what pins the
# transitive tree (keep it at least 7 days in the past), and the resolved tree
# is recorded in node_modules/.package-lock.json inside the tarball:
#   tar xzf ${MY_P}.tgz && cd package
#   npm pkg delete devDependencies scripts
#   npm install --omit=dev --ignore-scripts --no-audit --no-fund \
#       --before=2026-09-20
#   tar --sort=name --mtime='2026-09-20 00:00:00Z' --owner=0 --group=0 \
#       --numeric-owner --format=gnu -cf - node_modules \
#       | xz -T1 -9e > ${PN}-node_modules-${PV}.tar.xz
# Every bump must regenerate and upload this tarball, and redo the LICENSE
# survey below from node_modules/.package-lock.json.
NODE_MODULES="${PN}-node_modules-${PV}.tar.xz"

DESCRIPTION="Perl language server"
HOMEPAGE="https://github.com/bscan/PerlNavigator"
SRC_URI="
	https://registry.npmjs.org/${MY_PN}/-/${MY_P}.tgz
	https://distfiles.obentoo.org/${NODE_MODULES}
"
S="${WORKDIR}/package"

# MIT: the server and most of node_modules. ISC: lru-cache, yallist.
# Perl's own terms: the Class::Inspector and Devel::Symdump copies vendored
# under src/perl/lib_bs22.
LICENSE="MIT ISC || ( Artistic GPL-1+ )"
SLOT="0"
# Pure JavaScript plus WebAssembly (vscode-oniguruma) and Perl scripts, no
# install scripts and no native addons, so nothing here is arch-specific.
# The upstream GitHub assets are pkg-built x86_64 binaries and are not used.
KEYWORDS="~amd64 ~arm64"

RDEPEND="
	dev-lang/perl
	>=net-libs/nodejs-16:*
"

src_install() {
	insinto /usr/share/${PN}
	# out/server.js loads perl.tmLanguage.json and node_modules from its
	# parent directory and runs the helpers from src/perl there as well.
	doins -r out package.json perl.tmLanguage.json
	insinto /usr/share/${PN}/src
	doins -r src/perl

	# npm's .bin shims are symlinks to helper CLIs nothing here runs.
	rm -r "${WORKDIR}"/node_modules/.bin || die
	insinto /usr/share/${PN}
	doins -r "${WORKDIR}"/node_modules

	# bin/perlnavigator requires ../out/server.js relative to itself; the
	# launcher uses an absolute path instead.
	cat > "${T}"/${PN} <<-EOF || die
		#!/bin/sh
		exec node /usr/share/${PN}/out/server.js "\$@"
	EOF
	dobin "${T}"/${PN}

	dodoc README.md
}

pkg_postinst() {
	optfeature "Perl::Critic diagnostics" dev-perl/Perl-Critic
	optfeature "Perl::Tidy formatting" dev-perl/Perl-Tidy
}
