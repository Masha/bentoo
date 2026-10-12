# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit optfeature xdg

MY_PN="${PN%-bin}"
MY_P="${MY_PN}-${PV}"

DESCRIPTION="Clean-room Photoshop-style image editor in pure Rust (binary package)"
HOMEPAGE="https://github.com/storytold/photocraft"
SRC_URI="https://github.com/storytold/${MY_PN}/releases/download/v${PV}/${MY_P}-linux-x86_64.tar.gz"
S="${WORKDIR}/${MY_P}-linux-x86_64"

# The binary embeds three CJK fonts under the SIL Open Font License.
LICENSE="|| ( Apache-2.0 MIT ) OFL-1.1"
SLOT="0"
KEYWORDS="-* ~amd64"
RESTRICT="strip"

# Both binaries link only glibc; everything below is dlopen()ed at runtime
# (winit, wgpu and rfd), so no tool would derive it. Measured with
# LD_DEBUG=files on 0.7.0, excluding what Mesa and nvidia-drivers pull in
# themselves; libXcursor and libXi come from winit-0.30.13's xdisplay.rs,
# which fails the X11 backend outright when either is missing. wgpu tries
# Vulkan first and falls back to EGL.
RDEPEND="
	dev-libs/wayland
	media-libs/libglvnd
	media-libs/vulkan-loader
	sys-apps/dbus
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/libXcursor
	x11-libs/libXi
	x11-libs/libxkbcommon[X]
"

QA_PREBUILT="usr/bin/${MY_PN} usr/bin/${MY_PN}-cli"

src_install() {
	dobin bin/${MY_PN} bin/${MY_PN}-cli

	insinto /usr/share
	doins -r share/applications share/icons share/metainfo share/mime

	dodoc share/doc/${MY_PN}/README.md
}

pkg_postinst() {
	xdg_pkg_postinst

	# rfd asks org.freedesktop.portal.FileChooser first and runs zenity only
	# when no portal answers.
	optfeature "file dialogs on a session without an XDG desktop portal" gnome-extra/zenity
}
