# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# bentoo carries this ahead of ::gentoo, which is still on 1.18.1.
#
# It is deliberately ADDITIVE, not a replacement:
#  * SLOT is 1.19, so it installs beside dev-build/automake:1.18;
#  * autotools.eclass is NOT overridden here, so eautoreconf keeps using the
#    ::gentoo default (_LATEST_AUTOMAKE=1.18.1:1.18), and am-wrapper.sh only
#    scans down from its own LAST_KNOWN_AUTOMAKE_VER=18 before falling back.
# Reach this slot explicitly with WANT_AUTOMAKE=1.19.
#
# Upstream changed release manager: 1.18.1 was the last tarball signed by
# Karl Berry, 1.19 the first signed by Kamila Szewczyk. Hence the key package
# below differs from the one ::gentoo's automake ebuilds use.

# BENTOO-DIVERGENCE: BDEPEND - sec-keys/openpgp-keys-kamilaszewczyk where
# ::gentoo's automake ebuilds use sec-keys/openpgp-keys-karlberry. Not a
# preference: 1.18.1 is the last tarball signed by Karl Berry's key
# 0716748A30D155AD, and 1.19 is signed by Kamila Szewczyk's ed25519 subkey
# D5D527E7E338A682CBADB1C1217FCF7314636C07 instead. Verified 2026-09-10 by
# `gpgv` against both keys: karlberry fails, kamilaszewczyk succeeds, and the
# primary key is in https://ftp.gnu.org/gnu/gnu-keyring.gpg, which ties it to
# the GNU project rather than to a keyserver upload alone. This row aligns by
# itself once ::gentoo ships 1.19 and switches key packages too.

PYTHON_COMPAT=( python3_{12..15} )

inherit python-any-r1 verify-sig

MANGLED_SLOT=${PV:0:4}

VERIFY_SIG_OPENPGP_KEY_PATH=/usr/share/openpgp-keys/kamilaszewczyk.asc

DESCRIPTION="Used to generate Makefile.in from Makefile.am"
HOMEPAGE="https://www.gnu.org/software/automake/"
SRC_URI="
	mirror://gnu/${PN}/${P}.tar.xz
	verify-sig? (
		mirror://gnu/${PN}/${P}.tar.xz.sig
	)
"

LICENSE="GPL-2+ FSFAP"
# Use Gentoo versioning for slotting.
SLOT="${MANGLED_SLOT}"
KEYWORDS="~alpha ~amd64 ~arm ~arm64 ~hppa ~loong ~m68k ~mips ~ppc ~ppc64 ~riscv ~s390 ~sparc ~x86 ~arm64-macos ~x64-macos ~x64-solaris"
IUSE="test"
RESTRICT="!test? ( test )"

RDEPEND="
	>=dev-lang/perl-5.6
	>=dev-build/automake-wrapper-20250528
	>=dev-build/autoconf-2.69:*
	sys-devel/gnuconfig
"
BDEPEND="
	app-alternatives/gzip
	sys-apps/help2man
	dev-build/autoconf-wrapper
	dev-build/autoconf
	test? (
		${PYTHON_DEPS}
		dev-util/dejagnu
		sys-devel/bison
		sys-devel/flex
	)
	verify-sig? ( sec-keys/openpgp-keys-kamilaszewczyk )
"

pkg_setup() {
	use test && python-any-r1_pkg_setup
}

src_prepare() {
	default

	export WANT_AUTOCONF=2.5

	# ::gentoo's 1.18.1 ebuild runs ./bootstrap here. Do NOT copy that across:
	# as of 1.19 the script refuses to run outside a git checkout ("If you
	# desire to run the bootstrap script in some tree that is not a git
	# checkout, just mkdir .git"), and it is right to. The release tarball
	# already ships configure, Makefile.in, aclocal.m4 and doc/automake.info,
	# and bootstrap exists to regenerate them from a VCS tree — running it on a
	# tarball only makes makeinfo a hard build dependency (bug #628912, worked
	# around below). Nothing here needs regenerating.
	sed -i -e "/APIVERSION=/s:=.*:=${SLOT}:" configure || die
	grep -q "^APIVERSION=${SLOT}$" configure ||
		die "APIVERSION rewrite did not match; upstream changed configure"

	# bug #628912
	if ! has_version -b sys-apps/texinfo ; then
		touch doc/{stamp-vti,version.texi,automake.info} || die
	fi
}

src_configure() {
	# Also used in install.
	infopath="${EPREFIX}/usr/share/automake-${PV}/info"
	econf --infodir="${infopath}"
}

src_test() {
	# Fails with byacc/flex
	emake YACC="bison -y" LEX="flex" check
}

src_install() {
	default

	# dissuade Portage from removing our dir file
	touch "${ED}"/usr/share/${P}/info/.keepinfodir || die
	docompress -x /usr/share/${P}/info/dir

	rm "${ED}"/usr/share/aclocal/README || die
	rmdir "${ED}"/usr/share/aclocal || die
	rm \
		"${ED}"/usr/bin/{aclocal,automake} \
		"${ED}"/usr/share/man/man1/{aclocal,automake}.1 || die

	# remove all config.guess and config.sub files replacing them
	# w/a symlink to a specific gnuconfig version
	local x
	for x in guess sub ; do
		dosym ../gnuconfig/config.${x} \
			/usr/share/${PN}-${SLOT}/config.${x}
	done

	# Avoid QA message about pre-compressed file in docs
	local tarfile="${ED}/usr/share/doc/${PF}/amhello-1.0.tar.gz"
	if [[ -f "${tarfile}" ]] ; then
		gunzip "${tarfile}" || die
	fi

	pushd "${D}/${infopath}" >/dev/null || die
	local f
	for f in *.info*; do
		# Install convenience aliases for versioned Automake pages.
		ln -s "$f" "${f/./-${PV}.}" || die
	done
	popd >/dev/null || die

	# Lower number sorts first in /etc/env.d, so the newest slot wins INFOPATH.
	local major="$(ver_cut 1)"
	local minor="$(ver_cut 2)"
	local idx="$((99999-(major*1000+minor)))"
	newenvd - "06automake${idx}" <<-EOF
	INFOPATH="${infopath}"
	EOF

	docompress "${infopath}"
}
