# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cmake multilib

MY_PN="${PN%-compat}"

DESCRIPTION="libjxl runtime libraries for prebuilt packages linked against the 0.11 ABI"
HOMEPAGE="https://github.com/libjxl/libjxl/"
SRC_URI="
	https://github.com/libjxl/libjxl/archive/refs/tags/v${PV}.tar.gz
		-> ${MY_PN}-${PV}.tar.gz
"
S="${WORKDIR}/${MY_PN}-${PV}"

LICENSE="BSD"
SLOT="$(ver_cut 1-2)"
KEYWORDS="~amd64 ~arm64"

# media-libs/libjxl carries SLOT="0/$(ver_cut 1-2)", so only one ABI of it can
# ever be installed. This package supplies the older runtime alongside it,
# without headers, pkg-config files or tools, so nothing links against it.
RDEPEND="
	app-arch/brotli:=
	>=dev-cpp/highway-1.0.7
	>=media-libs/lcms-2.13:2
"
DEPEND="${RDEPEND}"

src_configure() {
	# Everything that is not the core decoding library is off: this package
	# ships two shared objects and nothing else.
	local mycmakeargs=(
		-DBUILD_TESTING=OFF
		-DCMAKE_DISABLE_FIND_PACKAGE_PNG=ON
		-DJPEGXL_ENABLE_BENCHMARK=OFF
		-DJPEGXL_ENABLE_COVERAGE=OFF
		-DJPEGXL_ENABLE_DOXYGEN=OFF
		-DJPEGXL_ENABLE_EXAMPLES=OFF
		-DJPEGXL_ENABLE_FUZZERS=OFF
		-DJPEGXL_ENABLE_JNI=OFF
		-DJPEGXL_ENABLE_JPEGLI=OFF
		-DJPEGXL_ENABLE_JPEGLI_LIBJPEG=OFF
		-DJPEGXL_ENABLE_MANPAGES=OFF
		-DJPEGXL_ENABLE_OPENEXR=OFF
		-DJPEGXL_ENABLE_PLUGINS=OFF
		-DJPEGXL_ENABLE_SJPEG=OFF
		-DJPEGXL_ENABLE_SKCMS=OFF
		-DJPEGXL_ENABLE_TCMALLOC=OFF
		-DJPEGXL_ENABLE_TOOLS=OFF
		-DJPEGXL_ENABLE_VIEWERS=OFF
		-DJPEGXL_FORCE_SYSTEM_BROTLI=ON
		-DJPEGXL_FORCE_SYSTEM_HWY=ON
		-DJPEGXL_FORCE_SYSTEM_LCMS2=ON
		-DJPEGXL_WARNINGS_AS_ERRORS=OFF
	)

	cmake_src_configure
}

src_install() {
	# Install into a scratch DESTDIR first: CMake drops the build-tree RPATH
	# on install, and only two of the resulting files belong in a compat
	# package. Headers, pkg-config files and CMake exports are deliberately
	# left behind -- they would collide with media-libs/libjxl and would let
	# other packages build against this old ABI.
	DESTDIR="${T}/full" cmake_build install

	local lib
	for lib in libjxl libjxl_cms; do
		dolib.so "${T}/full/usr/$(get_libdir)/${lib}.so.${PV}"
		dosym "${lib}.so.${PV}" "/usr/$(get_libdir)/${lib}.so.$(ver_cut 1-2)"
	done
}
