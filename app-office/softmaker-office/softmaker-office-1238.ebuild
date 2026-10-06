# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop xdg

DESCRIPTION="Commercial Microsoft Office-compatible office suite"
HOMEPAGE="https://www.softmaker.com/en/softmaker-office"
SRC_URI="https://www.softmaker.net/down/${PN}-2024-${PV}-amd64.tgz"
S="${WORKDIR}/${P}"

# Proprietary; upstream ships no EULA text in the archive.
LICENSE="all-rights-reserved"
SLOT="0"
KEYWORDS="-* ~amd64"
IUSE="cups"
RESTRICT="bindist mirror strip"

# Gentoo L10N code, or "code:suffix" when upstream's *_<suffix>.dwr differs.
# US English (*_us.dwr) is the fallback UI language and is always kept.
LANGUAGES="ar bg cs:cz da:dk de el:gr en-GB:uk es et:ee fi fr hu id it ja:jp
	kk:kz ko:kr lt lv nl pl pt pt-BR:pb ro ru sk sl:si sv:se tr uk:ua zh"
for lang in ${LANGUAGES}; do
	IUSE+=" l10n_${lang%:*}"
done
unset lang

# libcurl is linked statically; libgtk-3, libpango, libfontconfig and libcups
# are dlopen()ed.  The binaries carry RPATH=$ORIGIN/dpf3 for their bundled
# libraries, so the RPATH must be kept.
RDEPEND="
	app-misc/ca-certificates
	dev-libs/glib:2
	media-libs/fontconfig
	media-libs/gst-plugins-base:1.0
	media-libs/gstreamer:1.0
	media-libs/libglvnd[X]
	x11-libs/gtk+:3[X]
	x11-libs/libX11
	x11-libs/libXext
	x11-libs/libXmu
	x11-libs/libXrandr
	x11-libs/libXrender
	x11-libs/pango
	cups? ( net-print/cups )
"
BDEPEND="app-arch/xz-utils"

QA_PREBUILT="opt/${PN}/*"

src_unpack() {
	default
	# The inner archive is XZ-compressed despite its .tar.lzma suffix, which
	# unpack() would hand to "lzma -d" (legacy format only).
	mkdir "${S}" || die
	tar -xJf office2024.tar.lzma -C "${S}" || die
	rm office2024.tar.lzma installsmoffice || die
}

src_prepare() {
	default

	local lang suffix
	for lang in ${LANGUAGES}; do
		use "l10n_${lang%:*}" && continue
		suffix=${lang#*:}
		rm {textmaker,planmaker,presentations}_"${suffix}".dwr || die
	done
}

src_install() {
	local app
	insinto /opt/${PN}
	doins -r .
	for app in textmaker planmaker presentations; do
		fperms +x /opt/${PN}/${app}
		dobin "${FILESDIR}"/${PN}-${app}
		dosym ${PN}-${app} /usr/bin/${app}24
		domenu "${FILESDIR}"/${PN}-${app}.desktop
	done

	local size
	for size in 16 24 32 48 64 128 256 512; do
		newicon -s ${size} icons/tml_${size}.png ${PN}-textmaker.png
		newicon -s ${size} icons/pml_${size}.png ${PN}-planmaker.png
		newicon -s ${size} icons/prl_${size}.png ${PN}-presentations.png
	done

	insinto /usr/share/mime/packages
	doins mime/${PN}-2024.xml
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "SoftMaker Office 2024 is commercial software: it needs a purchased"
	elog "product key, entered on first start.  A free 30-day trial key is"
	elog "available at https://www.softmaker.com/en/softmaker-office"
}
