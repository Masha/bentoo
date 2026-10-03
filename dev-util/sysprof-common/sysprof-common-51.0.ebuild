# Copyright 2020-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
# GNOME 51 mirror ahead of ::gentoo; drop each tag below when ::gentoo reaches this version

EAPI=8
GNOME_ORG_MODULE="sysprof"

inherit gnome.org

DESCRIPTION="Static library for sysprof capture data generation"
HOMEPAGE="https://www.sysprof.com/"

LICENSE="GPL-3+ GPL-2+"
SLOT="0"
KEYWORDS="~amd64 ~arm64 ~loong ~x86"

src_install() {
	insinto /usr/share/dbus-1/interfaces/
	doins "${S}"/src/sysprofd/org.gnome.Sysprof3.Profiler.xml
}
