# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit edo multiprocessing toolchain-funcs

DESCRIPTION="Language server for Lua, written in Lua"
HOMEPAGE="https://luals.github.io/ https://github.com/LuaLS/lua-language-server"
# The -submodules.zip asset carries every git submodule under 3rd/ (luamake,
# bee.lua, lpeglabel, EmmyLuaCodeStyle, the addon API trees); the GitHub
# archive tarball does not, and would leave 3rd/ empty.
SRC_URI="https://github.com/LuaLS/${PN}/releases/download/${PV}/${P}-submodules.zip"
# The zip has no top-level directory.
S="${WORKDIR}"

# MIT: lua-language-server, luamake, bee.lua (+ bundled Lua 5.5, fmt,
# lua-seri), lpeglabel, EmmyLuaCodeStyle.
# Boost-1.0: wildcards (header-only, compiled into the code formatter).
LICENSE="MIT Boost-1.0"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

BDEPEND="
	app-alternatives/ninja
	app-arch/unzip
"

PATCHES=(
	"${FILESDIR}"/${PN}-luamake-toolchain.patch
)

# Rewrite one upstream line, and die if it is no longer there: sed exits 0
# when nothing matches, which would turn a moved line into a silent no-op.
lls_sed() {
	local pattern=${1} replacement=${2} file=${3}
	grep -qF -- "${pattern}" "${file}" ||
		die "upstream no longer has \"${pattern}\" in ${file}; recheck the ebuild"
	sed -i -e "s|${pattern}|${replacement}|" "${file}" || die
}

src_prepare() {
	default

	# Bootstrap build of luamake itself (a build-time tool, never installed).
	lls_sed "cc = gcc" "cc = $(tc-getCC)" 3rd/luamake/compile/ninja/linux.ninja
	lls_sed "ar = ar" "ar = $(tc-getAR)" 3rd/luamake/compile/ninja/linux.ninja

	# Link libstdc++ dynamically; the static CRT only exists so upstream's
	# release binary runs on old glibc distributions.
	lls_sed 'crt = "static",' 'crt = "dynamic",' make.lua

	# -Werror breaks the build on any new compiler warning.
	lls_sed '"-Wall -Werror"' '"-Wall"' make/code_format.lua
}

src_compile() {
	pushd 3rd/luamake >/dev/null || die
	edo ./compile/build.sh -v -j"$(makeopts_jobs)"
	popd >/dev/null || die

	# -notest: the test suite runs in src_test, not as part of the build.
	edo 3rd/luamake/luamake -notest -cc "$(tc-getCC)" -ar "$(tc-getAR)" \
		-v -j "$(makeopts_jobs)"
}

src_test() {
	edo bin/lua-language-server test.lua
}

src_install() {
	# The binary locates main.lua, script/, locale/ and meta/ relative to
	# its own path, so the tree is installed as a unit.
	local dir=/usr/$(get_libdir)/${PN}
	insinto "${dir}"
	# changelog.md is not documentation only: script/version.lua parses it
	# for --version and the LSP serverInfo, and reports "<Unknown>" without it.
	doins -r changelog.md debugger.lua main.lua locale meta script
	exeinto "${dir}"/bin
	doexe bin/${PN}
	insinto "${dir}"/bin
	doins bin/main.lua

	# The install tree is read-only: logs and generated meta files go to a
	# per-user cache. Explicit --logpath/--metapath from the caller still win,
	# because the server keeps the last occurrence of an option.
	cat > "${T}"/${PN} <<-EOF || die
		#!/bin/sh
		cache="\${XDG_CACHE_HOME:-\${HOME}/.cache}/${PN}"
		exec "${EPREFIX}${dir}/bin/${PN}" \\
		    --logpath="\${cache}/log" --metapath="\${cache}/meta" "\$@"
	EOF
	dobin "${T}"/${PN}

	dodoc README.md
}
