# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DOCS_BUILDER="doxygen"
DOCS_DIR=""

PYTHON_COMPAT=( python3_{11..14} )

inherit cmake docs python-any-r1

DESCRIPTION="Unicode validation and transcoding at billions of characters per second"
HOMEPAGE="https://simdutf.github.io/simdutf/"
SRC_URI="https://github.com/${PN}/${PN}/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="|| ( Apache-2.0 MIT )"
SLOT="0/34"
KEYWORDS="amd64 arm arm64 ~loong ppc ppc64 ~riscv ~sparc x86"
IUSE="test"
RESTRICT="!test? ( test )"

RDEPEND="
	virtual/libiconv
"
DEPEND="${RDEPEND}"
BDEPEND="
	${PYTHON_DEPS}
	virtual/pkgconfig
	doc? (
		app-text/doxygen
	)
"

# BENTOO-DIVERGENCE: SIMDUTF_CXX_STANDARD - ::gentoo builds with upstream's
# default of C++17; bentoo builds with C++20.
#
# The atomic base64 API (simdutf::atomic_binary_to_base64,
# simdutf::atomic_base64_to_binary_safe) is compiled into the library only when
# SIMDUTF_ATOMIC_REF is set, and portability.h sets it from
# __cpp_lib_atomic_ref, i.e. from the C++ standard *in effect at compile time*.
# The same gate is re-evaluated in the installed header, so a consumer built
# with -std=c++20 sees the declarations while a C++17-built libsimdutf.so does
# not export the definitions. That mismatch is a link error in the consumer,
# not here, which is why nothing flags it at merge time.
#
# net-libs/nodejs >= 26.10.0 is the case in the tree: V8's builtins-typed-array.cc
# is compiled with -std=gnu++20 and calls both functions, so mksnapshot fails to
# link against a C++17 simdutf with "undefined reference to
# simdutf::atomic_binary_to_base64".
#
# Measured on 2026-09-22 with gcc 16.2.0, symbol diff C++17 -> C++20:
#   3 atomic base64 symbols gained (plus 2 weak template instantiations)
#   0 non-weak symbols lost, SONAME and SLOT unchanged -> purely additive
#
# Note for the next bump: re-check that upstream still gates on
# SIMDUTF_CXX_STANDARD. If ::gentoo ever adopts C++20 this whole ebuild should
# be dropped rather than carried forward.
src_configure() {
	local mycmakeargs+=(
		-DSIMDUTF_CXX_STANDARD=20
		-DSIMDUTF_TESTS=$(usex test)
		-DSIMDUTF_ATOMIC_BASE64_TESTS=$(usex test)
	)
	cmake_src_configure
}

src_compile() {
	cmake_src_compile
	use doc && docs_compile
}

src_install() {
	cmake_src_install
	use doc && einstalldocs
}
