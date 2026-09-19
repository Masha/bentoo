# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cmake

# extern/resources submodule as pinned by the 1.1.2 tag
RESOURCES_COMMIT="f3e6e289db3cb7fe0a1a21e65430f221fe598882"

DESCRIPTION="PoDoFo is a C++ library to work with the PDF file format"
HOMEPAGE="https://github.com/podofo/podofo"
SRC_URI="https://github.com/podofo/podofo/archive/refs/tags/${PV}.tar.gz -> ${P}.tar.gz
	test? (
		https://github.com/podofo/podofo-resources/archive/${RESOURCES_COMMIT}.tar.gz
			-> ${P}-test-resources.tar.gz
	)
"

# BENTOO-DIVERGENCE: LICENSE - no "tools? ( GPL-2+ )" branch, because this
# package never builds the tools (see PODOFO_BUILD_UNSUPPORTED_TOOLS below).
# Only the LGPL-2+ library is installed.
LICENSE="LGPL-2+"

# BENTOO-DIVERGENCE: SLOT - ::gentoo ships 0/2 (PoDoFo 0.10.x). The 1.x API is a
# hard source break: PdfErrorCode::Flate became FlateError,
# PdfOutlineItem::CreateChild() lost an argument, page appending moved to
# PdfPageCollection::AppendDocumentPages(), and PdfMemDocument grew
# CreateDestination(). Consumers cannot be ported one at a time against a single
# shared install, so this slot lives entirely inside a private prefix and
# coexists with app-text/podofo:0:
#
#   headers   /usr/include/podofo-1/podofo/
#   library   /usr/$(get_libdir)/podofo-1/
#
# Nothing lands in a default search path, so a consumer opts in explicitly.
# Today that is app-text/calibre alone, which moved to the 1.x API in 9.15.0 and
# points setup.py at the prefix through PODOFO_INC_DIR/PODOFO_LIB_DIR plus an
# RPATH. app-office/scribus and kde-misc/krename keep using :0 from ::gentoo,
# untouched. The subslot is upstream's SOVERSION (4 here, 2 in the 0.10.x line).
SLOT="1/4"

# BENTOO-DIVERGENCE: KEYWORDS - ~amd64 ~arm64 only, where ::gentoo's 0.10.x is
# stable on several arches. Nothing here is amd64-specific; the narrower set is
# "not yet built anywhere else", not a restriction, and widening it only needs a
# build on the arch in question.
KEYWORDS="~amd64 ~arm64"

# BENTOO-DIVERGENCE: IUSE - "lcms" is new (1.x added PODOFO_WITH_LCMS2 for ICC
# profile reading), while "idn" and "tools" are gone: 1.x dropped the libidn
# dependency outright, and the tools are unsupported upstream and would install
# binaries colliding with :0.
# BENTOO-DIVERGENCE: IUSE_DEFAULTS - fontconfig, jpeg and png default on, where
# ::gentoo leaves all three off. Turning any of them off silently removes a
# feature app-text/calibre uses (font embedding, image extraction), and calibre
# depends on [jpeg,png] for that reason.
IUSE="+fontconfig +jpeg lcms +png test tiff"
RESTRICT="!test? ( test )"

# BENTOO-DIVERGENCE: DEPEND - media-libs/lcms replaces net-dns/libidn: 1.x
# removed the libidn code path and added optional little-cms2 support.
# BENTOO-DIVERGENCE: RDEPEND - the same swap, this is where it is written.
# BENTOO-DIVERGENCE: metadata.xml - describes the private-prefix arrangement
# above, which has no counterpart in ::gentoo's file.
RDEPEND="
	dev-libs/libxml2:=
	dev-libs/openssl:=
	media-libs/freetype:2=
	virtual/zlib:=
	fontconfig? ( media-libs/fontconfig:= )
	jpeg? ( media-libs/libjpeg-turbo:= )
	lcms? ( media-libs/lcms:2= )
	png? ( media-libs/libpng:= )
	tiff? ( media-libs/tiff:= )
"
DEPEND="${RDEPEND}"
BDEPEND="
	virtual/pkgconfig
	test? ( fontconfig? ( media-fonts/liberation-fonts ) )
"

# BENTOO-DIVERGENCE: PATCHES - none, where ::gentoo backports
# podofo-0.10.3-libcxx-20-from_chars.patch. That commit
# (aa9267229b40b49e5927f286841be4cbe81d05d5) is already in the 1.x line.

src_prepare() {
	cmake_src_prepare

	if use test; then
		rmdir extern/resources || die
		mv "${WORKDIR}/podofo-resources-${RESOURCES_COMMIT}" extern/resources || die
	fi
}

src_configure() {
	# The 3rdparty/ directory (fmt, date, fastfloat, utf8cpp, utf8proc,
	# tcbspan) stays vendored: upstream tracks unreleased revisions of those
	# and the PODOFO_DEVENDOR_* switches demand exactly the pinned ones.
	local mycmakeargs=(
		# private prefix -- see the SLOT comment above
		-DCMAKE_INSTALL_INCLUDEDIR="include/podofo-1"
		-DCMAKE_INSTALL_LIBDIR="$(get_libdir)/podofo-1"

		-DPODOFO_BUILD_STATIC=FALSE
		-DPODOFO_BUILD_TEST=$(usex test TRUE FALSE)
		-DPODOFO_BUILD_EXAMPLES=FALSE
		# tools would install podofo* binaries that collide with :0
		-DPODOFO_BUILD_UNSUPPORTED_TOOLS=FALSE

		-DPODOFO_WITH_FONTMANAGER=$(usex fontconfig ON OFF)
		-DPODOFO_WITH_LCMS2=$(usex lcms ON OFF)
		$(cmake_use_find_package jpeg JPEG)
		$(cmake_use_find_package png PNG)
		$(cmake_use_find_package tiff TIFF)
	)

	cmake_src_configure
}
