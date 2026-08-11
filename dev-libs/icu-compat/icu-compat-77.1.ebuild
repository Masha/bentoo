# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit flag-o-matic multilib toolchain-funcs

MY_PV="${PV//./_}"

DESCRIPTION="ICU runtime libraries for prebuilt packages linked against the ICU 77 ABI"
HOMEPAGE="https://icu.unicode.org/"
SRC_URI="https://github.com/unicode-org/icu/releases/download/release-${PV/./-}/icu4c-${MY_PV}-src.tgz"
S="${WORKDIR}/icu/source"

LICENSE="BSD"
SLOT="$(ver_cut 1)"
KEYWORDS="~amd64 ~arm64"

# Nothing should ever build against this package: it exists so that binaries
# which were compiled elsewhere against SONAME libicu*.so.77 keep loading.
# Only the versioned runtime libraries are installed, so it never becomes a
# link-time target and never collides with dev-libs/icu.

src_configure() {
	# Upstream renames every exported symbol to u_foo_77; dev-libs/icu builds
	# with U_DISABLE_RENAMING=1 and exports plain u_foo instead. Keeping the
	# renaming enabled here is what lets both libraries live in one process:
	# their symbol namespaces do not overlap.
	local myeconfargs=(
		--disable-extras
		--disable-layoutex
		--disable-samples
		--disable-static
		--disable-tests
		--enable-renaming
	)

	# Workaround for bug #963337 (gcc PR122058)
	tc-is-gcc && [[ $(gcc-major-version) -ge 16 ]] && append-cxxflags -fno-devirtualize-speculatively

	# ICU tries to use clang by default
	tc-export CC CXX

	econf "${myeconfargs[@]}"
}

src_install() {
	# No headers, no unversioned .so symlinks, no pkg-config files and no
	# tools: each of those is either a file collision with dev-libs/icu or an
	# invitation for something to link against the wrong ABI.
	local lib
	for lib in libicudata libicui18n libicuuc; do
		dolib.so "lib/${lib}.so.${PV}"
		dosym "${lib}.so.${PV}" "/usr/$(get_libdir)/${lib}.so.$(ver_cut 1)"
	done
}
