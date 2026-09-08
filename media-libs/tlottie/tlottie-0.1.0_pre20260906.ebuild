# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Every crate in Cargo.lock, not just the ones this build compiles.  With
# --features c-api only "cpu" is active, so hashbrown, dlmalloc and the
# windows-* pair are never built -- but cargo resolves the whole lock before
# it filters by target or feature, and --offline then wants each one present
# in the vendor directory.
CRATES="
	cfg-if@1.0.4
	dlmalloc@0.2.14
	foldhash@0.1.5
	hashbrown@0.15.5
	libc@0.2.189
	windows-link@0.2.1
	windows-sys@0.61.2
"

# src/renderer/cpu/simd/avx512.rs uses the x86 AVX-512 intrinsics, stable only
# since 1.89.  1.96.1 is the exact toolchain upstream builds with
# (Telegram/build/docker/centos_env/Dockerfile in the tdesktop tarball); no
# lower version is claimed to work anywhere, so the floor follows the pin
# rather than the intrinsic.
RUST_MIN_VER="1.96.1"

inherit cargo

# NOT "the newest commit".  Telegram Desktop pins this exact revision in
# Telegram/build/prepare/prepare.py (stage 'tlottie') and links the archive
# statically, so the pair moves together: bump this only when a tdesktop
# release asks for a different commit, and revbump telegram-desktop with it.
EGIT_COMMIT="758c7cb74444f1c3c9923065c40fdb3aad8b7d60"

DESCRIPTION="Rust library for drawing Lottie animations, used by Telegram Desktop"
HOMEPAGE="https://github.com/dkaraush/tlottie"
SRC_URI="
	https://github.com/dkaraush/tlottie/archive/${EGIT_COMMIT}.tar.gz -> ${P}.tar.gz
	${CARGO_CRATE_URIS}
"
S="${WORKDIR}/${PN}-${EGIT_COMMIT}"

# MIT is declared in Cargo.toml; the repository ships no LICENSE file and no
# per-file headers, so the manifest is the whole of the grant.
# Apache-2.0/ZLIB cover the vendored crates, which are distributed even though
# they are not compiled here.
LICENSE="MIT Apache-2.0 ZLIB"
SLOT="0"
# neon.rs alongside the x86 SIMD backends: upstream supports arm64 first-class.
KEYWORDS="~amd64 ~arm64"

src_compile() {
	# cargo_src_compile cannot express this: the C API lives behind a
	# non-default feature, and the archive type has to override the
	# rlib/cdylib pair declared in Cargo.toml.  This is upstream's own Linux
	# recipe, verbatim from the centos_env Dockerfile.
	# --print native-static-libs is not decorative -- it records in the build
	# log what the Rust runtime inside the archive expects the C++ side to
	# resolve at link time.
	cargo_env "${CARGO}" rustc --lib --release --locked \
		--features c-api --crate-type staticlib \
		-- --print native-static-libs || die "cargo rustc failed"
}

src_install() {
	dolib.a "$(cargo_target_dir)"/libtlottie.a

	# tdesktop resolves the header with
	#   find_path(... tlottie.h PATH_SUFFIXES tlottie)
	# and adds the result to its include path, so the header must sit in a
	# directory of its own and be reached as <tlottie.h>, not <tlottie/tlottie.h>.
	insinto /usr/include/tlottie
	doins include/tlottie.h

	dodoc README.md
}
