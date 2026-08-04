# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Node.js eselect module"
HOMEPAGE="https://wiki.gentoo.org/wiki/No_homepage"
S=${WORKDIR}

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64 ~arm ~arm64 ~loong ~ppc64 ~riscv ~x86"

# The blocker mirrors the one every slotted net-libs/nodejs carries, and it has
# to live here too: this package takes ownership of /etc/env.d/50npm, which an
# already-merged unslotted nodejs still records in its CONTENTS.  Portage merges
# a dependency before its dependant, so without a strong blocker this package
# would be merged while nodejs:0 is still installed and FEATURES="protect-owned"
# would abort on that one file.  Strong (!!) rather than weak, so the unslotted
# package is unmerged before this one is merged rather than alongside it.
# Precedent: app-eselect/eselect-lua blocks dev-lang/lua:0 for the same reason.
RDEPEND="
	app-admin/eselect
	!!net-libs/nodejs:0
"

src_install() {
	insinto /usr/share/eselect/modules/
	newins "${FILESDIR}"/nodejs.eselect-${PV} nodejs.eselect

	# The shared npm configuration lives here rather than in net-libs/nodejs:
	# neither path is slot-specific, so two installed slots would own the same
	# file, and FEATURES="protect-owned" turns that collision into a merge
	# failure.  Owning them from this single-instance package keeps
	# NPM_CONFIG_GLOBALCONFIG pointing at one shared file for every slot.
	# Only the directory is owned; npmrc itself is created by the user.
	keepdir /etc/npm
	echo "NPM_CONFIG_GLOBALCONFIG=${EPREFIX}/etc/npm/npmrc" > "${T}"/50npm || die
	doenvd "${T}"/50npm
}

pkg_postinst() {
	# Re-apply the current selection, without changing which slot it names.
	#
	# The unversioned entry points are runtime state this module owns, not files
	# any package records in its CONTENTS, so a merge of this package never
	# regenerates them.  That is fine while the module only changes behaviour -
	# but version 2 changed the *shape* of what it writes, from symlinks to exec
	# wrappers, and an upgrade therefore left the version-1 symlinks sitting in
	# /usr/bin.  The whole point of the wrapper is that `readlink -f` on the
	# entry point resolves to itself; a stale symlink keeps
	# www-client/chromium's src_prepare verification failing exactly as before,
	# with nothing in the merge output suggesting why.
	#
	# Measured on the box this was first reported from: /usr/bin/node was
	# written 09:57 by an unrelated nodejs merge and this package landed at
	# 10:03, so the new module was installed and inert for six minutes.
	#
	# get_active_slot() still recognises the version-1 symlink, so `show` answers
	# correctly even before the first re-write and the selection survives it.
	# Nothing active is the normal state on a first install: net-libs/nodejs's
	# own pkg_postinst makes the initial selection, and doing it here too would
	# race it.
	local active
	active=$(eselect nodejs show 2>/dev/null)

	if [[ -n ${active} ]]; then
		einfo "Re-applying the active Node.js slot (${active}) in the current entry-point format"
		# Not fatal: a failure here leaves the previous entry points in place,
		# which is a working system with an outdated shape.  Dying in postinst
		# would fail the merge over something the user can redo by hand.
		eselect nodejs set "${active}" ||
			ewarn "Could not re-apply ${active}; run 'eselect nodejs set ${active}' manually"
	fi
}
