# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="bind tools: dig, nslookup, host, nsupdate, dnssec-keygen"
HOMEPAGE="https://www.isc.org/bind/ https://gitlab.isc.org/isc-projects/bind9"

LICENSE="Apache-2.0 BSD BSD-2 GPL-2 HPND ISC MPL-2.0"
SLOT="0"
KEYWORDS="~alpha amd64 arm arm64 ~hppa ~loong ~m68k ~mips ppc ppc64 ~riscv ~s390 ~sparc x86"
# BENTOO-DIVERGENCE: IUSE - no caps flag, and this one is ::gentoo's bug rather
# than a gap here. Both ebuilds are dummies whose only job is to forward flags
# to net-dns/bind, and ::gentoo's 9.18.0-r1 forwards [caps?] to a package that
# has no caps flag - measured 2026-09-07 across every bind in ::gentoo, 9.18.38
# through 9.20.27, and not one declares it. Forwarding a dead flag is what this
# ebuild declines to copy.
IUSE="doc gssapi idn libedit readline xml"

RDEPEND="=net-dns/bind-9.20*[doc?,gssapi?,idn?,xml?]"

pkg_postinst() {
	ewarn "net-dns/bind-tools is now merged into net-dns/bind and"
	ewarn "net-dns/bind-tools serves as a dummy package until it is"
	ewarn "eventually removed. The split was already a maintenance burden"
	ewarn "because of lack of build system support for it, but this became"
	ewarn "more severe with >=9.18.0."
	ewarn ""
	ewarn "Please run the following commands:"
	ewarn "* emerge --deselect net-dns/bind-tools"
	ewarn "* emerge --noreplace net-dns/bind instead"
	ewarn ""
	ewarn "For the latest maintained versions, including >=9.20,"
	ewarn "ensure you are using net-dns/bind directly."
}
