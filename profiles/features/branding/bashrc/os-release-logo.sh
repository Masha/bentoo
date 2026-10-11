# baselayout builds os-release from BRANDING_OS_* (make.defaults), but its
# template has no LOGO line. Append one naming the icon x11-themes/bentoo-logos
# installs.
#
# A post_src_install in /etc/portage/bashrc is sourced later and replaces this
# one; os-release then simply has no LOGO line.
post_src_install() {
	local f="${ED}/usr/lib/os-release"
	[[ -f ${f} ]] || return 0
	grep -q '^LOGO=' "${f}" && return 0
	echo "LOGO='bentoo'" >> "${f}" || die "bentoo branding: cannot append LOGO to ${f}"
	einfo "bentoo branding: LOGO='bentoo' appended to /usr/lib/os-release"
}
