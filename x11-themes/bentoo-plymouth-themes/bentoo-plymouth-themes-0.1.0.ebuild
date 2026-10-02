# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Plymouth boot splash themes from the bentoo distribution"
HOMEPAGE="https://github.com/obentoo/bentoo"
# Artwork and .plymouth descriptors only. The script is shared by every theme
# and lives in FILESDIR, so a fix to it is a reviewable diff, not a new tarball.
SRC_URI="https://distfiles.obentoo.org/${P}.tar.xz"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

RDEPEND="sys-boot/plymouth"

# Per-theme layout: theme name, logo top, spinner top, password box divisor,
# text gray level. The first three are what each theme shipped with before the
# script was shared; the text is dark only where the background is light.
BENTOO_PLYMOUTH_THEMES=(
	"bentoo-compile-it    0.30 0.37 1.2 1.0"
	"bentoo-compile-it-v2 0.30 0.37 1.2 1.0"
	"compile-it           0.30 0.37 1.2 1.0"
	"funtoo               0.30 0.37 1.2 1.0"
	"funtoo-next          0.30 0.37 1.2 1.0"
	"funtoo-tux           0.30 0.37 1.2 1.0"
	"gentoo               0.30 0.37 1.2 1.0"
	"gentoo-maskots       0.20 0.37 1.26 1.0"
	"gnu-meditate         0.25 0.25 1.2 0.15"
)

src_compile() {
	local entry name logo_y anim_y box_y_div text_shade
	for entry in "${BENTOO_PLYMOUTH_THEMES[@]}"; do
		read -r name logo_y anim_y box_y_div text_shade <<< "${entry}"
		[[ -f ${name}/${name}.plymouth ]] || die "theme ${name} missing from ${A}"
		sed -e "s/@LOGO_Y@/${logo_y}/" \
			-e "s/@ANIM_Y@/${anim_y}/" \
			-e "s/@BOX_Y_DIV@/${box_y_div}/" \
			-e "s/@TEXT_SHADE@/${text_shade}/" \
			"${FILESDIR}/${PN}.script" > "${name}/${name}.script" || die
		# sed exits 0 even when nothing matched; a leftover placeholder would
		# make plymouth fail to parse the script at boot.
		if grep -q '@[A-Z_]*@' "${name}/${name}.script"; then
			die "unreplaced layout placeholder in ${name}.script"
		fi
	done
}

src_install() {
	local entry
	insinto /usr/share/plymouth/themes
	for entry in "${BENTOO_PLYMOUTH_THEMES[@]}"; do
		doins -r "${entry%% *}"
	done
}

pkg_postinst() {
	elog "Select a theme with: plymouth-set-default-theme <name>"
	elog "The theme is copied into the initramfs, so regenerate it (or the UKI)"
	elog "after installing or updating this package for the change to show at boot."
}
