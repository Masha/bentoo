# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop linux-info systemd unpacker xdg

DESCRIPTION="Obscura VPN client, service and desktop app (prebuilt binaries)"
HOMEPAGE="
	https://obscura.com/
	https://github.com/Sovereign-Engineering/obscuravpn-client
"

OBSCURA_POOL="https://linux-pkgs.obscura.com/deb/pool/main"
SRC_URI="
	${OBSCURA_POOL}/obscura-cli_${PV}_amd64.deb -> ${P}-cli-amd64.deb
	gui? ( ${OBSCURA_POOL}/obscura-gui_${PV}_amd64.deb -> ${P}-gui-amd64.deb )
"
S="${WORKDIR}"

# The 1.180 debs ship /usr/share/doc/obscura-{cli,gui}/copyright with the
# PolyForm Noncommercial 1.0.0 text, and the GUI metainfo says the same.
# Upstream relicensed the repository to GPL-3 with an OpenSSL-style linking
# exception on 2026-09-22 (commit 3e55fb3fd6, "switch to GPLv3 License"),
# four days AFTER 1.180 was built.  This binary was published under the terms
# it carries, so LICENSE follows the deb.  On the next bump re-read
# usr/share/doc/obscura-cli/copyright: once it says GPL-3, switch this to
# GPL-3-with-openssl-exception (in ::gentoo) and drop the overlay license.
LICENSE="PolyForm-Noncommercial-1.0.0"
SLOT="0"
# amd64 only: the APT repository's Release file lists "Architectures: amd64"
# and there is no binary-arm64 index (checked 2026-09-24).  Upstream builds
# arm64 for no Linux package format, so there is nothing to keyword.
KEYWORDS="-* ~amd64"
IUSE="+gui systemd"
# PolyForm Noncommercial permits redistribution, but only to noncommercial
# recipients with the license attached; neither Gentoo mirrors nor binary
# package hosts can guarantee that, hence bindist + mirror.  Stripping is
# allowed: the upstream ELFs carry full debug_info and nothing depends on it.
RESTRICT="bindist mirror"

# NEEDED, from readelf -d on the 1.180 binaries:
#   obscura:     liblzma.so.5 libtss2-esys.so.0 libtss2-tctildr.so.0
#                libtss2-mu.so.0 libgcc_s.so.1 libm.so.6 libc.so.6
#   obscura-gui: libwebkitgtk-6.0.so.4 libjavascriptcoregtk-6.0.so.1
#                libgtk-4.so.1 libadwaita-1.so.0 libgio-2.0.so.0
#                libgobject-2.0.so.0 libglib-2.0.so.0 liblzma.so.5 + libc/gcc
# libtss2-tcti-device.so.0 (in the deb's Depends) is dlopen()ed by tctildr to
# reach /dev/tpmrm0; tpm2-tss always builds it.
# sys-apps/shadow: "obscura add-operator" runs usermod to add users to the
# obscura group.
RDEPEND="
	!net-vpn/obscura
	acct-group/obscura
	app-arch/xz-utils
	app-crypt/tpm2-tss
	sys-apps/shadow
	gui? (
		dev-libs/glib:2
		gui-libs/gtk:4
		gui-libs/libadwaita:1
		net-libs/webkit-gtk:6
	)
"
BDEPEND="app-arch/xz-utils"

QA_PREBUILT="usr/bin/obscura usr/bin/obscura-gui"

# The service creates a userspace tun device ("obscuravpn") and an
# "inet obscura" nftables table using conntrack marks plus an arp chain for
# its kill switch; without these it fails with NftablesSetup at startup.
CONFIG_CHECK="~TUN ~NF_TABLES ~NF_TABLES_INET ~NF_TABLES_ARP ~NFT_CT ~NF_CONNTRACK"

src_install() {
	dobin usr/bin/obscura

	# Always installed, never behind USE=systemd: the only way to run the
	# daemon on OpenRC.  Same content as net-vpn/obscura's pair.
	newinitd "${FILESDIR}"/obscura.initd obscura
	newconfd "${FILESDIR}"/obscura.confd obscura

	if use systemd; then
		systemd_dounit usr/lib/systemd/system/obscura.service
	fi
	# usr/lib/sysusers.d/obscura-cli.conf ("g obscura - -") is deliberately
	# not installed: acct-group/obscura creates the group on every init.

	if use gui; then
		dobin usr/bin/obscura-gui

		domenu usr/share/applications/net.obscura.vpn.gui.desktop

		insinto /usr/share/metainfo
		doins usr/share/metainfo/net.obscura.vpn.gui.metainfo.xml

		local size
		for size in 64 128 256; do
			doicon -s ${size} usr/share/icons/hicolor/${size}x${size}/apps/net.obscura.vpn.gui.png
		done
		# etc/apparmor.d/obscura-gui is an "unconfined" profile whose only
		# rule is "userns,": it exempts WebKit's sandbox from Ubuntu's
		# kernel.apparmor_restrict_unprivileged_userns=1 default.  That
		# sysctl is off unless an admin turns it on, so it is not installed.
	fi
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "Start the service with one of:"
	elog "    rc-service obscura start && rc-update add obscura default"
	elog "    systemctl enable --now obscura.service"
	elog
	elog "Without systemd-resolved or NetworkManager the service refuses to"
	elog "start with --dns auto; see OBSCURA_DNS in /etc/conf.d/obscura."
	elog
	elog "Only members of the 'obscura' group may control the service:"
	elog "    obscura add-operator <user>    (then log in again)"
}
