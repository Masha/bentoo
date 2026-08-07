# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
PYTHON_COMPAT=( python3_{12..14} )

inherit desktop multilib python-single-r1 systemd unpacker xdg

DESCRIPTION="Folding@Home distributed computing client for protein folding research"
HOMEPAGE="https://foldingathome.org/"

BASE_URI="https://download.foldingathome.org/releases/public/fah-client"
SRC_URI="
	amd64? ( ${BASE_URI}/debian-10-64bit/release/fah-client_${PV}_amd64.deb -> ${P}-amd64.deb )
	arm64? ( ${BASE_URI}/debian-stable-arm64/release/fah-client_${PV}_arm64.deb -> ${P}-arm64.deb )
"
S="${WORKDIR}"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
IUSE="elogind systemd"
REQUIRED_USE="^^ ( elogind systemd ) ${PYTHON_REQUIRED_USE}"
RESTRICT="bindist mirror strip"

# The prebuilt fah-client has a DT_NEEDED on libsystemd.so.0 and is BIND_NOW,
# so the loader aborts before main() unless that SONAME resolves. Only one of
# the two providers may be depended on: sys-auth/elogind carries an explicit
# !sys-apps/systemd blocker, so an unconditional dep would make the package
# unemergeable for every systemd user.
#
# fahctl is a python3 script. It carries PEP 723 inline metadata declaring
# websocket-client, and the import is mandatory: the ImportError branch only
# prints a hint and exits 1, so without it the command is dead on arrival.
RDEPEND="
	${PYTHON_DEPS}
	$(python_gen_cond_dep '
		dev-python/websocket-client[${PYTHON_USEDEP}]
	')
	acct-group/foldingathome
	acct-user/foldingathome
	dev-libs/openssl:=
	sys-libs/glibc
	sys-libs/zlib:=
	elogind? ( sys-auth/elogind )
	systemd? ( sys-apps/systemd )
"
BDEPEND="elogind? ( dev-util/patchelf )"

QA_PREBUILT="*"

src_install() {
	if use elogind; then
		# elogind ships libelogind.so.0 with the LIBSYSTEMD_<n> version nodes
		# and all seven sd_bus_* symbols fah-client imports, so this symlink
		# satisfies the loader's version check for real. A private RUNPATH
		# (not RPATH) keeps the override local to this binary and needs no
		# environment variable from the caller.
		dodir /opt/foldingathome/lib
		dosym "../../../usr/$(get_libdir)/libelogind.so.0" /opt/foldingathome/lib/libsystemd.so.0
		patchelf --set-rpath "${EPREFIX}/opt/foldingathome/lib" usr/bin/fah-client || die
	fi

	# Rewrite the upstream "#!/usr/bin/env python3" to the interpreter this
	# build selected, so fahctl runs on the exact implementation that
	# dev-python/websocket-client was installed for. Like the patchelf call
	# above, this edits the payload in ${S} before it is copied into the image.
	python_fix_shebang usr/bin/fahctl

	exeinto /opt/foldingathome
	doexe usr/bin/fah-client
	doexe usr/bin/fahctl

	dosym ../../opt/foldingathome/fah-client /usr/bin/fah-client
	dosym ../../opt/foldingathome/fahctl /usr/bin/fahctl

	keepdir /etc/fah-client
	keepdir /var/lib/fah-client
	keepdir /var/log/fah-client
	fowners foldingathome:foldingathome /etc/fah-client
	fowners foldingathome:foldingathome /var/lib/fah-client
	fowners foldingathome:foldingathome /var/log/fah-client

	newinitd "${FILESDIR}"/foldingathome-initd fah-client
	newconfd "${FILESDIR}"/foldingathome-confd fah-client
	systemd_dounit "${FILESDIR}"/fah-client.service

	insinto /usr/share/polkit-1/rules.d
	newins "${FILESDIR}"/10-fah-client.rules 10-fah-client.rules

	newicon usr/share/pixmaps/fahlogo.png fah-client.png
	make_desktop_entry "xdg-open https://app.foldingathome.org/" \
		"Folding@home Client" fah-client "Science;Biology;"

	dodoc usr/share/doc/fah-client/README.md
}

pkg_postinst() {
	xdg_pkg_postinst
	elog "To run Folding@home in the background at boot:"
	elog "  OpenRC:  rc-update add fah-client default"
	elog "  systemd: systemctl enable fah-client"
	elog ""
	elog "Access the web interface at http://localhost:7396"
	elog "Or use the official web app at https://app.foldingathome.org/"
}

pkg_postrm() {
	xdg_pkg_postrm
	elog "Folding@home data files in /var/lib/fah-client were not removed."
	elog "Remove them manually if no longer needed."
}
