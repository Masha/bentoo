# ::gentoo commit 4b392d6d5a (2026-10-22) moved LLVM 23 to the prebuilt tarball
# llvm-23.1.4-manpages-r1.tar.xz, which unpacks to llvm-23.1.4-manpages-r1/.
# llvm_install_manpages (llvm.org.eclass) still globs llvm-*-manpages/, so with
# USE=-doc src_install dies in doins on the unexpanded pattern.
#
# Rename the directory to the name the eclass expects. A rename, not a symlink:
# if ::gentoo widens the glob to llvm-*-manpages*/ there is still exactly one
# match, and once the glob already matches this is a no-op. Drop this file and
# its package.bashrc lines when ::gentoo fixes the eclass.
post_src_unpack() {
	local d n
	local -a want=( "${WORKDIR}"/llvm-*-manpages )
	[[ -d ${want[0]} ]] && return 0
	for d in "${WORKDIR}"/llvm-*-manpages-r[0-9]*; do
		[[ -d ${d} ]] || continue
		n=${d##*/}
		mv "${d}" "${d%-r[0-9]*}" || die "bentoo: cannot rename ${n}"
		einfo "bentoo: ${n} renamed to ${n%-r[0-9]*} for llvm_install_manpages"
	done
}
