# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cmake

DESCRIPTION="Header-only C++ binding for libzmq (ZeroMQ)"
HOMEPAGE="https://github.com/zeromq/cppzmq"
SRC_URI="https://github.com/zeromq/cppzmq/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
IUSE="test"
RESTRICT="!test? ( test )"

# zmq.hpp is a C++ wrapper over the libzmq C API, so libzmq is needed both to
# build anything against this header and at runtime.  Nothing is compiled here.
RDEPEND="net-libs/zeromq"
DEPEND="${RDEPEND}"
# Upstream 4.11.0 moved the test suite to Catch2 v3 (<catch2/catch_all.hpp>,
# Catch2::Catch2WithMain).  Without an installed Catch2 the tests/CMakeLists.txt
# falls back to FetchContent, which the network sandbox forbids -- so the dep is
# mandatory whenever USE=test is on.
BDEPEND="test? ( >=dev-cpp/catch-3 )"

src_configure() {
	local mycmakeargs=(
		-DCPPZMQ_BUILD_TESTS=$(usex test)
	)
	cmake_src_configure
}
