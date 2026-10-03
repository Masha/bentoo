# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{12..14} )
# The sdist carries a PEP 740 attestation from this repo's ci.yml; the tools
# run as root, so a re-uploaded sdist must not be pinned on trust alone.
PYPI_VERIFY_REPO=https://github.com/superm1/amd-debug-tools

inherit distutils-r1 optfeature pypi shell-completion

DESCRIPTION="Debug tools for AMD Zen systems: s2idle, BIOS, P-State and TTM"
HOMEPAGE="
	https://git.kernel.org/pub/scm/linux/kernel/git/superm1/amd-debug-tools.git
	https://github.com/superm1/amd-debug-tools
	https://pypi.org/project/amd-debug-tools/
"

LICENSE="MIT"
SLOT="0"
# amd-s2idle, amd-pstate and amd-bios read x86-only interfaces (the AMD PMC
# driver, amd-pstate, the ACPI FADT low-power-idle bit); there is no AMD Zen
# arm64 platform for them to run on.
KEYWORDS="~amd64"
IUSE="systemd"

# pyproject lists cysystemd and dbus-fast as hard dependencies, but upstream
# imports both lazily and falls back: kernel.py tries cysystemd, then
# python-systemd, then dmesg; common.py tries dbus-fast, then dbus-python, for
# the logind reboot. cysystemd is not packaged, so USE=systemd maps to
# python-systemd, the second rung of the same journal fallback. Without it the
# kernel log comes from dmesg, which is also what a non-systemd host uses.
RDEPEND="
	dev-python/jinja2[${PYTHON_USEDEP}]
	dev-python/markupsafe[${PYTHON_USEDEP}]
	dev-python/matplotlib[${PYTHON_USEDEP}]
	dev-python/numpy[${PYTHON_USEDEP}]
	dev-python/packaging[${PYTHON_USEDEP}]
	dev-python/pandas[${PYTHON_USEDEP}]
	dev-python/pyudev[${PYTHON_USEDEP}]
	dev-python/seaborn[${PYTHON_USEDEP}]
	dev-python/tabulate[${PYTHON_USEDEP}]
	systemd? ( dev-python/python-systemd[${PYTHON_USEDEP}] )
"
BDEPEND="
	dev-python/setuptools-scm[${PYTHON_USEDEP}]
"

distutils_enable_tests unittest

src_prepare() {
	# package-dir = src with no package list makes setuptools auto-discover
	# every top-level module there, so launcher.py and all eighteen test_*.py
	# land loose in site-packages. Pin the list to the real package.
	grep -qxF 'package-dir = {"" = "src"}' pyproject.toml ||
		die "pyproject.toml no longer sets package-dir; recheck the packages pin"
	sed -i '/^package-dir = {"" = "src"}$/a packages = ["amd_debug"]' \
		pyproject.toml || die

	distutils-r1_src_prepare
}

python_test() {
	eunittest -s src
}

python_install_all() {
	distutils-r1_python_install_all

	newbashcomp src/amd_debug/bash/amd-s2idle amd-s2idle
}

pkg_postinst() {
	optfeature "ACPI table decoding in amd-s2idle" sys-power/iasl
	optfeature "Wake-on-LAN checks in amd-s2idle" sys-apps/ethtool
	optfeature "EDID decoding in amd-s2idle" media-libs/libdisplay-info
	optfeature "firmware versions in the amd-s2idle report" \
		"dev-python/pygobject sys-apps/fwupd[introspection]"
	optfeature "rebooting through logind after amd-ttm --set" \
		dev-python/dbus-fast dev-python/dbus-python

	elog "amd-s2idle, amd-bios, amd-pstate and amd-ttm re-run themselves as"
	elog "root and write files on the caller's behalf (--report-file, logs under"
	elog "~/.local/share). They are root-equivalent: never expose them through a"
	elog "restricted sudoers rule such as 'NOPASSWD: /usr/bin/amd-s2idle *'."
	elog
	elog "amd-ttm --set writes /etc/modprobe.d/ttm.conf and then runs a bare"
	elog "'dracut --force'. On a UKI or Secure Boot setup rebuild the image the"
	elog "way the kernel package does instead (installkernel, or"
	elog "'emerge --config' on the kernel), or pass ttm.pages_limit= on the"
	elog "kernel command line."
}
