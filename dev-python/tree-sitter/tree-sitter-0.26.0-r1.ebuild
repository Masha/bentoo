# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_EXT=1
DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{12..15} )

inherit distutils-r1

DESCRIPTION="Python bindings to the Tree-sitter parsing library"
HOMEPAGE="
	https://github.com/tree-sitter/py-tree-sitter/
	https://pypi.org/project/tree-sitter/
"
SRC_URI="
	https://github.com/tree-sitter/py-tree-sitter/archive/v${PV}.tar.gz
		-> ${P}.gh.tar.gz
"
S=${WORKDIR}/py-${P}

LICENSE="MIT"
SLOT="0"
KEYWORDS="~alpha amd64 arm arm64 ~hppa ~loong ~mips ppc ppc64 ~riscv ~s390 ~sparc x86"

# setuptools is needed for distutils import
DEPEND="=dev-libs/tree-sitter-0.26*:="
RDEPEND="
	${DEPEND}
	dev-python/setuptools[${PYTHON_USEDEP}]
"
BDEPEND="
	test? (
		>=dev-libs/tree-sitter-html-0.23.2[python,${PYTHON_USEDEP}]
		>=dev-libs/tree-sitter-javascript-0.23.1[python,${PYTHON_USEDEP}]
		>=dev-libs/tree-sitter-json-0.24.8[python,${PYTHON_USEDEP}]
		>=dev-libs/tree-sitter-python-0.23.6[python,${PYTHON_USEDEP}]
		>=dev-libs/tree-sitter-rust-0.23.2[python,${PYTHON_USEDEP}]
	)
"

distutils_enable_tests pytest

# BENTOO-DIVERGENCE: PATCHES - point-refcount fix, not in ::gentoo yet.
# Point.row/.column return a borrowed reference where a getter must return a
# strong one, so a temporary Point frees an integer its caller still holds.
# That use-after-free makes dev-util/pkgcheck segfault in roughly half of all
# scans -- inside a multiprocessing worker, so it still exits 0 and silently
# drops whole checks.  Regression introduced upstream in 0.26.0 (0.25.2 built
# Point with PyStructSequence); v0.26.0 is still the latest tag, so there is no
# fixed release to bump to.  Drop this patch once upstream ships the fix.
PATCHES=(
	"${FILESDIR}"/${PN}-0.22.2-unbundle.patch
	"${FILESDIR}"/${PN}-0.26.0-point-refcount.patch
)

src_unpack() {
	default
	rmdir "${S}/tree_sitter/core" || die
}

src_test() {
	rm -r tree_sitter || die
	distutils-r1_src_test
}
