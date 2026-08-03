# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Fast, disk space efficient package manager"
HOMEPAGE="https://pnpm.io"
SRC_URI="https://registry.npmjs.org/${PN}/-/${P}.tgz"
S="${WORKDIR}/package"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

# The floor comes from upstream, not from what happens to be installed here:
# pnpm 11.19.0's package.json declares engines.node ">=22.13".
#
# The :* slot operator is load-bearing.  Story 005 made net-libs/nodejs slotted
# by major (this overlay carries SLOT="24" and SLOT="26"; ::gentoo keeps the
# unslotted SLOT="0/<major>"), so a slotless atom matches more than one slot and
# pkgcheck rejects it as MissingSlotDep.  pnpm is a plain JavaScript bundle and
# runs on any node past the floor, so ":*" -- any slot, no rebuild when it
# changes -- is the honest constraint.  Pinning one major would be a lie.
#
# ACCEPTED QA FINDING: pkgcheck reports NonsolvableDepsInDev on the
# default/linux/amd64/23.0/x32 dev profile.  net-libs/nodejs is unavailable on
# amd64/x32 -- ::gentoo states exactly that and package.mask's each consumer
# individually there (dev-util/claude-code, net-misc/sunshine,
# app-containers/devcontainer, ...).  Every nodejs consumer in this overlay
# reports it (playwright, lemonade, claude-agent-acp-tui), so it is a property
# of the profile, not of this ebuild.  The systemic fix is one overlay-wide
# profiles/arch/amd64/x32/package.mask covering all of them.
DEPEND=">=net-libs/nodejs-22.13:*"
RDEPEND="${DEPEND}"

src_compile() {
	:
}

src_install(){
	local install_dir="/usr/$(get_libdir)/node_modules/${PN}" path shebang
	insinto "${install_dir}"
	doins -r .
	dosym "../$(get_libdir)/node_modules/${PN}/bin/pnpm.cjs" "/usr/bin/pnpm"
	dosym "../$(get_libdir)/node_modules/${PN}/bin/pnpx.cjs" "/usr/bin/pnpx"
	fperms +x "/usr/bin/pnpm" "/usr/bin/pnpx"
	fperms +x "${install_dir}/bin/pnpm.cjs" "${install_dir}/bin/pnpx.cjs"
	fperms +x "${install_dir}/dist/node-gyp-bin/node-gyp"
	fperms +x "${install_dir}/dist/node_modules/node-gyp/bin/node-gyp.js"
}
