# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

CRATES="
	aho-corasick@1.1.5
	async-broadcast@0.7.2
	async-channel@2.5.0
	async-executor@1.14.0
	async-io@2.6.0
	async-lock@3.4.2
	async-process@2.5.0
	async-recursion@1.1.1
	async-signal@0.2.14
	async-task@4.7.1
	async-trait@0.1.92
	atomic-waker@1.1.2
	autocfg@1.5.1
	bitflags@2.13.2
	block2@0.6.2
	blocking@1.7.0
	bumpalo@3.20.3
	cc@1.4.6
	cfg-if@1.0.4
	concurrent-queue@2.5.0
	crossbeam-utils@0.8.23
	deranged@0.5.8
	dispatch2@0.3.1
	endi@1.1.1
	enumflags2@0.7.12
	enumflags2_derive@0.7.12
	equivalent@1.0.2
	errno@0.3.14
	event-listener-strategy@0.5.4
	event-listener@5.4.2
	fastrand@2.5.0
	find-msvc-tools@0.1.12
	futures-channel@0.3.34
	futures-core@0.3.34
	futures-io@0.3.34
	futures-lite@2.6.1
	futures-macro@0.3.34
	futures-task@0.3.34
	futures-util@0.3.34
	getrandom@0.4.3
	hashbrown@0.17.1
	hermit-abi@0.5.3
	hex@0.4.3
	indexmap@2.14.2
	itoa@1.0.18
	js-sys@0.3.105
	ksni@0.3.6
	lazy_static@1.5.0
	libc@0.2.189
	linux-raw-sys@0.12.1
	log@0.4.34
	mac-notification-sys@0.6.15
	matchers@0.2.0
	memchr@2.8.3
	memoffset@0.9.1
	notify-rust@4.18.0
	nu-ansi-term@0.50.3
	num-conv@0.2.2
	objc2-core-foundation@0.3.2
	objc2-encode@4.1.0
	objc2-foundation@0.3.2
	objc2@0.6.4
	once_cell@1.21.4
	ordered-stream@0.2.0
	parking@2.2.1
	pastey@0.2.3
	pin-project-lite@0.2.17
	piper@0.2.5
	polling@3.11.0
	powerfmt@0.2.0
	proc-macro-crate@3.5.0
	proc-macro2@1.0.107
	quote@1.0.47
	r-efi@6.0.0
	regex-automata@0.4.18
	regex-syntax@0.8.11
	rustix@1.1.4
	rustversion@1.0.23
	serde@1.0.229
	serde_core@1.0.229
	serde_derive@1.0.229
	serde_json@1.0.151
	serde_repr@0.1.21
	sharded-slab@0.1.7
	shlex@2.0.1
	signal-hook-registry@1.4.8
	slab@0.4.12
	smallvec@1.16.1
	syn@2.0.119
	syn@3.0.5
	task-local@0.1.1
	tauri-winrt-notification@0.7.3
	tempfile@3.27.0
	thiserror-impl@2.0.20
	thiserror@2.0.20
	thread_local@1.1.10
	time-core@0.1.8
	time@0.3.47
	toml_datetime@1.1.1+spec-1.1.0
	toml_edit@0.25.15+spec-1.1.0
	toml_parser@1.1.3+spec-1.1.0
	tracing-attributes@0.1.31
	tracing-core@0.1.36
	tracing-log@0.2.0
	tracing-serde@0.2.0
	tracing-subscriber@0.3.23
	tracing@0.1.44
	uds_windows@1.2.1
	unicode-ident@1.0.24
	uuid@1.26.1
	valuable@0.1.1
	wasm-bindgen-macro-support@0.2.128
	wasm-bindgen-macro@0.2.128
	wasm-bindgen-shared@0.2.128
	wasm-bindgen@0.2.128
	windows-collections@0.2.0
	windows-core@0.61.2
	windows-future@0.2.1
	windows-implement@0.60.2
	windows-interface@0.59.3
	windows-link@0.1.3
	windows-link@0.2.1
	windows-numerics@0.2.0
	windows-result@0.3.4
	windows-strings@0.4.2
	windows-sys@0.61.2
	windows-threading@0.1.0
	windows-version@0.1.7
	windows@0.61.3
	winnow@0.7.15
	winnow@1.0.4
	zbus@5.13.2
	zbus_macros@5.13.2
	zbus_names@4.3.1
	zmij@1.0.23
	zvariant@5.9.2
	zvariant_derive@5.9.2
	zvariant_utils@3.3.0
"

# NOT upstream's own floor, which is rust-version = "1.85" (the edition 2024
# minimum). The real floor comes from a dependency: notify-rust-4.18.0 declares
# rust-version = "1.89.0", the highest in the resolved crate set, and cargo.eclass
# checks every vendored Cargo.toml -- building with 1.85 raises a QA notice
# naming exactly this. Re-derive on every bump; the dependency moves this, not
# the package.
RUST_MIN_VER="1.89.0"

inherit cargo desktop systemd xdg-utils

DESCRIPTION="Desktop tray indicator for Claude Code agent sessions, fed by hooks"
HOMEPAGE="https://github.com/lucascouts/zeo-systray"
SRC_URI="
	https://github.com/lucascouts/zeo-systray/archive/v${PV}.tar.gz -> ${P}.tar.gz
	${CARGO_CRATE_URIS}
"

# License for the package itself, then the dependent crate licenses as
# resolved by pycargoebuild.
LICENSE="MIT"
# Dependent crate licenses
LICENSE+=" MIT Unicode-3.0 Unlicense"
SLOT="0"
# KEYWORDS: ~amd64 only, and that is a restriction, not a default. Nothing here
# is arch-bound -- it is pure Rust with no prebuilt payload and no -sys crate
# needing a system library -- but amd64 is the only arch this was built and run
# on. The code IS Linux-bound (std::os::unix datagram sockets, XDG_RUNTIME_DIR),
# so no non-Linux keyword is possible. Add ~arm64 once someone builds it there.
KEYWORDS="~amd64"
IUSE="systemd"

# No DEPEND/RDEPEND on purpose, and that is a finding rather than an omission.
# The binary links libc and nothing else: the SNI tray and the desktop
# notification are both spoken as D-Bus messages over a socket by zbus, which is
# pure Rust, so there is no libdbus, no GTK and no libappindicator to link. The
# session bus and the StatusNotifierHost that renders the icon come from the
# desktop session, not from a package this one can name.
#
# BDEPEND is not set either: rust.eclass, inherited through cargo.eclass,
# already puts ${RUST_DEPEND} there, and no crate here needs pkg-config.

# Upstream's [profile.release] sets strip = true, so the binary arrives already
# stripped and carrying no .GCC.command.line section. Both notices are about
# that one decision, not about the packaging.
QA_FLAGS_IGNORED="usr/bin/${PN}"
QA_PRESTRIPPED="usr/bin/${PN}"

src_install() {
	cargo_src_install

	# The tray icon is looked up by name in the icon theme, so it has to land
	# in hicolor. assets/theme/ is deliberately NOT installed: it is a
	# development convenience tree whose only content is a symlink back to
	# this file, for running the daemon straight out of a build tree.
	doicon -s scalable assets/${PN}.svg

	# A *user* unit, never a system one. The daemon needs a session bus with a
	# StatusNotifierHost on it, and that only exists once the desktop is up --
	# there is nothing for it to draw on at boot, and a system instance would
	# have no session bus to reach at all. Hence WantedBy=graphical-session.target
	# inside the unit and the user unit directory here.
	if use systemd; then
		systemd_douserunit contrib/${PN}.service
	fi

	# Same scope, for hosts without systemd. Never gated on USE=systemd: it
	# costs a systemd user nothing and is the only way to start the daemon on
	# an OpenRC desktop. /etc/user/init.d is the user-scope counterpart of
	# /etc/init.d, driven by `rc-service --user`.
	exeinto /etc/user/init.d
	newexe "${FILESDIR}"/${PN}.initd ${PN}

	# The KDE opener: switches virtual desktop and raises the editor window
	# before handing over the deep link, through a KWin script -- the one thing
	# an application cannot do for itself on Wayland. Under /usr/share rather
	# than /usr/bin because it is not a command a person runs; it is what
	# ZEO_SYSTRAY_OPEN_CMD points at, and pkg_postinst says so.
	exeinto /usr/share/${PN}
	doexe contrib/${PN}-open-kde.sh

	einstalldocs
	# The hook wiring is documentation, not configuration: it has to be merged
	# into a ~/.claude/settings.json this package must not touch. Left
	# uncompressed because pkg_postinst names the path and someone has to be
	# able to open it there.
	dodoc contrib/hooks.example.json
	docompress -x /usr/share/doc/${PF}/hooks.example.json
}

pkg_postinst() {
	xdg_icon_cache_update

	elog "zeo-systray is fed by Claude Code hooks. Append the entries in"
	elog "  /usr/share/doc/${PF}/hooks.example.json"
	elog "to the matching arrays in ~/.claude/settings.json -- appending, not"
	elog "replacing, or you drop whatever else runs on those events."
	elog
	elog "Then start the daemon as your desktop user:"
	if use systemd; then
		elog "  systemctl --user enable --now ${PN}.service"
	fi
	elog "  rc-service --user ${PN} start   (OpenRC)"
	elog
	elog "On KDE, to have a click switch desktop and raise the editor window:"
	elog "  ZEO_SYSTRAY_OPEN_CMD='/usr/share/${PN}/${PN}-open-kde.sh {session} {cwd}'"
	elog
	elog "GNOME removed built-in tray support: there it additionally needs the"
	elog "AppIndicator Support or Status Tray shell extension. Every other"
	elog "desktop with a StatusNotifierHost (Plasma, XFCE, MATE, Cinnamon,"
	elog "Budgie, LXQt) works out of the box."
}

pkg_postrm() {
	xdg_icon_cache_update
}
