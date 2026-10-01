# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=hatchling
PYTHON_COMPAT=( python3_14 )

inherit distutils-r1

DESCRIPTION="Builds Bentoo (Gentoo stage5) images and live ISOs from a stage3"
HOMEPAGE="https://github.com/obentoo/shidashi"
SRC_URI="https://github.com/obentoo/${PN}/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="MIT"
SLOT="0"
# amd64 only: Shidashi runs amd64 stage3s in systemd-nspawn on the host itself
# and its arch axis is x86-64 only (v3, znver5, arrowlake), so an arm64 host
# cannot run a build -- upstream does not support it.
KEYWORDS="~amd64"
IUSE="+iso vm"

# Always: systemd-nspawn runs every build stage (and systemd-ssh-proxy reaches
# the VM), gpg verifies the stage3 and the ::gentoo snapshot, git fetches the
# pinned overlays. Portage itself runs inside the containers, not on the host.
# sys-apps/systemd is a hard dependency on purpose: nspawn has no standalone
# package, so a host without systemd (split-usr, musl profiles) cannot build.
RDEPEND="
	app-crypt/gnupg
	dev-python/pydantic[${PYTHON_USEDEP}]
	dev-python/pyyaml[${PYTHON_USEDEP}]
	dev-python/rich[${PYTHON_USEDEP}]
	dev-python/typer[${PYTHON_USEDEP}]
	dev-vcs/git
	sys-apps/systemd
	iso? (
		dev-libs/libisoburn
		sys-boot/grub[grub_platforms_efi-64,grub_platforms_pc]
		sys-fs/mtools
		sys-fs/squashfs-tools
	)
	vm? (
		app-emulation/qemu
		virtual/ssh
		|| (
			sys-firmware/edk2-bin
			sys-firmware/edk2
		)
	)
"

EPYTEST_PLUGINS=()
distutils_enable_tests pytest

python_install_all() {
	distutils-r1_python_install_all

	# The recipes (variants/) and the pinned inputs (seeds/) are data, not
	# code: the wheel carries only the package, and Shidashi looks for them
	# beside it unless told otherwise. Ship them read-only under
	# /usr/share/shidashi and point the variables Shidashi honors at them; a
	# curator sets SHIDASHI_VARIANTS_DIR to an own checkout to edit recipes.
	insinto /usr/share/${PN}
	doins -r variants seeds

	newenvd - 90${PN} <<-EOF
		SHIDASHI_VARIANTS_DIR="${EPREFIX}/usr/share/${PN}/variants"
		SHIDASHI_SEEDS_DIR="${EPREFIX}/usr/share/${PN}/seeds"
	EOF
}
