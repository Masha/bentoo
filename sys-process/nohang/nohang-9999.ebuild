# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{12..15} )

inherit python-single-r1 systemd

DESCRIPTION="Low memory handler that acts on PSI pressure before the kernel OOM killer"
HOMEPAGE="https://github.com/hakavlad/nohang"

if [[ ${PV} == 9999 ]]; then
	inherit git-r3
	EGIT_REPO_URI="https://github.com/hakavlad/nohang.git"
else
	SRC_URI="https://github.com/hakavlad/nohang/archive/v${PV}.tar.gz -> ${P}.tar.gz"
	KEYWORDS="~amd64 ~arm64 ~x86"
fi

LICENSE="MIT"
SLOT="0"
IUSE="desktop systemd"

REQUIRED_USE="${PYTHON_REQUIRED_USE}"

# The daemon itself is pure stdlib Python. The desktop profile shells out to
# notify-send through sudo to reach the logged-in user's session bus.
RDEPEND="
	${PYTHON_DEPS}
	desktop? (
		app-admin/sudo
		x11-libs/libnotify
	)
"

src_prepare() {
	default

	# The Makefile takes the version string from `git describe`, which leaves
	# the file empty when building from a release tarball: the shell truncates
	# it before git fails, and the `-` prefix swallows the error.
	sed -i \
		-e "s|-git describe --tags --long --dirty > version|echo v${PV} > version|" \
		Makefile || die "failed to pin the version string"

	# The Makefile gzips the manpages on its way into ${D}. Portage compresses
	# man/ itself, and warns about anything that arrives already compressed, so
	# hand the pages over as-is and let docompress decide.
	sed -i \
		-e 's|gzip -9cn \(\S*\) > \(\S*\)\.gz|install -p -m0644 \1 \2|' \
		Makefile || die "failed to defer manpage compression to portage"
	if grep -q 'gzip -9cn' Makefile; then
		die "manpage gzip calls left in the Makefile"
	fi

	# /var/run is a compat symlink; OpenRC pidfiles belong in /run, and want
	# the .pid suffix that start-stop-daemon consumers expect.
	sed -i \
		-e 's|pidfile="/var/run/nohang"|pidfile="/run/nohang.pid"|' \
		openrc/nohang.in || die "failed to relocate the nohang pidfile"
	sed -i \
		-e 's|pidfile="/var/run/nohang-desktop"|pidfile="/run/nohang-desktop.pid"|' \
		openrc/nohang-desktop.in || die "failed to relocate the nohang-desktop pidfile"
}

src_compile() {
	# Nothing to build: every executable is a standalone Python script, and the
	# manpages ship pregenerated. The upstream `all` target only prints a hint.
	:
}

src_install() {
	local makeargs=(
		DESTDIR="${D}"
		PREFIX="${EPREFIX}/usr"
		SYSCONFDIR="${EPREFIX}/etc"
		DOCDIR="${EPREFIX}/usr/share/doc/${PF}"
	)

	# The daemon, the two config profiles, the manpages and the logrotate
	# snippet. Everything init-system specific is handled below.
	emake "${makeargs[@]}" base

	# The init scripts are deliberately NOT gated on USE=systemd: they cost a
	# systemd user nothing, and they are the only way to start the daemon on a
	# host that does not run systemd.
	#
	# Expanded here rather than through the upstream install-openrc target,
	# which installs them 0775 - group-writable, for scripts that run as root.
	local svc
	for svc in nohang nohang-desktop; do
		sed \
			-e "s|:TARGET_SBINDIR:|${EPREFIX}/usr/sbin|" \
			-e "s|:TARGET_SYSCONFDIR:|${EPREFIX}/etc|" \
			"openrc/${svc}.in" > "${T}/${svc}.initd" || die "failed to expand the ${svc} init script"
		newinitd "${T}/${svc}.initd" "${svc}"
	done

	# `units` is invoked on its own rather than through the upstream `install`
	# target, which also runs chcon and `systemctl daemon-reload` against the
	# live host instead of against ${D}.
	if use systemd; then
		emake "${makeargs[@]}" \
			SYSTEMDUNITDIR="$(systemd_get_systemunitdir)" units
	fi

	python_fix_shebang "${ED}"

	# Referenced by the shipped logrotate snippet and by separate_log = True.
	keepdir /var/log/nohang
}

pkg_postinst() {
	if [[ -z ${REPLACING_VERSIONS} ]]; then
		elog "Two profiles are installed, and they conflict - enable only one:"
		elog "  nohang          - conservative, headless-safe defaults"
		elog "  nohang-desktop  - tuned for interactive use, sends GUI warnings"
		elog
		elog "OpenRC:  rc-update add nohang default && rc-service nohang start"
		if use systemd; then
			elog "systemd: systemctl enable --now nohang.service"
		fi
		elog
		elog "GUI notifications from the desktop profile need USE=desktop."
		if [[ ! -e /proc/pressure/memory ]]; then
			elog
			elog "This kernel exposes no /proc/pressure/memory: PSI is off."
			elog "Enable CONFIG_PSI, and boot with psi=1 if CONFIG_PSI_DEFAULT_DISABLED"
			elog "is set. Without PSI, nohang falls back to plain memory thresholds."
		fi
	fi
}
