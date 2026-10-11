# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="OpenPGP keys used to sign CachyOS kernel source releases"
HOMEPAGE="https://github.com/CachyOS/linux"
# The two keys linux-cachyos's PKGBUILD lists in validpgpkeys.
SRC_URI="
	https://keys.openpgp.org/vks/v1/by-fingerprint/E8B9AA39F054E30E8290D492C3C4820857F654FE
		-> ${P}-ptr1337.asc
	https://keys.openpgp.org/vks/v1/by-fingerprint/E18447AC260021D31F3FF6C4C8A2A4774B8B63C4
		-> ${P}-dnaim.asc
"
S=${WORKDIR}

LICENSE="public-domain"
SLOT="0"
KEYWORDS="~amd64"

src_install() {
	local files=( ${A} )
	insinto /usr/share/openpgp-keys
	newins - cachyos.asc < <(cat "${files[@]/#/${DISTDIR}/}")
}
