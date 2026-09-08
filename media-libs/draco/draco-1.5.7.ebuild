# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cmake

DESCRIPTION="Library for compressing and decompressing 3D geometric meshes and point clouds"
HOMEPAGE="https://google.github.io/draco/ https://github.com/google/draco"
SRC_URI="https://github.com/google/draco/archive/refs/tags/${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="Apache-2.0"
# Subslot tracks the SONAME.  cmake/draco_build_definitions.cmake sets
# LT_CURRENT=9 / LT_AGE=0, so DRACO_SOVERSION_MAJOR is 9 and the library
# installs as libdraco.so.9.  Re-read that file on every version bump: the
# soname moves independently of ${PV}.
SLOT="0/9"
KEYWORDS="~amd64 ~arm64"

# The release tarball carries third_party/{googletest,eigen,filesystem,tinygltf}
# as empty submodule stubs, so DRACO_TESTS cannot be satisfied from it at all.
RESTRICT="test"

PATCHES=(
	# Upstream fills draco.pc from the RELATIVE GNUInstallDirs values, so the
	# installed file reads "-Iinclude -Llib64" and pkg-config hands consumers
	# two paths that do not exist.  cmake_src_prepare applies this.
	"${FILESDIR}"/${P}-pkgconfig-absolute-paths.patch
)

src_configure() {
	local mycmakeargs=(
		# Consumers link the imported target draco::draco into shared objects
		# of their own -- media-gfx/blender's intern/draco_bridge/ is exactly
		# that.  With BUILD_SHARED_LIBS=ON, CMakeLists.txt aliases draco::draco
		# onto draco_shared; with it OFF the alias points at the static archive
		# instead.
		-DBUILD_SHARED_LIBS=ON
		-DDRACO_INSTALL=ON
		-DDRACO_TESTS=OFF
		# The transcoder needs the eigen, filesystem and tinygltf submodules,
		# none of which ship in the release tarball.
		-DDRACO_TRANSCODER_SUPPORTED=OFF
	)

	cmake_src_configure
}

# DO NOT remove libdraco.a from the image, however unused a static archive on
# a shared build looks.  In cmake/draco_install.cmake the
# install(TARGETS draco_static EXPORT dracoExport ...) call is unconditional,
# so draco_static is a member of the exported set even when BUILD_SHARED_LIBS
# is ON, and draco-targets.cmake always references the archive.  Deleting it
# breaks find_package(draco) at *configure* time in every consumer with
# "imported target references a file that does not exist".
#
# Likewise, the CMake config lands in /usr/share/cmake/draco rather than
# /usr/$(get_libdir)/cmake/draco: draco_install.cmake hardcodes
# INSTALL_DESTINATION "${CMAKE_INSTALL_DATAROOTDIR}/cmake/draco".  That is a
# standard find_package search path, so it is left where upstream puts it.
