# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit meson xdg

DESCRIPTION="Display and control your Android device"
HOMEPAGE="https://github.com/Genymobile/scrcpy"
# Source code and server part on Android device
SRC_URI="
	https://github.com/Genymobile/${PN}/archive/v${PV}.tar.gz -> ${P}.tar.gz
	https://github.com/Genymobile/${PN}/releases/download/v${PV}/${PN}-server-v${PV}
"

LICENSE="Apache-2.0"
SLOT="0"
# BENTOO-DIVERGENCE: KEYWORDS - ~arm64, which ::gentoo lacks. The client is
# plain C over SDL3/FFmpeg/libusb and the server is an arch-independent dex
# blob that runs on the device, so nothing ties the package to x86.
KEYWORDS="~amd64 ~arm64 ~ppc64 ~x86"
# BENTOO-DIVERGENCE: IUSE - upstream 5.0, not in ::gentoo yet. 5.0 added
# VA-API hardware decoding (meson -Dvaapi); usb and v4l2 were always meson
# options that ::gentoo builds unconditionally. All three default on, which
# matches upstream's own defaults.
IUSE="X +usb +v4l +vaapi wayland"

# BENTOO-DIVERGENCE: DEPEND - upstream 5.0, not in ::gentoo yet. 5.0 requires
# libavformat >= 60.3 (FFmpeg 6), and its VA-API interop maps frames through
# FFmpeg's DRM hwcontext, which needs the libdrm headers at build time and an
# FFmpeg built with drm and vaapi.
DEPEND="
	media-libs/libsdl3[X?,wayland?]
	>=media-video/ffmpeg-6:=
	usb? ( virtual/libusb:1 )
	vaapi? (
		media-video/ffmpeg[drm,vaapi]
		x11-libs/libdrm
	)
"
# Manual install for ppc64 until bug #723528 is fixed
# BENTOO-DIVERGENCE: RDEPEND - upstream 5.0, not in ::gentoo yet; inherits
# the DEPEND changes above.
RDEPEND="
	${DEPEND}
	!ppc64? ( dev-util/android-tools )
"

DOCS=( {FAQ,README}.md doc/. )

src_prepare() {
	default
	rm doc/{build,develop,macos,windows}.md || die
}

src_configure() {
	local emesonargs=(
		-Dprebuilt_server="${DISTDIR}/${PN}-server-v${PV}"
		$(meson_use usb)
		$(meson_use v4l v4l2)
		$(meson_use vaapi)
	)
	meson_src_configure
}

pkg_postinst() {
	xdg_pkg_postinst

	if has_version media-video/pipewire; then
		ewarn "On pipewire systems scrcpy might not start due to a problem with libsdl2."
		ewarn "If that is the case for you start the program as follows:"
		ewarn "    $ SDL_AUDIODRIVER=pipewire scrcpy [...]"
		ewarn "For more information see https://github.com/Genymobile/scrcpy/issues/3864"
	fi
}
