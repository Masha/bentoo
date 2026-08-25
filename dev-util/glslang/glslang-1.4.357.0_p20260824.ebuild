# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{11..14} )
inherit cmake-multilib python-any-r1

if [[ ${PV} == *9999* ]]; then
	EGIT_REPO_URI="https://github.com/KhronosGroup/${PN}.git"
	inherit git-r3
else
	GIT_COMMIT="23076b376e06a99b4c765df5c9836d127c8bbbfc"
	SRC_URI="https://github.com/KhronosGroup/${PN}/archive/${GIT_COMMIT}.tar.gz -> ${P}.tar.gz"
	KEYWORDS="~amd64 ~arm ~arm64 ~loong ~ppc ~ppc64 ~riscv ~x86"
	S="${WORKDIR}/${PN}-${GIT_COMMIT}"
fi

DESCRIPTION="Khronos reference front-end for GLSL and ESSL, and sample SPIR-V generator"
HOMEPAGE="https://www.khronos.org/opengles/sdk/tools/Reference-Compiler/ https://github.com/KhronosGroup/glslang"

LICENSE="BSD"
SLOT="0/16.1"

# BENTOO-DIVERGENCE: DEPEND - ::gentoo pins the SDK in lockstep (~pkg-${PV});
# bentoo ships snapshots that bump on independent dates, so an exact pin can
# never be satisfied. A floor on the companion snapshot keeps the coupling the
# pin exists to enforce. Raise it on every spirv-tools bump.
BDEPEND="${PYTHON_DEPS}
	>=dev-util/spirv-tools-1.4.357.0_p20260813[${MULTILIB_USEDEP}]
"

DEPEND=">=dev-util/spirv-tools-1.4.357.0_p20260813[${MULTILIB_USEDEP}]"
RDEPEND="${DEPEND}"

multilib_src_configure() {
	local mycmakeargs=(
		-DENABLE_PCH=OFF
		-DALLOW_EXTERNAL_SPIRV_TOOLS=ON
	)
	cmake_src_configure
}
