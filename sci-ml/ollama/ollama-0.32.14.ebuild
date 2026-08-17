# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cmake go-module systemd

DESCRIPTION="Get up and running with Llama 3, Mistral, Gemma, and other language models"
HOMEPAGE="https://ollama.com"

# Read from LLAMA_CPP_VERSION at the root of the v${PV} tag, never chosen
# freely: llama/server/CMakeLists.txt reads that file to pin the FetchContent
# revision. The autoupdate applier only rewrites PV, so this has to be resynced
# by hand on every bump.
LLAMA_CPP_tag=b10380

# gentoo-golang-dist packages the Go dependencies roughly a day after upstream
# tags, so v${PV} 404s on release day. v${MY_DEPS_PV} carries the same module
# set: go.mod and go.sum are byte-identical between the two tags. Retarget this
# at v${PV} once the mirror catches up.
MY_DEPS_PV="0.32.8"

SRC_URI="
	https://github.com/ollama/${PN}/archive/refs/tags/v${PV}.tar.gz -> ${P}.gh.tar.gz
	https://github.com/gentoo-golang-dist/${PN}/releases/download/v${MY_DEPS_PV}/${PN}-${MY_DEPS_PV}-deps.tar.xz
	https://github.com/ggml-org/llama.cpp/archive/refs/tags/${LLAMA_CPP_tag}.tar.gz
		-> llama.cpp-${LLAMA_CPP_tag}.tar.gz
"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"

RESTRICT="mirror test"

# The ceiling on sci-ml/ggml is load-bearing, not cosmetic. src_configure sets
# LLAMA_USE_SYSTEM_GGML=ON, so the vendored llama.cpp compiles against the
# system headers: ggml-0.20.0 added a trailing "int64_t K" to ggml_ssm_scan,
# while llama.cpp b10380 still calls it with eight arguments. Without the
# ceiling the solver pulls 0.20.0 and llama-model-loader.cpp fails to compile
# (obentoo/bentoo#40). Raise it once LLAMA_CPP_tag reaches a revision that
# carries the new arity -- b10448 already does.
DEPEND="
	acct-group/ollama
	acct-user/ollama
	>=sci-ml/ggml-0.17
	<sci-ml/ggml-0.20.0
"
# sci-ml/ollama-bin is the same program obtained the other way, and the two
# install four of the same paths: /usr/bin/ollama (a real binary here, a
# symlink into /opt there), /etc/init.d/ollama, /etc/conf.d/ollama and
# /usr/lib/systemd/system/ollama.service. The libraries do not clash --
# /usr/lib/ollama here against /opt/ollama/lib there -- but the four above are
# enough for collision-protect to abort the merge.
#
# Hard blocker, symmetric, matching sci-libs/onnxruntime{,-bin} and
# sci-ml/lemonade{,-bin}: portage has no ordering that resolves this, since
# neither package is an upgrade path for the other. One must be unmerged.
RDEPEND="
	${DEPEND}
	!!sci-ml/ollama-bin
	net-misc/curl:=
"
BDEPEND="
	>=dev-lang/go-1.26.0
	dev-libs/stb
"

PATCHES=(
	"${FILESDIR}"/${PN}-0.31.1-ggml.patch
	"${FILESDIR}"/${PN}-0.31.1-cmake.patch
)

src_prepare() {
	cmake_src_prepare

	local llama_src="${BUILD_DIR}/_deps/llama_cpp-src"
	local llama_patch_dir="${WORKDIR}/${P}/llama/compat"

	mkdir -p "${BUILD_DIR}"/_deps || die

	ln -s "${WORKDIR}"/llama.cpp-${LLAMA_CPP_tag} "${llama_src}" || die

	# Switch to the llama.cpp source directory
	pushd "${llama_src}" > /dev/null || die
	eapply "${llama_patch_dir}"/*.patch \
		"${llama_patch_dir}"/models/*.patch \
		"${FILESDIR}"/${PN}-0.31.1-gcc17.patch

	# Remove vendored
	rm -r vendor/stb || die
	popd > /dev/null || die
}

src_configure() {
	# Configure Embedded local Server
	local llama_src="${BUILD_DIR}/_deps/llama_cpp-src"
	local mycmakeargs=(
		-DCMAKE_INSTALL_PREFIX="${BUILD_DIR}"
		-DOLLAMA_RUNNER_DIR=""
		-DFETCHCONTENT_SOURCE_DIR_LLAMA_CPP="${llama_src}"
		-DOLLAMA_LLAMA_CPP_SKIP_COMPAT_PATCH=ON
		-DBUILD_SHARED_LIBS=ON
		-DLLAMA_USE_SYSTEM_GGML=ON
	)
	local CMAKE_USE_DIR="${S}/llama/server"
	local BUILD_DIR="${BUILD_DIR}/llama-server-local"
	cmake_src_configure
}

src_compile() {
	local SAVE_BUILD_DIR="${BUILD_DIR}"

	# Compile Embedded Local Server
	local BUILD_DIR="${BUILD_DIR}"/llama-server-local
	local cmake_src_compile_opts=(
		--target llama-server
		--target llama-quantize
	)
	cmake_src_compile

	# Install/Stage Local Server Component
	"${CMAKE_BINARY}" \
		--install "${BUILD_DIR}" \
		--prefix "${SAVE_BUILD_DIR}" \
		--component llama-server \
		|| die "Failed to stage server component"

	# Expose CGO to Go and establish compiler optimization paths
	export CGO_ENABLED=1

	# Replicate the linker flags dynamically from your ebuild version
	local mygoldflags="-X github.com/ollama/ollama/version.Version=${PV} \
		-X github.com/ollama/ollama/server.mode=release"

	# Call the Go build engine natively with standard Gentoo flags
	ego build \
		-trimpath \
		-ldflags "${mygoldflags}" \
		-o "${BUILD_DIR}/ollama" \
		. || die "Go build failed"
}

src_install() {
	dobin "${BUILD_DIR}"/llama-server-local/ollama
	insinto usr
	doins -r "${BUILD_DIR}"/lib
	fperms -R +x /usr/lib/ollama

	einstalldocs

	newinitd "${FILESDIR}/ollama.init" "${PN}"
	newconfd "${FILESDIR}/ollama.confd" "${PN}"

	systemd_dounit "${FILESDIR}/ollama.service"
}

pkg_preinst() {
	keepdir /var/log/ollama
	fperms 750 /var/log/ollama
	fowners "${PN}:${PN}" /var/log/ollama
}

pkg_postinst() {
	if [[ -z ${REPLACING_VERSIONS} ]] ; then
		einfo "Quick guide:"
		einfo "\tollama serve"
		einfo "\tollama run llama3:70b"
		einfo
		einfo "See available models at https://ollama.com/library"
	fi

	einfo
	einfo "Ollama binds 127.0.0.1 port 11434 by default."
	einfo "Change the bind address with the OLLAMA_HOST environment variable."
	einfo "See https://docs.ollama.com/faq for more info"
	einfo
}
