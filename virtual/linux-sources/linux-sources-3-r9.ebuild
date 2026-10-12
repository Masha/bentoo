# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=9

# BENTOO-DIVERGENCE: RDEPEND - adds sys-kernel/bentoo-kernel, which installs
# the same module-build tree as sys-kernel/gentoo-kernel. Without it,
# linux-mod-r1's DEPEND on this virtual pulls sys-kernel/gentoo-sources onto
# machines that already run bentoo-kernel. Same PVR as ::gentoo on purpose;
# this copy wins by repository priority (bentoo 0, gentoo -1000).

DESCRIPTION="Virtual for Linux kernel sources"
SLOT="0"
KEYWORDS="~alpha ~amd64 ~arm ~arm64 ~hppa ~loong ~m68k ~mips ~ppc ~ppc64 ~riscv ~s390 ~sparc ~x86"
IUSE="firmware"

RDEPEND="
	firmware? ( sys-kernel/linux-firmware )
	|| (
		sys-kernel/gentoo-sources
		sys-kernel/vanilla-sources
		sys-kernel/git-sources
		sys-kernel/mips-sources
		sys-kernel/pf-sources
		sys-kernel/rt-sources
		sys-kernel/zen-sources
		sys-kernel/raspberrypi-sources
		sys-kernel/gentoo-kernel
		sys-kernel/gentoo-kernel-bin
		sys-kernel/vanilla-kernel
		sys-kernel/linux-next
		sys-kernel/asahi-sources
		sys-kernel/gentoo-kernel-modprep
		sys-kernel/bentoo-kernel
	)"
