# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# PREBUILT PACKAGING NOTES -- READ BEFORE A VERSION BUMP.
#
# 1) Why a -bin at all, when ::gentoo already has sys-apps/uutils-coreutils:
#    the from-source ebuild pulls ~400 crates and a Rust toolchain.  Upstream
#    publishes official binaries for every release, so users who only want the
#    utilities (containers, edge boxes, arm64 SBCs, machines with no Rust)
#    should not have to compile them.  This package installs exactly the same
#    file layout as the from-source one, so the two are interchangeable.
#
# 2) Why musl builds on arm64/riscv but a glibc build on amd64/x86:
#    upstream ships NO aarch64-*-linux-gnu or riscv64-*-linux-gnu tarball --
#    only *-linux-musl, which is statically linked and therefore runs fine on
#    a glibc system.  On amd64/x86 the glibc build is preferred because a
#    statically linked musl binary resolves users and groups through musl's
#    own minimal NSS: it reads /etc/passwd and /etc/group directly and cannot
#    consult nsswitch.conf modules (LDAP, SSSD, systemd-userdb).  That would
#    silently change the output of `uu-ls -l`, `uu-id` and `uu-chown` on hosts
#    with networked accounts.  Verified glibc floors (objdump -T):
#       x86_64-unknown-linux-gnu -> GLIBC_2.39
#       i686-unknown-linux-gnu   -> GLIBC_2.18
#    Re-check those on a bump; if the floor ever exceeds the oldest glibc in
#    ::gentoo, switch that arch over to its musl tarball.
#
# 3) Why the applet list is derived from the man pages and not from
#    `coreutils --list`:
#    running the payload at build time would break every cross-arch build.
#    docs.tar.zst is architecture independent and carries one man page per
#    applet, so it is the portable source of truth.  Two names in it are NOT
#    multicall applets and are filtered out below: "coreutils" (the multicall
#    binary itself) and "stdbuf" (it needs libstdbuf.so in libexec, which the
#    release tarballs do not ship -- confirmed absent from `coreutils --list`).
#
# 4) Why the completion files are rewritten with sed:
#    upstream generates them for the unprefixed command name ("#compdef ls",
#    "complete -F _ls ... ls") and merely renames the file to uu-ls.  That
#    registers the completion against GNU ls instead of uu-ls.  The seds below
#    retarget them at the installed name.  This is a deliberate improvement
#    over upstream's own install rule, not an oversight.
#
# 5) l10n: translations live in the source tree, not in the binary tarballs.
#    Release builds look them up at <prefix>/share/locales/<applet>, i.e. the
#    very path the source ebuild installs to -- verified at runtime by running
#    the shipped binary against a synthetic prefix.  en-US is compiled into the
#    binary, so only the extra locales are installed.  0.10.0 ships fr-FR only.

# 6) Why src_unpack is overridden:
#    PMS does not list .tar.zst among the suffixes that unpack() understands,
#    not even in EAPI 8, so portage silently skips docs.tar.zst with a mere
#    "=== Skipping unpack" and the man pages never reach ${WORKDIR}.
#    unpacker.eclass knows the format.

inherit bash-completion-r1 optfeature unpacker

MY_PN="${PN%-bin}"
MY_BASE="https://github.com/uutils/coreutils/releases/download/${PV}"

DESCRIPTION="GNU coreutils rewritten in Rust (prebuilt upstream binaries)"
HOMEPAGE="https://uutils.github.io/coreutils/ https://github.com/uutils/coreutils"

SRC_URI="
	amd64? (
		elibc_glibc? ( ${MY_BASE}/coreutils-${PV}-x86_64-unknown-linux-gnu.tar.gz )
		elibc_musl? ( ${MY_BASE}/coreutils-${PV}-x86_64-unknown-linux-musl.tar.gz )
	)
	arm64? ( ${MY_BASE}/coreutils-${PV}-aarch64-unknown-linux-musl.tar.gz )
	riscv? ( ${MY_BASE}/coreutils-${PV}-riscv64gc-unknown-linux-musl.tar.gz )
	x86? (
		elibc_glibc? ( ${MY_BASE}/coreutils-${PV}-i686-unknown-linux-gnu.tar.gz )
		elibc_musl? ( ${MY_BASE}/coreutils-${PV}-i686-unknown-linux-musl.tar.gz )
	)
	${MY_BASE}/docs.tar.zst -> ${MY_PN}-${PV}-docs.tar.zst
	l10n_fr? (
		https://github.com/uutils/coreutils/archive/refs/tags/${PV}.tar.gz
			-> ${MY_PN}-${PV}.tar.gz
	)
"
S="${WORKDIR}"

LICENSE="MIT"
# Dependent crate licenses, statically linked into the payload.  Kept in sync
# with the from-source ebuild -- regenerate with pycargoebuild on a bump.
LICENSE+="
	Apache-2.0 BSD-2 BSD CC0-1.0 ISC MIT MPL-2.0 Unicode-3.0 ZLIB
"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64 ~riscv ~x86"
IUSE="l10n_fr"

RDEPEND="!sys-apps/uutils-coreutils"
BDEPEND="app-arch/zstd"

RESTRICT="strip"
QA_PREBUILT="usr/bin/uu-coreutils"

src_unpack() {
	# See note 6.
	unpacker_src_unpack
}

src_install() {
	local target
	if use amd64 ; then
		target=x86_64-unknown-linux-$(usex elibc_musl musl gnu)
	elif use x86 ; then
		target=i686-unknown-linux-$(usex elibc_musl musl gnu)
	elif use arm64 ; then
		target=aarch64-unknown-linux-musl
	elif use riscv ; then
		target=riscv64gc-unknown-linux-musl
	else
		die "no upstream binary for this arch; use sys-apps/uutils-coreutils instead"
	fi

	local payload="${WORKDIR}/coreutils-${PV}-${target}"

	newbin "${payload}/coreutils" uu-coreutils
	dodoc "${payload}"/README.md

	# See note 3: the man page names are the portable applet list.
	local progs=() prog
	for prog in "${WORKDIR}"/share/man/man1/*.1 ; do
		prog=$(basename "${prog}" .1)
		[[ ${prog} == coreutils || ${prog} == stdbuf ]] && continue
		progs+=( "${prog}" )
	done
	[[ ${#progs[@]} -ge 100 ]] ||
		die "only ${#progs[@]} applets found in docs.tar.zst -- layout changed?"

	# The list already contains `[`, which ships its own man page.
	for prog in "${progs[@]}" ; do
		dosym uu-coreutils /usr/bin/"uu-${prog}"
	done

	doman "${WORKDIR}"/share/man/man1/coreutils.1
	mv "${ED}"/usr/share/man/man1/{,uu-}coreutils.1 || die
	for prog in "${progs[@]}" ; do
		newman "${WORKDIR}/share/man/man1/${prog}.1" "uu-${prog}.1"
	done

	# See note 4: retarget the completions at the uu- prefixed command.
	local esc
	for prog in "${progs[@]}" ; do
		# `[` is a regex metacharacter; escape it for the seds below.
		esc=${prog//\[/\\[}

		if [[ -f ${WORKDIR}/share/bash-completion/completions/${prog}.bash ]] ; then
			sed -e "s/ ${esc}\$/ uu-${prog}/" \
				"${WORKDIR}/share/bash-completion/completions/${prog}.bash" \
				> "${T}/uu-${prog}" || die
			newbashcomp "${T}/uu-${prog}" "uu-${prog}"
		fi

		if [[ -f ${WORKDIR}/share/zsh/site-functions/_${prog} ]] ; then
			sed -e "s/^#compdef ${esc}\$/#compdef uu-${prog}/" \
				-e "s/^\(\s*compdef _${esc}\) ${esc}\$/\1 uu-${prog}/" \
				"${WORKDIR}/share/zsh/site-functions/_${prog}" \
				> "${T}/_uu-${prog}" || die
			insinto /usr/share/zsh/site-functions
			doins "${T}/_uu-${prog}"
		fi

		if [[ -f ${WORKDIR}/share/fish/vendor_completions.d/${prog}.fish ]] ; then
			sed -e "s/^complete -c ${esc}\b/complete -c uu-${prog}/" \
				"${WORKDIR}/share/fish/vendor_completions.d/${prog}.fish" \
				> "${T}/uu-${prog}.fish" || die
			insinto /usr/share/fish/vendor_completions.d
			doins "${T}/uu-${prog}.fish"
		fi
	done

	# See note 5.  uucore holds the strings shared by every applet; the rest
	# are per applet, and only the applets this binary actually carries are
	# installed (the source tree also has locales for stdbuf and runcon).
	if use l10n_fr ; then
		local dir
		for prog in "${progs[@]}" uucore ; do
			dir="${WORKDIR}/coreutils-${PV}/src/uu/${prog}/locales"
			[[ ${prog} == uucore ]] &&
				dir="${WORKDIR}/coreutils-${PV}/src/uucore/locales"
			[[ -f ${dir}/fr-FR.ftl ]] || continue
			insinto "/usr/share/locales/${prog}"
			doins "${dir}"/fr-FR.ftl
		done
	fi
}

pkg_postinst() {
	elog "Every utility is installed with an 'uu-' prefix (uu-ls, uu-cp, ...)"
	elog "so this package does not shadow sys-apps/coreutils.  The multicall"
	elog "binary itself is /usr/bin/uu-coreutils; run 'uu-coreutils --list'"
	elog "for the full set of applets."
	elog
	elog "'stdbuf' is not available here: it needs a helper library that"
	elog "upstream does not ship in the release tarballs.  Build"
	elog "sys-apps/uutils-coreutils from source if you need it."

	if use elibc_glibc && ( use arm64 || use riscv ) ; then
		ewarn "Upstream publishes no glibc binary for this arch, so the"
		ewarn "statically linked musl build was installed.  It resolves users"
		ewarn "and groups from /etc/passwd and /etc/group only -- NSS modules"
		ewarn "such as LDAP, SSSD or systemd-userdb are ignored by uu-ls -l,"
		ewarn "uu-id and uu-chown.  Build sys-apps/uutils-coreutils from source"
		ewarn "if your system uses networked accounts."
	fi

	optfeature "shell completions" app-shells/bash-completion
}
