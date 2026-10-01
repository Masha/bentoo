# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit xdg

# The prebuilt form of app-editors/zeo at the same ${PV}: the same Zed commit, the
# same patch series, the default USE set, compiled for x86-64-v3 by
# zed-patches/scripts/make-bin-release.sh under the versioned configuration in
# zed-patches/release/configroot. PROVENANCE.txt inside the tarball names the
# commit, every patch with its sha256, the USE set and the flags.
EGIT_COMMIT="71456c40f3971ee763e620a513c5fb98390d93e3"

DESCRIPTION="Zeo - the Zed editor, rebranded, with the bentoo patch series (binary)"
HOMEPAGE="https://github.com/zeo-workspace/zeo https://zed.dev"
# ${PF}, not ${P}: the tarball is named after zeo's full version, revision
# included, because a zeo revbump is a different binary and R2 must not serve
# new bytes under a name an older Manifest already pins.
SRC_URI="https://distfiles.obentoo.org/${PF}-amd64.tar.xz"
S="${WORKDIR}/${PF}"

# The Corresponding Source of this binary (GPL-3 section 6) is the Zed tarball
# named by EGIT_COMMIT plus the patches in app-editors/zeo/files/ at this ${PV};
# PROVENANCE.txt carries the exact list.
LICENSE="GPL-3+
	Apache-2.0 Apache-2.0-with-LLVM-exceptions BSD-2 BSD Boost-1.0
	CC0-1.0 CDLA-Permissive-2.0 ISC LGPL-3 MIT MIT-0 MPL-2.0 UoI-NCSA
	Unicode-3.0 ZLIB BZIP2
"
SLOT="0"
KEYWORDS="-* ~amd64"
# Only the dependency half of the adapter flags is honest on a binary: the
# integration patches are compiled in either way, and these decide whether the
# adapters they talk to are pulled in.
IUSE="+claude-agent-acp-plus +claude-agent-acp-tui"
# Never bindist: redistributing this binary is the reason the package exists.
RESTRICT="mirror strip"

# NEEDED is measured on the shipped binary with scanelf. The dlopen()ed
# libraries are invisible to scanelf and are listed from what gpui loads at run
# time: Vulkan, the Wayland client and libX11.
RDEPEND="
	!app-editors/zed
	!app-editors/zed-bin
	!app-editors/zeo
	media-libs/alsa-lib
	dev-libs/glib:2
	x11-libs/libxcb
	x11-libs/libxkbcommon[X]
	media-libs/vulkan-loader
	dev-libs/wayland
	x11-libs/libX11
	|| (
		media-fonts/dejavu
		media-fonts/cantarell
		media-fonts/noto
		media-fonts/ubuntu-font-family
	)
	claude-agent-acp-plus? ( dev-util/claude-agent-acp-plus )
	claude-agent-acp-tui? ( dev-util/claude-agent-acp-tui )
"

QA_PREBUILT="
	usr/bin/zeo
	usr/libexec/zeo-editor
"

pkg_pretend() {
	# Compiled for x86-64-v3. On an older CPU the editor dies with SIGILL at the
	# first AVX2 instruction, which reads as a crash rather than as the wrong
	# package; this turns it into a message. Skipped when building for another
	# machine, where this CPU says nothing.
	[[ ${MERGE_TYPE} == buildonly ]] && return
	[[ ${ROOT:-/} != / ]] && return
	local flag missing=()
	for flag in avx2 fma bmi2 movbe; do
		grep -qw "${flag}" /proc/cpuinfo || missing+=( "${flag}" )
	done
	if [[ ${#missing[@]} -gt 0 ]]; then
		eerror "This binary needs an x86-64-v3 CPU (Haswell / Zen 1 or newer)."
		eerror "Missing: ${missing[*]}"
		eerror "Install app-editors/zeo instead, which compiles for this machine."
		die "CPU below x86-64-v3"
	fi
}

src_install() {
	cp -a usr "${ED}"/ || die
	dodoc PROVENANCE.txt
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "Zeo (binary) installed. Launch with: zeo"

	if use claude-agent-acp-plus; then
		elog ""
		elog "The claude-agent-acp-plus ACP adapter was installed as 'claude-agent-acp-plus'."
		elog "To enable it in Zeo, add to ~/.config/zeo/settings.json:"
		elog ""
		elog "    \"agent_servers\": {"
		elog "        \"Claude Agent Plus\": { \"command\": \"claude-agent-acp-plus\", \"args\": [] }"
		elog "    }"
	fi
}
