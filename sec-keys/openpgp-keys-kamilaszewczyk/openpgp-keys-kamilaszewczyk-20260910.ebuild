# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Kamila Szewczyk took over GNU Automake releases from Karl Berry: 1.18.1 is
# the last tarball signed by <karl@freefriends.org>, 1.19 the first signed
# here, with the ed25519 signing subkey D5D527E7E338A682CBADB1C1217FCF7314636C07
# created 2026-06-29. The primary key below is also present in the official
# https://ftp.gnu.org/gnu/gnu-keyring.gpg, which is what ties it to the GNU
# project rather than to the keyserver upload alone.

FINGERPRINT="6C222EA6B2BD216AA406516AC868F0B6DE38409D"

DESCRIPTION="OpenPGP keys used by Kamila Szewczyk to sign GNU Automake releases"
HOMEPAGE="https://iczelia.net/"
SRC_URI="
	https://keys.openpgp.org/vks/v1/by-fingerprint/${FINGERPRINT}
	-> ${FINGERPRINT}-${PV}.asc
"
S="${WORKDIR}"

LICENSE="public-domain"
SLOT="0"
KEYWORDS="~alpha ~amd64 ~arm ~arm64 ~hppa ~loong ~m68k ~mips ~ppc ~ppc64 ~riscv ~s390 ~sparc ~x86"

src_install() {
	local files=( ${A} )
	insinto /usr/share/openpgp-keys
	newins - kamilaszewczyk.asc < <(cat "${files[@]/#/${DISTDIR}/}" || die)
}
