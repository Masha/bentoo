# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop multilib toolchain-funcs xdg

MY_PN="oriongtk"
MY_ID="com.kagi.OrionGtk"

DESCRIPTION="WebKit-based browser by Kagi, with Chrome and Firefox extension support"
HOMEPAGE="https://orionbrowser.com/ https://kagi.com/orion/"
SRC_URI="
	amd64? (
		https://cdn.kagi.com/downloads/${MY_PN}.${PV}.flatpak
			-> ${P}-amd64.flatpak
	)
	arm64? (
		https://cdn.kagi.com/downloads/${MY_PN}.${PV}.arm.flatpak
			-> ${P}-arm64.flatpak
	)
"
S="${WORKDIR}/${PN}"

LICENSE="all-rights-reserved"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
RESTRICT="bindist mirror splitdebug strip"

QA_PREBUILT="usr/lib*/orion/*"

# Upstream ships these as a Flatpak against org.gnome.Platform, so the payload
# is only the browser itself: WebKit and the Orion libraries are bundled, and
# everything below comes from the system. Two of them are pinned to an ABI
# that ::gentoo no longer carries, hence the -compat packages.
RDEPEND="
	app-crypt/libsecret
	app-text/enchant:2
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/hidapi:0=
	dev-libs/hyphen
	dev-libs/icu-compat:77
	dev-libs/libgcrypt:=
	dev-libs/libgpg-error
	dev-libs/libmanette
	dev-libs/libtasn1:=
	dev-libs/libxml2:=
	dev-libs/libxslt
	dev-libs/openssl:=
	dev-libs/wayland
	gui-libs/gtk:4
	gui-libs/libadwaita:1
	media-libs/fontconfig
	media-libs/freetype:2
	media-libs/graphene
	media-libs/gst-plugins-base:1.0
	media-libs/gstreamer:1.0
	media-libs/harfbuzz:=[icu]
	media-libs/lcms:2
	media-libs/libavif:=
	media-libs/libepoxy
	media-libs/libjpeg-turbo:=
	media-libs/libjxl-compat:0.11
	media-libs/libpng:0=
	media-libs/libwebp:=
	media-libs/mesa
	media-libs/vulkan-loader
	media-libs/woff2
	net-libs/libsoup:3.0
	net-misc/curl
	sys-apps/bubblewrap
	sys-apps/dbus
	sys-apps/xdg-dbus-proxy
	sys-libs/libseccomp
	x11-libs/cairo
	x11-libs/gdk-pixbuf:2
	x11-libs/libX11
	x11-libs/libdrm
	x11-libs/pango
"
BDEPEND="
	dev-lang/perl
	dev-util/ostree
	dev-util/patchelf
	sys-apps/flatpak
"

# Absolute paths baked into the binaries. WebKit resolves its auxiliary
# processes through a compiled-in path and this build has no WEBKIT_EXEC_PATH
# to override it, so the strings have to be rewritten in place. They live in
# .rodata and can only be padded with NULs, never grown -- keep the
# replacements no longer than the originals.
ORION_OLD_EXEC="/app/libexec/webkitgtk-6.0"
ORION_OLD_LOCALE="/app/share/locale"

orion_elfs() {
	local f
	while IFS= read -r -d '' f; do
		[[ $(head -c4 -- "${f}") == $'\x7fELF' ]] && printf '%s\0' "${f}"
	done < <(find "${S}/files" -type f \( -perm /111 -o -name '*.so*' \) -print0)
}

# orion_binpatch <old-path> <new-path>
orion_binpatch() {
	local f
	local -x ORION_FROM=${1} ORION_TO=${2}

	[[ ${#ORION_TO} -le ${#ORION_FROM} ]] ||
		die "'${ORION_TO}' is longer than '${ORION_FROM}', cannot patch in place"

	while IFS= read -r -d '' f; do
		perl -0777 -pi -e '
			BEGIN {
				$from = $ENV{ORION_FROM};
				$to = $ENV{ORION_TO} . ("\0" x (length($from) - length($ENV{ORION_TO})));
			}
			s/\Q$from\E/$to/g;
		' "${f}" || die "failed to rewrite paths in ${f}"
	done < <(orion_elfs)
}

src_unpack() {
	# A .flatpak bundle is an OSTree static delta, not an archive Portage can
	# unpack. Importing it into a scratch repo and checking that out needs
	# neither network nor root, and never touches the system flatpak state.
	ostree --repo="${WORKDIR}/repo" init --mode=bare-user || die
	flatpak build-import-bundle "${WORKDIR}/repo" "${DISTDIR}/${A}" || die

	local ref
	ref=$(ostree --repo="${WORKDIR}/repo" refs) || die
	[[ ${ref} == *${MY_ID}* ]] || die "unexpected ref '${ref}' in ${A}"

	ostree --repo="${WORKDIR}/repo" checkout -U "${ref}" "${S}" || die
}

src_prepare() {
	default

	local instdir="${EPREFIX}/usr/$(get_libdir)/orion"

	# Development leftovers and Flatpak-only metadata.
	rm -rf \
		"${S}/files/bin/app.gdbserver.sh" \
		"${S}/files/bin/unifdef" \
		"${S}/files/bin/unifdefall" \
		"${S}/files/lib/libbacktrace.la" \
		"${S}/files/lib64/cmake" \
		"${S}/files/lib64/pkgconfig" \
		"${S}/files/share/app-info" \
		"${S}/files/share/gir-1.0" || die

	# Flatpak splits libraries across lib and lib64; merge them so the
	# installed tree has a single library directory.
	if [[ -d ${S}/files/lib64 ]]; then
		cp -a "${S}/files/lib64/." "${S}/files/lib/" || die
		rm -rf "${S}/files/lib64" || die
	fi

	mv "${S}/files/libexec/webkitgtk-6.0" "${S}/files/wk" || die
	rmdir "${S}/files/libexec" || die

	orion_binpatch "${ORION_OLD_EXEC}" "${instdir}/wk"
	orion_binpatch "${ORION_OLD_LOCALE}" "${EPREFIX}/usr/share/orion"

	# The bundled libraries are found through this RPATH, which also keeps
	# them from being picked up by anything else on the system. The journal
	# stub is deliberately *not* here: see the wrapper in src_install.
	local f
	while IFS= read -r -d '' f; do
		patchelf --set-rpath "${instdir}/lib" "${f}" || die "patchelf failed on ${f}"
	done < <(orion_elfs)
}

src_compile() {
	# WebKit's release logging calls sd_journal_send() unconditionally, so on
	# a system without systemd the browser would die the first time anything
	# logged. These two entry points are stubbed out; the wrapper decides at
	# startup whether the stub is needed.
	$(tc-getCC) ${CFLAGS} ${LDFLAGS} -shared -fPIC \
		-Wl,-soname,libsystemd.so.0 \
		-Wl,--version-script="${FILESDIR}/libsystemd.map" \
		-o "${WORKDIR}/libsystemd.so.0" \
		"${FILESDIR}/libsystemd-journal-stub.c" || die
}

src_install() {
	local instdir="/usr/$(get_libdir)/orion"

	insinto "${instdir}"
	doins -r "${S}/files/bin" "${S}/files/lib" "${S}/files/wk"

	local f
	while IFS= read -r -d '' f; do
		fperms +x "${instdir}/${f#"${S}/files/"}"
	done < <(orion_elfs)

	exeinto "${instdir}/compat"
	doexe "${WORKDIR}/libsystemd.so.0"

	# Translations go to their own prefix: the payload carries
	# WebKitGTK-6.0.mo, which would collide with net-libs/webkit-gtk.
	if [[ -d ${S}/files/share/locale ]]; then
		insinto /usr/share/orion
		doins -r "${S}/files/share/locale/."
	fi

	local ib
	ib=$(cd "${S}/files" && find lib -type d -name injected-bundle) || die
	[[ -n ${ib} ]] || die "injected bundle directory not found"

	cat > "${T}/orion" <<-EOF || die
		#!/bin/sh
		# WebKit looks for its injected bundle in a compiled-in path that this
		# package cannot keep; this is the only override upstream still honours.
		WEBKIT_INJECTED_BUNDLE_PATH="${EPREFIX}${instdir}/${ib}"
		export WEBKIT_INJECTED_BUNDLE_PATH

		# Reach for the bundled journal stub only when the system has no
		# libsystemd of its own. Putting it on the search path unconditionally
		# would shadow the real library for everything else loaded into this
		# process -- libmount and libappstream ask for symbol versions the stub
		# does not carry, and the browser would fail to start.
		if [ ! -e "${EPREFIX}/usr/$(get_libdir)/libsystemd.so.0" ] &&
		   [ ! -e "${EPREFIX}/lib/libsystemd.so.0" ]
		then
		    LD_LIBRARY_PATH="${EPREFIX}${instdir}/compat\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
		    export LD_LIBRARY_PATH
		fi

		exec "${EPREFIX}${instdir}/bin/${MY_PN}" "\$@"
	EOF
	dobin "${T}/orion"

	sed -e "s/^Exec=.*/Exec=orion %U/" \
		-e "/^Categories=/a MimeType=text\/html;text\/xml;application\/xhtml+xml;x-scheme-handler\/http;x-scheme-handler\/https;" \
		-e "/^Categories=/a StartupWMClass=${MY_PN}" \
		"${S}/export/share/applications/${MY_ID}.desktop" > "${T}/${MY_ID}.desktop" || die
	domenu "${T}/${MY_ID}.desktop"

	local size
	for size in 16 32 64 128 256; do
		newicon -s ${size} \
			"${S}/export/share/icons/hicolor/${size}x${size}/apps/${MY_ID}.png" \
			"${MY_ID}.png"
	done

	insinto /usr/share/metainfo
	doins "${S}/export/share/metainfo/${MY_ID}.metainfo.xml"
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "Orion is a beta release: expect missing features and instability."
	elog "WebKit extensions and data sync are not implemented yet upstream."
	elog
	elog "Browser data lives in ~/.var/app/${MY_ID}, the path the prebuilt"
	elog "binaries were compiled with. An existing Flatpak install of Orion"
	elog "shares that directory, so profiles carry over as they are."
}
