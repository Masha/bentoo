# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit xdg desktop

DESCRIPTION="Commercial verison of FileZilla"
HOMEPAGE="https://filezillapro.com/"
SRC_URI="https://distfiles.obentoo.org/${P}_x86_64-linux-gnu.tar.xz"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64"

# pugixml 1.7 minimal dependency is for c++11 proper configuration
RDEPEND="
	>=dev-libs/nettle-3.1:=
	>=dev-db/sqlite-3.7
	>=dev-libs/boost-1.76.0:=
	>=dev-libs/libfilezilla-0.50.0:=
	>=dev-libs/pugixml-1.7
	>=net-libs/gnutls-3.5.7
	x11-libs/gtk+:2
	x11-misc/xdg-utils"
DEPEND="${RDEPEND}"

S="${WORKDIR}/FileZilla3"

# The manual route comes FIRST and stays complete on its own: bentoolkit is not a
# dependency of this package, and whoever does not have it installed may not be
# left without a way to get the archive.
pkg_nofetch() {
	einfo "Please download"
	einfo "  - ${A}"
	einfo "from ${HOMEPAGE} and place it in your DISTDIR directory."
	einfo
	einfo "With app-portage/bentoolkit installed and your licence serial exported"
	einfo "as \$FILEZILLA_PRO_KEY (or kept in ~/.config/bentoo/secrets), one"
	einfo "command does the same:"
	einfo
	einfo "  bentoo distfile fetch ${CATEGORY}/${PN} --version ${PV}"
}

src_prepare() {
	default
	cd "${WORKDIR}/FileZilla3/share/applications/" || die
	mv filezilla.desktop filezilla-pro.desktop || die
	sed -i \
		-e 's/Exec=filezilla/Exec=filezilla-pro/' \
		-e 's/Icon=filezilla/Icon=filezilla-pro/' \
		filezilla-pro.desktop || die
}

src_install() {
	insinto /opt/${PN}
	doins -r * || die

	fperms +x "/opt/${PN}/bin/filezilla"
	dosym "/opt/${PN}/bin/filezilla" /usr/bin/filezilla-pro

	fperms +x "/opt/${PN}/bin/fzstorj"
	dosym "/opt/${PN}/bin/fzstorj" /usr/bin/fzstorj-pro

	newicon share/pixmaps/filezilla.png filezilla-pro.png
	domenu share/applications/filezilla-pro.desktop
}

pkg_postinst() {
	xdg_desktop_database_update
	xdg_mimeinfo_database_update
	xdg_icon_cache_update
}

pkg_postrm() {
	xdg_desktop_database_update
	xdg_mimeinfo_database_update
	xdg_icon_cache_update
}
