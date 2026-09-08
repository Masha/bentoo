# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

# BENTOO-DIVERGENCE: INHERIT - toolchain-funcs, which ::gentoo's ebuild does not
# need.  src_configure() below uses tc-getCC to ask the compiler where it keeps
# libatomic_asneeded.so, so that libtool can resolve it and stop degrading every
# dlopen plugin to static-only.  Without that fix bochs merges cleanly and then
# dies at startup with "no plugins found" (see the full note in src_configure).
inherit toolchain-funcs

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

	# THE REASON THIS REVISION EXISTS.
	#
	# Without this, bochs installs but cannot start:
	#     >>PANIC<< bx_plugin_ctrl_init() failure: no plugins found
	#
	# GCC 16 announces "-latomic_asneeded" as an implicit link dependency of
	# every C++ link.  That name is not a library: it is a linker script,
	#     INPUT ( AS_NEEDED ( -latomic ) )
	# living in GCC's private directory (/usr/lib/gcc/${CHOST}/${ver}/), which
	# is not part of libtool's sys_lib_search_path.
	#
	# libtool records it in `postdeps` while probing the compiler, then fails to
	# resolve it at link time and warns:
	#     linker path does not have real file for library -latomic_asneeded
	# and QUIETLY falls back to building each dlopen module as static-only.  The
	# .la files come out with dlname='' and only libbx_*.a is installed, so the
	# 53 plugins the build produces are unloadable and PLUGDIR ends up with no
	# .so at all.  Nothing in the build fails, which is why this reaches users.
	#
	# Pointing libtool at GCC's directory keeps the as-needed semantics intact.
	# Deleting the flag from postdeps also produces working .so files, but does
	# so by hiding a real dependency: a package that does use atomics would then
	# link with the symbols unresolved.
	#
	# Not fixable via elibtoolize: that patches the bundled ltmain.sh, not the
	# compiler probing that produced postdeps.  Rebuilding dev-build/libtool
	# does not help either, because this tarball ships a pre-generated configure
	# and ltmain.sh and never consults the system's libtool macros.
	local gcc_libdir
	gcc_libdir=$(dirname "$($(tc-getCC) -print-file-name=libatomic_asneeded.so)") || die
	sed -i "s|^sys_lib_search_path_spec=\"|sys_lib_search_path_spec=\"${gcc_libdir} |" \
		libtool || die
}

src_install() {
	default

	# The .la files are only needed by libtool at install time; the plugins are
	# dlopen'ed by name and load fine without them.
	find "${ED}" -name '*.la' -delete || die
}
