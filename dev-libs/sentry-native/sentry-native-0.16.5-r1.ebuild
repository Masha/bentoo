# Copyright 1999-2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# BENTOO-DIVERGENCE: PATCHES - none, where ::gentoo wraps sentry_fuzz_json in
# if(0) via sentry-native-0.6.5_no-fuzz-test.patch. Not copied because it does
# not apply: measured 2026-09-07 against the 0.16.5 tarball, hunk 1 lands with
# fuzz at a 33-line offset and hunk 2 fails outright - tests/unit/CMakeLists.txt
# has been restructured since 0.6.5.
#
# WHAT THAT LEAVES OPEN, stated rather than glossed: the fuzz target is still
# built and registered under USE=test here, and ::gentoo's reason for disabling
# it (it needs a special, performance-killing build to work at all) has not gone
# away. Rebasing the patch is the fix; it was out of scope for a parity pass.
inherit cmake

DESCRIPTION="Sentry SDK for C, C++ and native applications"
HOMEPAGE="https://sentry.io/ https://github.com/getsentry/sentry-native"
SRC_URI="https://github.com/getsentry/${PN}/archive/refs/tags/${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
IUSE="+breakpad +curl test"
RESTRICT="!test? ( test )"

RDEPEND="
	breakpad? ( dev-util/breakpad )
	curl? (
		net-misc/curl
		virtual/zlib:=
	)
"
DEPEND="${RDEPEND}"
BDEPEND="virtual/pkgconfig"

src_configure() {
	local mycmakeargs=(
		-DSENTRY_BUILD_EXAMPLES=OFF
		-DSENTRY_BACKEND=$(usex breakpad "breakpad" "inproc")
		-DSENTRY_BUILD_TESTS=$(usex test)
		-DSENTRY_TRANSPORT=$(usex curl "curl" "none")
		-DSENTRY_TRANSPORT_COMPRESSION=$(usex curl)
	)
	# Avoid "not used by the project" warnings when USE=-breakpad
	if use breakpad; then
		mycmakeargs+=( -DSENTRY_BREAKPAD_SYSTEM=ON )
	fi

	cmake_src_configure
}
