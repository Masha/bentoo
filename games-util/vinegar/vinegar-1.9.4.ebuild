# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module toolchain-funcs xdg

DESCRIPTION="Open-source, configurable, fast bootstrapper for running Roblox Studio on Linux"
HOMEPAGE="https://vinegarhq.org https://github.com/vinegarhq/vinegar"
# The release tarball ships vendor/, so no separate Go dependency tarball.
SRC_URI="https://github.com/vinegarhq/vinegar/releases/download/v${PV}/${PN}-v${PV}.tar.xz"
S="${WORKDIR}/${PN}-v${PV}"

LICENSE="GPL-3 BSD-2"
# Dependent (vendored, statically linked) Go module licenses
LICENSE+=" Apache-2.0 BSD GPL-3 LGPL-2.1 MIT"
SLOT="0"
# Roblox Studio only exists as a Windows x86_64 binary run under Wine, so an
# arm64 build would install a launcher with nothing it can launch.
KEYWORDS="~amd64"

# GTK4/libadwaita are not linked: puregotk dlopen()s them at runtime, so the
# compiler never sees them and only RDEPEND keeps them on the system.
# hwdata: without a local pci.ids, pcidb downloads it on every start.
RDEPEND="
	dev-libs/glib:2
	gui-libs/gtk:4
	>=gui-libs/libadwaita-1.6:1
	media-libs/graphene
	media-libs/vulkan-loader
	sys-apps/hwdata
	x11-libs/cairo
	x11-libs/gdk-pixbuf:2
	x11-libs/pango
"
DEPEND="dev-util/vulkan-headers"
BDEPEND="
	>=dev-lang/go-1.26
	dev-libs/glib:2
	sys-devel/gettext
	virtual/pkgconfig
"

src_compile() {
	# Upstream's rule for the Vulkan layer drops CXXFLAGS and LDFLAGS.
	$(tc-getCXX) ${CXXFLAGS} ${LDFLAGS} -shared -fPIC \
		-Wl,-soname,libVkLayer_VINEGAR_VinegarLayer.so \
		$($(tc-getPKG_CONFIG) --cflags vulkan) \
		layer/vinegar_layer.cpp -o layer/libVkLayer_VINEGAR_VinegarLayer.so || die

	# Drop upstream's -s -w: Portage strips and splits debug info itself.
	emake GO_LDFLAGS="-X main.LocaleDir=${EPREFIX}/usr/share/locale" vinegar
}

src_test() {
	ego test ./...
}

src_install() {
	# The Vulkan layer manifest names its library without a path, so the
	# loader resolves it through the linker search path. Upstream's /usr/lib
	# is not on that path on a multilib amd64 system.
	emake DESTDIR="${D}" PREFIX="${EPREFIX}/usr" \
		LIBPREFIX="${EPREFIX}/usr/$(get_libdir)" \
		GO_LDFLAGS="-X main.LocaleDir=${EPREFIX}/usr/share/locale" \
		install
	einstalldocs
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "By default Vinegar downloads its own Wine build (Kombucha) and DXVK"
	elog "into the user's data directory on first run. To use a system Wine"
	elog "instead, set 'wineroot' under [studio] in"
	elog "~/.config/vinegar/config.toml to an absolute path such as"
	elog "${EROOT}/usr/lib/wine-staging-<version>."
}
