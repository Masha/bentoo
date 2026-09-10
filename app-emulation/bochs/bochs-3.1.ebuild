# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

DESCRIPTION="LGPL-ed pc emulator"
HOMEPAGE="http://bochs.sourceforge.io/"
MY_P="REL_$(ver_cut 1)_$(ver_cut 2)_FINAL"
SRC_URI="https://github.com/bochs-emu/Bochs/archive/refs/tags/${MY_P}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/Bochs-${MY_P}/bochs"

LICENSE="LGPL-2.1"
SLOT="0"
KEYWORDS="~alpha ~amd64 ~ppc ~sparc ~x86"

IUSE="3dnow avx debugger doc gdb ncurses readline sdl +smp vnc X +x86-64"
REQUIRED_USE="
	avx? ( x86-64 )
	gdb? ( !debugger !smp )
	debugger? ( !gdb )
"

RDEPEND="
	ncurses? ( sys-libs/ncurses:= )
	readline? ( sys-libs/readline:= )
	sdl? ( media-libs/libsdl )
	X? (
		x11-libs/libICE
		x11-libs/libSM
		x11-libs/libX11
		x11-libs/libXpm
	)
"
DEPEND="${RDEPEND}
	X? ( x11-base/xorg-proto )
"
BDEPEND="
	>=app-text/opensp-1.5
	doc? ( app-text/docbook-sgml-utils )
"

src_prepare() {
	default

	sed -i "s:^docdir.*:docdir = ${EPREFIX}/usr/share/doc/${PF}:" \
		Makefile.in || die
	sed -i 's:| $(GZIP_BIN) -c >  $(DESTDIR)$(man1dir)/$$i.1.gz:> $(DESTDIR)$(man1dir)/$$i.1:' Makefile.in || die
	sed -i 's:$$i.1.gz:$$i.1:' Makefile.in || die
	sed -i 's:| $(GZIP_BIN) -c >  $(DESTDIR)$(man5dir)/$$i.5.gz:> $(DESTDIR)$(man5dir)/$$i.5:' Makefile.in || die
	sed -i 's:$$i.5.gz:$$i.5:' Makefile.in || die
}

src_configure() {
	econf \
		--enable-all-optimizations \
		--enable-idle-hack \
		--enable-cdrom \
		--enable-clgd54xx \
		--enable-cpu-level=6 \
		--enable-e1000 \
		--enable-gameport \
		--enable-iodebug \
		--enable-monitor-mwait \
		--enable-ne2000 \
		--enable-plugins \
		--enable-pci \
		--enable-pnic \
		--enable-raw-serial \
		--enable-sb16=linux \
		--enable-usb \
		--enable-usb-ohci \
		--enable-usb-xhci \
		--prefix=/usr \
		--with-nogui \
		--without-wx \
		$(use_enable 3dnow) \
		$(use_enable avx) \
		$(use_enable avx evex) \
		$(use_enable debugger) \
		$(use_enable doc docbook) \
		$(use_enable gdb gdb-stub) \
		$(use_enable readline) \
		$(use_enable smp) \
		$(use_enable x86-64) \
		$(use_with ncurses term) \
		$(use_with sdl) \
		$(use_with vnc rfb) \
		$(use_with X x) \
		$(use_with X x11)

	# BENTOO-DIVERGENCE: src_configure - THE REASON THIS REVISION EXISTS.
	#
	# Without this, bochs merges cleanly and then cannot start at all:
	#     >>PANIC<< bx_plugin_ctrl_init() failure: no plugins found
	#
	# GCC 16 reports "-latomic_asneeded" among the implicit dependencies of any
	# C++ link.  That name is not a library: it is a linker script,
	#     INPUT ( AS_NEEDED ( -latomic ) )
	# which is how GCC links libatomic only when something needs it.
	#
	# libtool probes the compiler, records the flag in `postdeps`, and then
	# cannot resolve it as a library.  It warns
	#     linker path does not have real file for library -latomic_asneeded
	# and QUIETLY falls back to a static-only build of every dlopen module: the
	# .la files come out with dlname='' and only libbx_*.a is installed.  All 53
	# plugins become unloadable, and nothing in the build reports an error --
	# which is why this reaches users instead of the build log.
	#
	# Dropping the flag from postdeps only changes what libtool BELIEVES the
	# compiler links implicitly.  The link itself is still driven by g++, which
	# keeps applying its own implicit dependencies, so the as-needed behaviour is
	# preserved: the resulting modules carry no unresolved __atomic/__sync
	# symbols and no libatomic in DT_NEEDED (verified on 3.0 with GCC 16.2.0).
	#
	# Adding GCC's directory to libtool's sys_lib_search_path does NOT help --
	# measured.  That directory is already in the search path; libtool's problem
	# is the linker script itself, not where it lives.
	#
	# Neither elibtoolize nor rebuilding dev-build/libtool fixes this: the first
	# patches the bundled ltmain.sh rather than the compiler probing that filled
	# postdeps, and the second is irrelevant because this tarball ships a
	# pre-generated configure and never reads the system libtool macros.
	#
	# The grep is the guard, not decoration: `sed -i` exits 0 when its pattern
	# matches nothing, so without it a GCC that stops emitting the flag would
	# leave this revision silently doing nothing at all.
	grep -q -- '-latomic_asneeded' libtool ||
		die "libtool no longer records -latomic_asneeded; re-check whether this workaround is still needed"
	sed -i 's/-latomic_asneeded//g' libtool || die
}

src_install() {
	default

	# The .la files are only needed by libtool at install time; the plugins are
	# dlopen'ed by name and load fine without them.
	find "${ED}" -name '*.la' -delete || die
}
