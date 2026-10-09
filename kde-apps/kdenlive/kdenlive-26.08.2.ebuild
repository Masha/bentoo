# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# The one change from ::gentoo: src_configure turns off BUILD_RUN_QMLLINT.
# It carries no BENTOO-DIVERGENCE tag on purpose. ecm.eclass already exports
# src_configure, so DEFINED_PHASES matches ::gentoo's, and gentoo-parity.sh
# compares metadata, not phase bodies: any axis named here would be reported
# as a stale tag (measured).
#
# Upstream defaults that option ON, which wires all_qmllint into the kdenlive
# target, so any qmllint "Error:" fails the build. Qt 6.12 promoted
# confusing-expression-statement to an error, and ClipThumbs.qml trips it 3x
# with valid JS (a switch's completion value used as a binding). Upstream's fix,
# 2a40ef90 ("Fix confusing-expression-statement qml error with Qt 6.12"), only
# rewrites those values as `return` -- no runtime change -- and lives on master
# alone: release/26.08 still carries the old code, and the patch does not apply
# here (master renamed parentTrack.trackThumbsFormat to thumbRow.thumbsFormat).
#
# The lint is a developer gate, not a property of the installed program, so
# switching it off is the fix rather than a workaround. Remove this copy once
# ::gentoo carries a kdenlive containing 2a40ef90 (expected: 26.12.0).

ECM_DESIGNERPLUGIN="true"
ECM_HANDBOOK="optional"
ECM_QTHELP="true"
ECM_TEST="true"
KFMIN=6.27.0
QTMIN=6.11.2
inherit ecm gear.kde.org optfeature xdg

DESCRIPTION="Non-linear video editing suite by KDE"
HOMEPAGE="https://kdenlive.org/en/"

LICENSE="GPL-3"
SLOT="6"
KEYWORDS="~amd64 ~arm64 ~loong ~ppc64 ~riscv ~x86"
IUSE="gles2-only semantic-desktop"

RESTRICT="test" # segfaults, bug 684132

DEPEND="
	>=dev-qt/qtbase-${QTMIN}:6[concurrent,dbus,gles2-only=,gui,network,widgets,xml]
	>=dev-qt/qtdeclarative-${QTMIN}:6[widgets]
	>=dev-qt/qtmultimedia-${QTMIN}:6
	>=dev-qt/qtnetworkauth-${QTMIN}:6
	>=dev-qt/qtsvg-${QTMIN}:6
	>=gui-libs/kddockwidgets-2.4.0:=
	>=kde-frameworks/karchive-${KFMIN}:6
	>=kde-frameworks/kbookmarks-${KFMIN}:6
	>=kde-frameworks/kcodecs-${KFMIN}:6
	>=kde-frameworks/kcompletion-${KFMIN}:6
	>=kde-frameworks/kconfig-${KFMIN}:6
	>=kde-frameworks/kconfigwidgets-${KFMIN}:6
	>=kde-frameworks/kcoreaddons-${KFMIN}:6
	>=kde-frameworks/kcrash-${KFMIN}:6
	>=kde-frameworks/kdbusaddons-${KFMIN}:6
	>=kde-frameworks/kfilemetadata-${KFMIN}:6
	>=kde-frameworks/kguiaddons-${KFMIN}:6
	>=kde-frameworks/ki18n-${KFMIN}:6
	>=kde-frameworks/kiconthemes-${KFMIN}:6
	>=kde-frameworks/kio-${KFMIN}:6
	>=kde-frameworks/kitemviews-${KFMIN}:6
	>=kde-frameworks/kjobwidgets-${KFMIN}:6
	>=kde-frameworks/knewstuff-${KFMIN}:6
	>=kde-frameworks/knotifications-${KFMIN}:6
	>=kde-frameworks/knotifyconfig-${KFMIN}:6
	>=kde-frameworks/kservice-${KFMIN}:6
	>=kde-frameworks/ktextwidgets-${KFMIN}:6
	>=kde-frameworks/kwidgetsaddons-${KFMIN}:6
	>=kde-frameworks/kxmlgui-${KFMIN}:6
	>=kde-frameworks/purpose-${KFMIN}:6
	>=kde-frameworks/solid-${KFMIN}:6
	media-video/ffmpeg:=[encode(+),libass,sdl,X]
	>=media-libs/mlt-7.38.0:=[ffmpeg,frei0r,qt6,sdl,xml]
	>=media-libs/opentimelineio-0.18.0:=
"
RDEPEND="${DEPEND}
	>=kde-frameworks/qqc2-desktop-style-${KFMIN}:6
	media-video/mediainfo
"
BDEPEND="sys-devel/gettext"
DEPEND+=" virtual/os-headers"

src_configure() {
	local mycmakeargs=(
		-DBUILD_RUN_QMLLINT=OFF
	)
	ecm_src_configure
}

pkg_postinst() {
	xdg_pkg_postinst
	optfeature "VP8 and VP9 codec support" "media-video/ffmpeg[vpx]"
}
