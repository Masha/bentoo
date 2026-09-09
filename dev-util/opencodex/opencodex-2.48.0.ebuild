# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# opencodex is TypeScript executed DIRECTLY by the Bun runtime -- there is no
# compile step for src/, so this package builds nothing and installs the tree
# as upstream ships it.
#
# Two ways to launch it exist and this package deliberately uses the second:
#
#   1. bin/ocx.mjs, a Node shim that locates a Bun and spawns it.
#   2. Bun straight at src/cli/index.ts.
#
# (2) buys two things at once.  It drops net-libs/nodejs from the dependency
# graph entirely, and it makes `ocx update` detect an "installed via source"
# layout, at which point it REFUSES to self-update instead of writing an npm
# tree into /usr.  That refusal is upstream behaviour, not a patch:
#
#   opencodex v2.48.0 (installed via source, tag latest)
#   Running from a source checkout -- update with: ...
#
# src_prepare only rewrites the ADVICE in that message to name Portage.
#
# bin/ is still installed even though it is not an entry point: src/update/
# stats <pkg-root>/bin/ocx.mjs (job.ts, transactional-install.mjs), so deleting
# the directory would change code paths for no gain.  What is NOT installed is
# assets/ -- 5 MiB of README screenshots with no runtime reader.

# The @napi-rs/keyring native package version, which is NOT ${PV} and must not
# be made to follow it on a bump.  It comes from upstream's package.json
# ("@napi-rs/keyring": "1.3.0") and moves on its own schedule.
KEYRING_PV="1.3.0"

# --- vendored runtime tree ---------------------------------------------------
#
# REGENERATING THE DISTFILES ON A BUMP.  Neither obentoo tarball is produced by
# upstream or by any CI, so a bump that skips this fails at fetch time.  From a
# directory holding upstream's package.json + bun.lock at tag v${PV}:
#
#   bun install --frozen-lockfile --production --ignore-scripts
#   rm -rf node_modules/{bun,@oven} node_modules/.bin/{bun,bunx}
#   rm -rf node_modules/@napi-rs/keyring-linux-*
#   tar --sort=name --owner=0 --group=0 --numeric-owner --mtime=@0 --format=gnu \
#       -cf - node_modules | xz -9e -T0 > ${PN}-node_modules-${PV}.tar.xz
#   npx --yes wrangler@latest r2 object put "obentoo-distfiles/<name>" \
#       --file=<path> --content-type=application/x-xz --remote
#
# and the same put for each keyring-linux-*-gnu directory, tarred on its own.
#
# Three things in that recipe are load-bearing and none of them is obvious:
#
#   * bun.lock -- NOT package-lock.json -- is the pin.  `--frozen-lockfile` is
#     what makes the tree reproducible from the tag; without it bun re-resolves
#     the ranges in package.json and the result depends on the day it ran.
#   * @oven/bun-* is ~149 MiB of Bun runtime that gets dropped ON PURPOSE.  The
#     runtime comes from net-libs/bun-bin, and vendoring a second copy would
#     ship an unmanaged, unpatched interpreter inside /usr/lib.
#   * `--remote` on wrangler decides whether the upload happens at all.
#     Without it wrangler writes to LOCAL dev storage, still prints "Upload
#     complete", and the object never reaches the bucket -- so the next fetch
#     404s with nothing in the transcript to explain why.
#
# The npm tarball is used instead of the GitHub tag tarball because only the
# npm one carries gui/dist, the Vite-built web UI.  The tag would force a
# networked `bun install` plus a Vite build inside the gui/ workspace.
NODE_MODULES_TARBALL="${PN}-node_modules-${PV}.tar.xz"

DESCRIPTION="Universal provider proxy: any LLM with Codex CLI/App/SDK and Claude Code"
HOMEPAGE="https://lidge-jun.github.io/opencodex/ https://github.com/lidge-jun/opencodex"
# No "-> ${P}.tgz" rename on the registry URL: its basename already IS
# opencodex-<PV>.tgz, so the rename would be a no-op -- and a no-op rename
# is a pkgcheck RedundantUriRename.  The comment lives out here rather than
# inside the string because SRC_URI is parsed as a depset, where a "#" is a
# token and not a comment: `bash -n` would still pass while the depset broke.
SRC_URI="
	https://registry.npmjs.org/@bitkyc08/${PN}/-/${P}.tgz
	https://distfiles.obentoo.org/${NODE_MODULES_TARBALL}
	keyring? (
		amd64? ( https://distfiles.obentoo.org/${PN}-keyring-${KEYRING_PV}-linux-x64-gnu.tar.xz )
		arm64? ( https://distfiles.obentoo.org/${PN}-keyring-${KEYRING_PV}-linux-arm64-gnu.tar.xz )
	)
"
S="${WORKDIR}/package"

# opencodex itself is MIT, and so is @napi-rs/keyring.
#
# VENDORED SURVEY -- redone across all 93 packages in the node_modules tarball
# for 2.48.0: 83 MIT, 8 ISC, 2 BSD-3-Clause, 1 BSD-2-Clause, 1 declared
# "(Apache-2.0 AND BSD-3-Clause)".  The 5 packages carrying no `license` field
# at all are zod sub-entrypoint stubs, and zod is MIT.  gui/dist bundles only
# React 19, react-dom and @tanstack/react-virtual -- all MIT.
#
# REDO THIS ON EVERY BUMP.  The autoupdate machinery bumps ${PV} and the
# vendored set changes underneath it with nothing here going red; this overlay
# has already been bitten by a vendored-license list going quietly stale.
LICENSE="MIT ISC BSD BSD-2 Apache-2.0"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
IUSE="+keyring"

# No REQUIRED_USE on purpose.  A `^^ ( ... )` group with no default kills
# emerge outright on a headless machine, and nothing here needs one: with
# USE=-keyring the CLI simply has no OS-keychain backend and stores keys in its
# own config, which is a working configuration rather than an invalid one.

# net-libs/bun-bin is the whole runtime dependency, and NOT net-libs/nodejs:
# the wrapper execs Bun directly on the TypeScript, so Node never runs.
RDEPEND="net-libs/bun-bin"

# The only native object in the image is the keyring .node blob, and it exists
# only under USE=keyring -- which is precisely the point of the flag: with
# -keyring this package ships zero prebuilt binaries and both variables below
# describe an empty set.  That is why they are unconditional rather than gated
# in pkg_setup: QA_PREBUILT is a path WHITELIST, so a glob matching nothing is
# silently fine, and gating it would trade a harmless no-op for a whole extra
# phase whose value has to survive Portage's inter-phase environment save.
RESTRICT="strip"
QA_PREBUILT="usr/lib/${PN}/node_modules/@napi-rs/keyring-linux-*-gnu/*.node"

DOCS=( README.md AGENTS_INSTALL.md )

src_prepare() {
	default

	# `ocx update` already refuses to touch a source-layout install; only the
	# ADVICE it prints is wrong for us, naming a git checkout the user does
	# not have.  Point it at Portage instead.
	#
	# Both seds are guarded with `grep -qF` first because sed exits 0 when its
	# pattern matches nothing: an unguarded rewrite would go on "succeeding"
	# silently the moment upstream reworded the line, and the wrong advice
	# would ship again with no signal anywhere.
	local old_msg="Running from a source checkout — update with:  git pull && bun install"
	local new_msg="Installed by Portage — update with:  emerge --ask --update dev-util/opencodex"
	grep -qF "${old_msg}" src/update/index.ts \
		|| die "src/update/index.ts no longer prints the source-checkout advice; recheck this sed"
	sed -i "s|${old_msg}|${new_msg}|" src/update/index.ts || die

	# The same advice reaches the GUI and `ocx update --check` through
	# manualSourceCommand() in src/update/job.ts.  For a source install
	# latestVersion() returns null, so this string is only ever DISPLAYED,
	# never executed -- but it is displayed, so it has to be right too.
	grep -qF 'return "git pull && bun install && bun run build:gui";' src/update/job.ts \
		|| die "src/update/job.ts manualSourceCommand() changed; recheck this sed"
	sed -i \
		's|return "git pull && bun install && bun run build:gui";|return "emerge --ask --update dev-util/opencodex";|' \
		src/update/job.ts || die
}

src_install() {
	local dest="/usr/lib/${PN}"

	dodir "${dest}"

	# cp -a rather than doins -r, and that is not a style preference:
	# node_modules/.bin holds relative SYMLINKS (node-which -> ../which/bin/
	# node-which) which doins dereferences, and the tree carries executable
	# bits that doins would flatten to 0644.
	cp -a "${S}"/src "${S}"/bin "${S}"/gui "${S}"/package.json \
		"${ED}${dest}"/ || die
	cp -a "${WORKDIR}"/node_modules "${ED}${dest}"/ || die

	if use keyring; then
		# @napi-rs/keyring's loader require()s the platform package as a
		# SIBLING under node_modules/@napi-rs/, so the tarball's directory
		# has to land there rather than anywhere else.
		local triple
		if use amd64; then
			triple="x64"
		elif use arm64; then
			triple="arm64"
		else
			die "USE=keyring on an arch with no prebuilt @napi-rs/keyring"
		fi
		cp -a "${WORKDIR}/keyring-linux-${triple}-gnu" \
			"${ED}${dest}"/node_modules/@napi-rs/ || die
	fi

	# Upstream's package.json declares both `opencodex` and `ocx`, so both
	# names exist.  The wrapper execs Bun on an absolute path and never reads
	# $0, so the second name is a plain symlink.
	newbin "${FILESDIR}"/${PN}-wrapper.sh ${PN}
	dosym ${PN} /usr/bin/ocx

	# User-scope OpenRC service.  `ocx service install` writes a user-scope
	# systemd unit AT RUNTIME, so this ebuild installs no unit and the
	# overlay's "every daemon needs an OpenRC counterpart" rule is not
	# triggered by an installed file -- but someone without systemd still has
	# no supervised way to run the proxy, which is the situation that rule
	# exists to prevent.  newinitd has no user-scope variant; installing it as
	# a plain executable follows sys-apps/xdg-desktop-portal and
	# sci-ml/lemonade-bin in this overlay.
	exeinto /etc/user/init.d
	newexe "${FILESDIR}"/${PN}-user.initd ${PN}

	einstalldocs
}

pkg_postinst() {
	elog "opencodex proxies Codex CLI/App/SDK and Claude Code onto any LLM"
	elog "backend.  First run:"
	elog
	elog "    ocx setup      # pick providers and store credentials"
	elog "    ocx start      # proxy on 127.0.0.1:10100"
	elog
	elog "Supervised in your own session, without systemd:"
	elog
	elog "    rc-service --user ${PN} start"
	elog
	if use keyring; then
		elog "USE=keyring is on, so credentials can go to the OS keyring."
		elog "That needs a running Secret Service provider on the session bus"
		elog "(gnome-keyring, KWallet or KeePassXC).  There is no package"
		elog "dependency to express this: the native blob links only glibc and"
		elog "libgcc and talks org.freedesktop.secrets over D-Bus with the"
		elog "client embedded, so the requirement is a runtime one.  Without a"
		elog "provider, keyring reads and writes fail while everything else in"
		elog "opencodex keeps working."
		elog
	fi
	elog "\`ocx update\` is disabled by design in this package -- it detects the"
	elog "source layout and declines to write into /usr.  Update through"
	elog "Portage instead."
}
