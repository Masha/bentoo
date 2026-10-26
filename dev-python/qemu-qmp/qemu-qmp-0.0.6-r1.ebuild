# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{12..15} )

inherit distutils-r1 optfeature pypi

DESCRIPTION="QEMU Monitor Protocol library"
HOMEPAGE="
	https://gitlab.com/qemu-project/python-qemu-qmp
	https://pypi.org/project/qemu.qmp/
"

LICENSE="GPL-2 LGPL-2+"
SLOT="0"
KEYWORDS="~amd64 ~arm64 ~ppc64"

# BENTOO-DIVERGENCE: RDEPEND - blocker raised from <qemu-11.1.2-r0 to -r1.
# Until 2026-10-24 this overlay's qemu-11.1.2 was forked from 10.2.x and
# installed /usr/bin/qmp-shell itself; it was then rebased onto ::gentoo's
# 11.1.2 under the SAME PVR, so ::gentoo's blocker (<11.1.2-r0) never matches
# an image built from the old ebuild, and merging this package dies on a file
# collision (bentoo issue #53). The rebase now ships as qemu-11.1.2-r1; this
# blocker is what lets Portage hand qmp-shell over from the old image instead
# of refusing the merge. Drop this mirror once no supported install can still
# carry that image (see .autoupdate/packages.toml).
RDEPEND="!<app-emulation/qemu-11.1.2-r1[python]"
BDEPEND="
	dev-python/setuptools-scm[${PYTHON_USEDEP}]
	dev-python/wheel[${PYTHON_USEDEP}]
	test? (
		dev-python/pygments[${PYTHON_USEDEP}]
		dev-python/urwid-readline[${PYTHON_USEDEP}]
		dev-python/urwid[${PYTHON_USEDEP}]
	)
"

EPYTEST_PLUGINS=()
distutils_enable_tests pytest

pkg_postinst() {
	optfeature "Terminal User Interface support" "dev-python/pygments dev-python/urwid dev-python/urwid-readline"
}
