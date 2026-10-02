# Copyright 2020-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

KERNEL_IUSE_GENERIC_UKI=1

inherit kernel-build toolchain-funcs

# A release candidate of the NEXT series, ahead of ::gentoo, which never ships
# -rc dist-kernels.  It is package.mask'ed: 7.3_rc5 sorts above 7.2.x, so without
# the mask every ~arch user would be moved onto a release candidate.
#
# The source is the previous release plus Linus's cumulative -rc diff from
# git.kernel.org.  kernel.org publishes no tarball or patch for an -rc on the
# CDN, so sha256sums.asc has no entry to verify it against.  The distfile name
# is the one sys-kernel/git-sources uses, so both share one download and one
# checksum.  Everything verify-sig contributed goes with it:
# BENTOO-DIVERGENCE: INHERIT - no verify-sig: nothing signed covers an -rc diff.
# BENTOO-DIVERGENCE: IUSE - no verify-sig flag, for the same reason.
# BENTOO-DIVERGENCE: BDEPEND - no kernel.org OpenPGP keys, for the same reason.
# BENTOO-DIVERGENCE: DEFINED_PHASES - no src_unpack: it only ran verify-sig.
#
# PATCH_PV is the series (7.3), so the EXTRAVERSION computed below is -rc5 and
# the release string becomes 7.3.0-rc5, which kernel-build checks against PV in
# src_configure.
#
# PATCHSET and CONFIG_VER are the ones the 7.2 dist-kernel ships.  All 9
# patches apply to the 7.3-rc5 tree with zero rejects.  The Fedora 7.2 config
# leaves 83 symbols undecided on this tree; most are new drivers that olddefconfig
# turns off, which is the price of running ahead of Fedora's 7.3 config.
BASE_P=linux-$(ver_cut 1).$(( $(ver_cut 2) - 1 ))
PATCH_PV=$(ver_cut 1-2)
RC_PATCH=patch-${PV/_/-}.patch
PATCHSET=linux-gentoo-patches-7.1.9
# https://koji.fedoraproject.org/koji/packageinfo?packageID=8
# forked to git.gentoo.org:fork/fedora/kernel
CONFIG_VER=7.2.5-gentoo
GENTOO_CONFIG_P=gentoo-kernel-config-g19
# Debian kconfig commit from:
# https://salsa.debian.org/kernel-team/linux/-/tree/debian/latest/debian/
DEBIAN_COMMIT=31e70f1f469ef1ce4c910df1d12b7de09da561d1

DESCRIPTION="Linux kernel built with Gentoo patches"
HOMEPAGE="
	https://wiki.gentoo.org/wiki/Project:Distribution_Kernel
	https://www.kernel.org/
"
SRC_URI+="
	https://cdn.kernel.org/pub/linux/kernel/v$(ver_cut 1).x/${BASE_P}.tar.xz
	https://git.kernel.org/torvalds/p/v${PV/_/-}/${BASE_P#linux-} -> ${RC_PATCH}
	https://distfiles.gentoo.org/pub/proj/dist-kernel/patchsets/7.1/${PATCHSET}.tar.xz
	https://gitweb.gentoo.org/proj/dist-kernel/gentoo-kernel-config.git/snapshot/${GENTOO_CONFIG_P}.tar.bz2
	https://distfiles.gentoo.org/pub/proj/dist-kernel/config/fedora-kernel-config-${CONFIG_VER}.tar.xz
	https://salsa.debian.org/kernel-team/linux/-/archive/${DEBIAN_COMMIT}/linux-${DEBIAN_COMMIT}.tar.bz2
"
S=${WORKDIR}/${BASE_P}

KEYWORDS="~alpha ~amd64 ~arm ~arm64 ~hppa ~loong ~m68k ~mips ~ppc ~ppc64 ~riscv ~s390 ~sparc ~x86"
IUSE="debug hardened"
REQUIRED_USE="
	hppa? ( savedconfig )
	mips? ( savedconfig )
"

BDEPEND="
	debug? ( dev-util/pahole )
"
PDEPEND="
	>=virtual/dist-kernel-${PV}
"

QA_FLAGS_IGNORED="
	usr/src/linux-.*/scripts/gcc-plugins/.*.so
	usr/src/linux-.*/vmlinux
	usr/src/linux-.*/arch/powerpc/kernel/vdso.*/vdso.*.so.dbg
"

src_prepare() {
	local patch
	eapply "${DISTDIR}/${RC_PATCH}"
	eapply "${WORKDIR}/${PATCHSET}"

	default

	# add Gentoo patchset version
	local extraversion=${PV#${PATCH_PV}}
	sed -i -e "s:^\(EXTRAVERSION =\).*:\1 ${extraversion/_/-}:" Makefile || die

	local biendian=false

	# prepare the default config
	case ${ARCH} in
		hppa | mips)
			> .config || die
		;;
		alpha)
			cp "${WORKDIR}/linux-${DEBIAN_COMMIT}/debian/config/config" .config || die
			merge_configs+=(
				"${WORKDIR}/linux-${DEBIAN_COMMIT}/debian/config/alpha/config" \
				"${WORKDIR}/linux-${DEBIAN_COMMIT}/debian/config/alpha/config.alpha-smp"
			)
			;;
		amd64)
			cp "${WORKDIR}/fedora-kernel-config-${CONFIG_VER}/kernel-x86_64-fedora.config" .config || die
			;;
		arm)
			cp "${WORKDIR}/linux-${DEBIAN_COMMIT}/debian/config/config" .config || die
			merge_configs+=(
				"${WORKDIR}/linux-${DEBIAN_COMMIT}/debian/config/armhf/config" \
				"${WORKDIR}/linux-${DEBIAN_COMMIT}/debian/config/armhf/config.armmp-lpae"
			)
			;;
		arm64)
			cp "${WORKDIR}/fedora-kernel-config-${CONFIG_VER}/kernel-aarch64-fedora.config" .config || die
			biendian=true
			;;
		loong)
			cp "${WORKDIR}/linux-${DEBIAN_COMMIT}/debian/config/config" .config || die
			merge_configs+=(
				"${WORKDIR}/linux-${DEBIAN_COMMIT}/debian/config/loong64/config"
			)
			;;
		m68k)
			cp "${WORKDIR}/linux-${DEBIAN_COMMIT}/debian/config/config" .config || die
			merge_configs+=(
				"${WORKDIR}/linux-${DEBIAN_COMMIT}/debian/config/m68k/config"
			)
			;;
		ppc)
			cp "${WORKDIR}/linux-${DEBIAN_COMMIT}/debian/config/config" .config || die
			merge_configs+=(
				"${WORKDIR}/linux-${DEBIAN_COMMIT}/debian/config/powerpc/config.powerpc"
			)
			;;
		ppc64)
			cp "${WORKDIR}/fedora-kernel-config-${CONFIG_VER}/kernel-ppc64le-fedora.config" .config || die
			biendian=true
			;;
		riscv)
			cp "${WORKDIR}/fedora-kernel-config-${CONFIG_VER}/kernel-riscv64-fedora.config" .config || die
			;;
		s390)
			cp "${WORKDIR}/fedora-kernel-config-${CONFIG_VER}/kernel-s390x-fedora.config" .config || die
			;;
		sparc)
			cp "${WORKDIR}/linux-${DEBIAN_COMMIT}/debian/config/config" .config || die
			merge_configs+=(
				"${WORKDIR}/linux-${DEBIAN_COMMIT}/debian/config/sparc64/config.sparc64" \
				"${WORKDIR}/linux-${DEBIAN_COMMIT}/debian/config/sparc64/config.sparc64-smp"
			)
			;;
		x86)
			cp "${WORKDIR}/fedora-kernel-config-${CONFIG_VER}/kernel-i686-fedora.config" .config || die
			;;
		*)
			die "Unsupported arch ${ARCH}"
			;;
	esac

	local myversion="-gentoo-dist"
	use hardened && myversion+="-hardened"
	echo "CONFIG_LOCALVERSION=\"${myversion}\"" > "${T}"/version.config || die
	local dist_conf_path="${WORKDIR}/${GENTOO_CONFIG_P}"

	local merge_configs=(
		"${T}"/version.config
		"${dist_conf_path}"/base.config
		"${dist_conf_path}"/6.12+.config
	)
	use debug || merge_configs+=(
		"${dist_conf_path}"/no-debug.config
	)
	if use hardened; then
		merge_configs+=( "${dist_conf_path}"/hardened-base.config )

		tc-is-gcc && merge_configs+=( "${dist_conf_path}"/hardened-gcc-plugins.config )

		if [[ -f "${dist_conf_path}/hardened-${ARCH}.config" ]]; then
			merge_configs+=( "${dist_conf_path}/hardened-${ARCH}.config" )
		fi
	fi

	# this covers ppc64 and aarch64_be only for now
	if [[ ${biendian} == true && $(tc-endian) == big ]]; then
		merge_configs+=( "${dist_conf_path}/big-endian.config" )
	fi

	use secureboot && merge_configs+=(
		"${dist_conf_path}/secureboot.config"
		"${dist_conf_path}/zboot.config"
	)

	kernel-build_merge_configs "${merge_configs[@]}"
}
