# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DOCS_BUILDER="doxygen"
DOCS_DIR=""

PYTHON_COMPAT=( python3_{12..14} )

inherit cmake docs python-any-r1

DESCRIPTION="Unicode validation and transcoding at billions of characters per second"
HOMEPAGE="https://simdutf.github.io/simdutf/"
SRC_URI="https://github.com/${PN}/${PN}/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="|| ( Apache-2.0 MIT )"
SLOT="0/36"
KEYWORDS="~amd64 ~arm ~arm64 ~loong ~ppc ~ppc64 ~riscv ~sparc ~x86"
# BENTOO-DIVERGENCE: IUSE_DEFAULTS - "+atomic-base64" where ::gentoo ships it
# off. The flag builds the library as C++20, which is the only way it exports
# simdutf::atomic_binary_to_base64 / atomic_base64_to_binary_safe: upstream's
# portability.h gates them on __cpp_lib_atomic_ref, i.e. on the standard in
# effect when the .so was compiled. net-libs/nodejs >= 26.10.0 calls both from
# V8 (built -std=gnu++20) and depends on [atomic-base64]; default-off would make
# every node user hand-edit package.use for a purely additive change (measured
# 2026-09-22: 3 symbols gained, none lost, SONAME unchanged).
#
# This is the only difference from ::gentoo. If ::gentoo ever flips the default,
# drop this package rather than carry it forward.
IUSE="+atomic-base64 test"
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

src_configure() {

	local mycmakeargs+=(
		-DSIMDUTF_TESTS=$(usex test)
		-DSIMDUTF_ATOMIC_BASE64_TESTS=$(usex test)
	)

	if use atomic-base64; then
		mycmakeargs+=(
			-DSIMDUTF_CXX_STANDARD=20
		)
	fi

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
