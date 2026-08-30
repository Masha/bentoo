# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit autotools eapi9-ver flag-o-matic systemd

DESCRIPTION="Terminal multiplexer"
HOMEPAGE="https://tmux.github.io/"
SRC_URI="https://github.com/tmux/tmux/releases/download/${PV}/${P/_/-}.tar.gz"
S="${WORKDIR}/${P/_/-}"

LICENSE="ISC"
SLOT="0"
KEYWORDS="~alpha ~amd64 ~arm ~arm64 ~hppa ~loong ~m68k ~mips ~ppc ~ppc64 ~riscv ~s390 ~sparc ~x86 ~x64-macos"
IUSE="debug jemalloc selinux sixel systemd utempter vim-syntax"

DEPEND="
	dev-libs/libevent:=
	sys-libs/ncurses:=
	jemalloc? ( dev-libs/jemalloc:= )
	systemd? ( sys-apps/systemd:= )
	utempter? ( sys-libs/libutempter )
	kernel_Darwin? ( dev-libs/libutf8proc:= )
"

BDEPEND="
	virtual/pkgconfig
	app-alternatives/yacc
"

RDEPEND="
	${DEPEND}
	selinux? ( sec-policy/selinux-screen )
	vim-syntax? ( app-vim/vim-tmux )
"

QA_CONFIG_IMPL_DECL_SKIP=(
	# BSD only functions
	strtonum recallocarray
	# missing on musl, tmux has fallback impl which it uses
	b64_ntop
)

DOCS=( CHANGES README )

# BENTOO-DIVERGENCE: PATCHES - ::gentoo's 3.6a carries four patches; this
# carries one.  The flags patch is the same fix rebased onto 3.7's reworked
# Makefile.am (the old hunk no longer applies, the reason for it still holds --
# see the patch header).  The other three are upstream as of 3.7 and are
# deliberately dropped.  Verified against this tarball, not against the
# changelog:
#
#   tmux-3.6a-race-fork.patch  spawn.c already declares path[PATH_MAX], home
#                              and actual_cwd (upstream f58b8d0)
#   tmux-3.6a-pane-color.patch screen-redraw.c already guards the border on
#                              pane_status != PANE_STATUS_BOTTOM (upstream afa05ae)
#   tmux-3.6a-sixel.patch      image-sixel.c already subtracts the offset before
#                              clamping in sixel_scale() (upstream 2e5e9c0)
#
# Re-check on the next bump by running each one with `patch -p1 --dry-run`: a
# hunk that fails because the fix is already there and one that fails because
# the code moved look identical in the output, and only the first is harmless.
PATCHES=(
	"${FILESDIR}"/${PN}-3.7-flags.patch
)

src_prepare() {
	default
	eautoreconf
}

src_configure() {
	# bug 438558
	# 1.7 segfaults when entering copy mode if compiled with -Os
	replace-flags -Os -O2

	local myeconfargs=(
		--sysconfdir="${EPREFIX}"/etc
		$(use_enable debug)
		$(use_enable jemalloc)
		$(use_enable sixel)
		$(use_enable systemd)
		$(use_enable utempter)

		# For now, we only expose this for macOS, because
		# upstream strongly encourage it. I'm not sure it's
		# needed on Linux right now.
		$(use_enable kernel_Darwin utf8proc)
	)

	econf "${myeconfargs[@]}"
}

src_install() {
	default

	einstalldocs

	dodoc example_tmux.conf
	docompress -x /usr/share/doc/${PF}/example_tmux.conf

	if use systemd; then
		systemd_newuserunit "${FILESDIR}"/tmux.service tmux@.service
		systemd_newuserunit "${FILESDIR}"/tmux.socket tmux@.socket
	fi

	# The OpenRC counterpart of the user units above, at the same scope, and
	# NOT behind USE=systemd on purpose: it costs a systemd user nothing, and
	# it is the only way to run a persistent tmux server on a host without
	# systemd.  Started by openrc-user, never by the system init.
	exeinto /etc/user/init.d
	newexe "${FILESDIR}"/tmux.initd tmux
}

pkg_postinst() {
	# https://github.com/tmux/tmux/issues/4711
	if ver_replacing -lt 3.6a ; then
		ewarn "Please restart all running tmux sessions (client+server)."
		ewarn "3.6a has an incompatible protocol change, so it is especially important:"
		ewarn " https://github.com/tmux/tmux/issues/4699#issue-3666479306"
	elif ver_replacing -lt ${PV} ; then
		# https://github.com/tmux/tmux/issues/4699#issue-3666479306
		# > Note that it is very important to restart tmux entirely after upgrading.
		# > This is particularly important with this release because one of the libraries
		# > that tmux uses changed its protocol.
		ewarn "Please restart all running tmux clients+servers after upgrading tmux."
	fi
}
