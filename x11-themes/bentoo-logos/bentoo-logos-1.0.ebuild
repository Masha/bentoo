# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit xdg

DESCRIPTION="Logo of the bentoo distribution, installed as the os-release LOGO icon"
HOMEPAGE="https://github.com/obentoo/bentoo"
# No upstream tarball: the logo is a single 8 KiB SVG kept in FILESDIR, so a
# change to it is a reviewable diff.
S="${WORKDIR}"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"

src_install() {
	# The icon name is the LOGO= value the bentoo profiles append to
	# /usr/lib/os-release (profiles/features/branding).
	insinto /usr/share/icons/hicolor/scalable/apps
	newins "${FILESDIR}"/bentoo.svg bentoo.svg
}
