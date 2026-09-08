# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

ECM_HANDBOOK="optional"
ECM_TEST="forceoptional"
KFMIN=6.26.0
QTMIN=6.11.2
inherit ecm plasma.kde.org xdg

DESCRIPTION="Screenshot capture utility"
HOMEPAGE="https://apps.kde.org/spectacle/"

LICENSE="LGPL-2+ handbook? ( FDL-1.3 )"
SLOT="6"
KEYWORDS="~amd64 ~arm64 ~ppc64 ~riscv ~x86"
IUSE="share"

# slot op: Uses Qt::GuiPrivate for qtx11extras_p.h
COMMON_DEPEND="
	app-text/tesseract:=
	dev-libs/wayland
	>=dev-qt/qtbase-${QTMIN}:6=[concurrent,dbus,gui,wayland,widgets,X]
	>=dev-qt/qtdeclarative-${QTMIN}:6
	>=dev-qt/qtmultimedia-${QTMIN}:6[qml]
	>=kde-frameworks/kconfig-${KFMIN}:6
	>=kde-frameworks/kconfigwidgets-${KFMIN}:6
	>=kde-frameworks/kcoreaddons-${KFMIN}:6
	>=kde-frameworks/kcrash-${KFMIN}:6
	>=kde-frameworks/kdbusaddons-${KFMIN}:6
	>=kde-frameworks/kglobalaccel-${KFMIN}:6
	>=kde-frameworks/kguiaddons-${KFMIN}:6
	>=kde-frameworks/ki18n-${KFMIN}:6
	>=kde-frameworks/kio-${KFMIN}:6
	>=kde-frameworks/kirigami-${KFMIN}:6
	>=kde-frameworks/knotifications-${KFMIN}:6
	>=kde-frameworks/kservice-${KFMIN}:6
	>=kde-frameworks/kstatusnotifieritem-${KFMIN}:6
	>=kde-frameworks/kwidgetsaddons-${KFMIN}:6
	>=kde-frameworks/kwindowsystem-${KFMIN}:6[X]
	>=kde-frameworks/kxmlgui-${KFMIN}:6
	>=kde-frameworks/prison-${KFMIN}:6
	>=kde-plasma/kpipewire-${KDE_CATV}:6
	>=kde-plasma/layer-shell-qt-${KDE_CATV}:6
	>=media-libs/kquickimageeditor-0.6.0:6
	media-libs/opencv:=
	x11-libs/libxcb
	x11-libs/libXrandr
	x11-libs/xcb-util
	x11-libs/xcb-util-cursor
	x11-libs/xcb-util-image
	share? ( >=kde-frameworks/purpose-${KFMIN}:6 )
"
DEPEND="${COMMON_DEPEND}
	>=dev-libs/plasma-wayland-protocols-1.19.0
"
RDEPEND="${COMMON_DEPEND}
	>=dev-qt/qtimageformats-${QTMIN}:6
	>=dev-qt/qtsvg-${QTMIN}:6
	>=kde-frameworks/kimageformats-${KFMIN}:6
"
BDEPEND="
	>=dev-qt/qtbase-${QTMIN}:6[wayland]
	dev-util/wayland-scanner
	virtual/pkgconfig
"

# BENTOO-DIVERGENCE: PATCHES - this overlay ships media-libs/opencv-5.0.0, and
# upstream asks CMake for "OpenCV 4.7" explicitly. OpenCV 5's config rejects
# that request on a major version mismatch, so src_configure dies before a
# single object is compiled -- ::gentoo does not hit this because it still
# ships 4.x. Everything else here is byte-identical to ::gentoo's -r1, and the
# revision is matched deliberately: on a tie Portage picks this repo
# (priority 0) over ::gentoo (priority -1000). Drop this once ::gentoo carries
# an OpenCV 5 fix of its own.
#
# Deliberately ${PN}, not ${P}: this patch has been byte-identical since 6.7.1
# and a version in its name only means every bump must rename the file by hand.
# 6.7.4 shipped without that rename and would die in src_prepare.
PATCHES=( "${FILESDIR}/${PN}-opencv5.patch" )

src_configure() {
	local mycmakeargs=(
		$(cmake_use_find_package share KF6Purpose)
	)
	ecm_src_configure
}
