# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
# GNOME 51 mirror ahead of ::gentoo; drop each tag below when ::gentoo reaches this version
# BENTOO-DIVERGENCE: INHERIT - 51.0 moved from autotools to meson
# BENTOO-DIVERGENCE: DEFINED_PHASES - 51.0 moved from autotools to meson
# BENTOO-DIVERGENCE: BDEPEND - meson >=1.7 plus itstool/gettext that gnome.yelp() needs

EAPI=8

inherit gnome.org meson

DESCRIPTION="GNOME end user documentation"
HOMEPAGE="https://gitlab.gnome.org/GNOME/gnome-user-docs"

LICENSE="CC-BY-3.0"
SLOT="0"
KEYWORDS="~alpha ~amd64 ~arm ~arm64 ~loong ~ppc ~ppc64 ~riscv ~sparc ~x86"
IUSE="test"

# 51.0 moved from autotools to meson; gnome.yelp() builds the translations
# with itstool + msgfmt, so both are now unconditional build dependencies.
BDEPEND="
	>=dev-build/meson-1.7.0
	dev-util/itstool
	sys-devel/gettext
	test? (
		app-text/yelp-tools
		dev-libs/libxml2
	)
"

# This ebuild does not install any binaries
RESTRICT="binchecks strip
	!test? ( test )"

src_configure() {
	local emesonargs=(
		$(meson_use test tests)
	)
	meson_src_configure
}
