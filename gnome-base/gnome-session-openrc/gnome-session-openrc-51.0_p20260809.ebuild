# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
# Snapshot of upstream master named for the GNOME series it serves: upstream has no v51 tag yet.
# BENTOO-DIVERGENCE: SRC_URI - pinned upstream master commit instead of the v50.0 tag
# BENTOO-DIVERGENCE: PATCHES - the DCONF_PROFILE leader patch ::gentoo carries is already in this commit
# BENTOO-DIVERGENCE: DEPEND - new pam_gnome_session_openrc module needs sys-libs/pam and librc
# BENTOO-DIVERGENCE: RDEPEND - follows DEPEND (sys-libs/pam, sys-apps/openrc)

EAPI=8

inherit meson

COMMIT="93ddc90d50ee33b6759bbc9a7bd5d7e52bba77c0"

DESCRIPTION="Gnome session leader for OpenRC"
HOMEPAGE="https://github.com/swagtoy/gnome-session-openrc"
SRC_URI="https://github.com/swagtoy/${PN}/archive/${COMMIT}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/${PN}-${COMMIT}"

LICENSE="GPL-2+"
SLOT="0"
KEYWORDS="~alpha ~amd64 ~arm ~arm64 ~loong ~ppc ~ppc64 ~riscv ~sparc ~x86"

COMMON_DEPEND="
	>=dev-libs/glib-2.82.0:2
	>=sys-auth/elogind-242
	sys-apps/openrc
	sys-libs/pam
"
RDEPEND="${COMMON_DEPEND}
	sys-apps/dbus
	!<gnome-base/gnome-session-50
"
DEPEND="${COMMON_DEPEND}"
BDEPEND="
	virtual/pkgconfig
"

src_configure() {
	local emesonargs=(
		-Dsecuredir="/$(get_libdir)/security"
	)
	meson_src_configure
}
