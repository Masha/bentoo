# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit toolchain-funcs

# The guest kernel is pinned by the Kata release, not chosen here: the kernel
# version comes from versions.yaml (assets.kernel.version) and the suffix from
# tools/packaging/kernel/kata_config_version, which Kata raises whenever the
# config fragments change on the same kernel. Bump all three together.
KATA_PV="4.2.0"
KV="${PV%_p*}"
KATA_CONFIG_VERSION="${PV##*_p}"

DESCRIPTION="Linux kernel for Kata Containers guest VMs, built from Kata's config fragments"
HOMEPAGE="https://katacontainers.io/ https://github.com/kata-containers/kata-containers"
SRC_URI="
	https://cdn.kernel.org/pub/linux/kernel/v${KV%%.*}.x/linux-${KV}.tar.xz
	https://github.com/kata-containers/kata-containers/archive/refs/tags/${KATA_PV}.tar.gz
		-> kata-containers-${KATA_PV}.tar.gz
"
S="${WORKDIR}/linux-${KV}"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
# The kernel is never run on the build host; there is nothing to test here.
RESTRICT="test"

BDEPEND="
	app-alternatives/bc
	app-alternatives/cpio
	dev-lang/perl
	sys-devel/bison
	sys-devel/flex
	virtual/libelf
"

# The product is a guest kernel image, not code linked on this host.
QA_PREBUILT="usr/share/kata-containers/*"

src_unpack() {
	unpack "linux-${KV}.tar.xz"
	# Only the kernel packaging bits are needed from the Kata tree.
	tar -xzf "${DISTDIR}/kata-containers-${KATA_PV}.tar.gz" -C "${WORKDIR}" \
		"kata-containers-${KATA_PV}/tools/packaging/kernel" || die
}

src_prepare() {
	KATA_KDIR="${WORKDIR}/kata-containers-${KATA_PV}/tools/packaging/kernel"

	local have_cv
	have_cv=$(<"${KATA_KDIR}/kata_config_version") || die
	[[ ${have_cv} == "${KATA_CONFIG_VERSION}" ]] ||
		die "PV says kata_config_version ${KATA_CONFIG_VERSION}, Kata ${KATA_PV} ships ${have_cv}"

	eapply "${KATA_KDIR}"/patches/${KV%.*}.x/*.patch
	default
}

# Not tc-arch-kernel: it answers "x86", where CONFIG_64BIT is a prompt that the
# allnoconfig pass of merge_config.sh -n turns off, producing an i386 kernel.
# With "x86_64" the option has no prompt, which is what build-kernel.sh uses.
kernel_arch() {
	case ${ARCH} in
		amd64) echo x86_64 ;;
		arm64) echo arm64 ;;
		*) die "unsupported ARCH: ${ARCH}" ;;
	esac
}

kmake() {
	emake ARCH="$(kernel_arch)" \
		CC="$(tc-getCC)" HOSTCC="$(tc-getBUILD_CC)" \
		LD="$(tc-getLD)" AR="$(tc-getAR)" NM="$(tc-getNM)" \
		OBJCOPY="$(tc-getOBJCOPY)" STRIP="$(tc-getSTRIP)" \
		KBUILD_BUILD_USER=kata KBUILD_BUILD_HOST=bentoo \
		"$@"
}

src_configure() {
	local karch frag_arch
	karch=$(kernel_arch)
	frag_arch=${karch}

	local frags="${KATA_KDIR}/configs/fragments"
	# Same selection as build-kernel.sh: every common fragment except those
	# tagged "!<arch>" or "!confidential", then every arch fragment.
	local -a configs
	mapfile -t configs < <(grep -L -e "!${frag_arch}" -e "!confidential" "${frags}"/common/*.conf)
	configs+=( "${frags}/${frag_arch}"/*.conf )

	local results
	results=$(ARCH=${karch} CC="$(tc-getCC)" HOSTCC="$(tc-getBUILD_CC)" \
		KCONFIG_CONFIG=.config \
		scripts/kconfig/merge_config.sh -r -n "${configs[@]}") ||
		die "merge_config.sh failed"

	# build-kernel.sh fails the build when a requested option is dropped, minus
	# the options its whitelist knows to vanish on newer kernels. Keep that
	# guard: a silently dropped option is a guest that boots without a feature.
	local missing
	missing=$(grep "not in final" <<<"${results}" |
		grep -v -f "${frags}/whitelist.conf")
	if [[ -n ${missing} ]]; then
		eerror "${missing}"
		die "Kata config fragments request options missing from the final .config"
	fi

	kmake olddefconfig

	# Both supported guests are 64-bit; anything else is a config accident
	# that still boots on nothing Kata runs.
	grep -qx "CONFIG_64BIT=y" .config || die "guest kernel config is not 64-bit"
}

src_compile() {
	case $(kernel_arch) in
		x86_64) kmake vmlinux bzImage ;;
		arm64) kmake vmlinux Image Image.gz ;;
	esac
}

src_install() {
	local karch suffix img
	karch=$(kernel_arch)
	suffix="${KV}-${KATA_CONFIG_VERSION}"

	insinto /usr/share/kata-containers
	# The hypervisors load these images directly; keep them as Kbuild left them.
	dostrip -x /usr/share/kata-containers
	case ${karch} in
		x86_64)
			newins arch/x86/boot/bzImage "vmlinuz-${suffix}"
			newins vmlinux "vmlinux-${suffix}"
			;;
		arm64)
			newins arch/arm64/boot/Image.gz "vmlinuz-${suffix}"
			# On arm64 the uncompressed boot image, not the ELF, is what the
			# hypervisors load as "vmlinux".
			newins arch/arm64/boot/Image "vmlinux-${suffix}"
			;;
	esac
	newins .config "config-${suffix}"
	newins System.map "System.map-${suffix}"

	dosym "vmlinuz-${suffix}" /usr/share/kata-containers/vmlinuz.container
	dosym "vmlinux-${suffix}" /usr/share/kata-containers/vmlinux.container
}
