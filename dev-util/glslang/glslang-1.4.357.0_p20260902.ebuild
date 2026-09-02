# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{11..14} )
inherit cmake-multilib python-any-r1

if [[ ${PV} == *9999* ]]; then
	EGIT_REPO_URI="https://github.com/KhronosGroup/${PN}.git"
	inherit git-r3
else
	GIT_COMMIT="e7e245dd9f759862bd7dda7fc6a2953e0f0384f6"
	SRC_URI="https://github.com/KhronosGroup/${PN}/archive/${GIT_COMMIT}.tar.gz -> ${P}.tar.gz"
	KEYWORDS="~amd64 ~arm ~arm64 ~loong ~ppc ~ppc64 ~riscv ~x86"
	S="${WORKDIR}/${PN}-${GIT_COMMIT}"
fi

DESCRIPTION="Khronos reference front-end for GLSL and ESSL, and sample SPIR-V generator"
HOMEPAGE="https://www.khronos.org/opengles/sdk/tools/Reference-Compiler/ https://github.com/KhronosGroup/glslang"

LICENSE="BSD"
# BENTOO-DIVERGENCE: SLOT - ::gentoo tracks the released tag and carries 0/16.4;
# this snapshot builds libglslang.so.16.5.0, so the subslot follows the library
# the package actually installs. It had been stale at 0/16.1 since the ebuild
# was copied over from glslang-1.4.335.0. Bump it whenever the built soname
# minor changes -- glslang breaks C++ ABI between minors.
SLOT="0/16.5"

# BENTOO-DIVERGENCE: DEPEND - ::gentoo pins the SDK in lockstep (~pkg-${PV});
# bentoo ships snapshots that bump on independent dates, so an exact pin can
# never be satisfied. A floor on the companion snapshot keeps the coupling the
# pin exists to enforce. Raise it on every spirv-tools bump.
BDEPEND="${PYTHON_DEPS}
	>=dev-util/spirv-tools-1.4.357.0_p20260813[${MULTILIB_USEDEP}]
"

DEPEND=">=dev-util/spirv-tools-1.4.357.0_p20260813[${MULTILIB_USEDEP}]"
RDEPEND="${DEPEND}"

# BENTOO-DIVERGENCE: PATCHES - not in ::gentoo, which sits on the released tag
# and never saw the offending commit. Upstream eaff806e (PR #4052, 2026-08-24)
# made glslang emit the LocalSizeId execution mode from SPIR-V 1.2 instead of
# 1.6, without declaring SPV_KHR_maintenance4 -- so the module it produces is
# rejected by spirv-val under Vulkan. Breaks the whole ggml shader tree
# (obentoo/bentoo#42). Because this package tracks main by commit, the patch
# carries no version in its name: the autoupdate applier never renames files/.
# Drop it -- do not rebase -- once upstream fixes the gate. See the patch
# header for what is deliberately NOT reverted.
PATCHES=(
	"${FILESDIR}"/${PN}-revert-localsizeid-below-spv16.patch
)

multilib_src_configure() {
	local mycmakeargs=(
		-DENABLE_PCH=OFF
		-DALLOW_EXTERNAL_SPIRV_TOOLS=ON
	)
	cmake_src_configure
}
