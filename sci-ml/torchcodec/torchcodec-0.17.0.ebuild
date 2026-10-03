# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=scikit-build-core
DISTUTILS_SINGLE_IMPL=1
DISTUTILS_EXT=1
PYTHON_COMPAT=( python3_{12..14} )

inherit cuda distutils-r1

DESCRIPTION="Decode and encode video, audio and images into PyTorch tensors via FFmpeg"
HOMEPAGE="
	https://github.com/meta-pytorch/torchcodec
	https://pypi.org/project/torchcodec/
"
SRC_URI="
	https://github.com/meta-pytorch/torchcodec/archive/refs/tags/v${PV}.tar.gz
		-> ${P}.gh.tar.gz
"

# USE=gif compiles a vendored giflib 5.2.2 decoder (src/torchcodec/_core/giflib)
# that media-libs/giflib security updates never reach.
LICENSE="BSD gif? ( MIT )"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
# No ROCm flag: upstream has no HIP backend. On a ROCm pytorch the CPU decoders
# are used and the tensors are moved to the GPU by torch itself.
IUSE="cuda +gif heif +jpeg +png +webp"

# FFmpeg is found through pkg-config and mapped from the libavcodec major;
# ffmpeg_versions.cmake accepts FFmpeg 4 through 9 and stops at FATAL_ERROR
# beyond that. The libraries build against torch's stable ABI
# (TORCH_TARGET_VERSION 2.11), so a pytorch upgrade does not need a rebuild and
# a floor is enough; it is 2.13, the first pytorch carrying the cuda flag
# itself (2.12 still split it out to sci-ml/caffe2).
RDEPEND="
	<media-video/ffmpeg-10:=
	>=sci-ml/pytorch-2.13[${PYTHON_SINGLE_USEDEP},cuda?]
	cuda? ( dev-util/nvidia-cuda-toolkit:= )
	heif? ( media-libs/libheif:= )
	jpeg? ( media-libs/libjpeg-turbo:= )
	png? ( media-libs/libpng:= )
	webp? ( media-libs/libwebp:= )
"
DEPEND="${RDEPEND}"
BDEPEND="
	$(python_gen_cond_dep '
		dev-python/pybind11[${PYTHON_USEDEP}]
	')
	virtual/pkgconfig
"

# The test suite decodes a media corpus that upstream fetches separately.
RESTRICT="test"

src_prepare() {
	use cuda && cuda_src_prepare
	distutils-r1_src_prepare
}

python_compile() {
	# CMakeLists.txt runs "import torch" to find Torch_DIR, which probes the
	# GPU and the entropy pool (bug #968112, same as sci-ml/torchvision).
	addpredict /dev/kfd
	addpredict /dev/random

	# Any of these in the caller's environment redirects the build: the first
	# (even empty) downloads six FFmpeg builds from S3, the others point the
	# image codecs at a user-writable prefix.
	unset BUILD_AGAINST_ALL_FFMPEG_FROM_S3 CONDA_PREFIX HOMEBREW_PREFIX
	# The version provider asks git; never let it read an enclosing checkout.
	export GIT_CEILING_DIRECTORIES="${WORKDIR}"

	# scikit-build-core maps these to CMake definitions (pyproject.toml); the
	# version provider honors BUILD_VERSION instead of asking git.
	export BUILD_VERSION="${PV}"
	export TORCHCODEC_DISABLE_COMPILE_WARNING_AS_ERROR=ON

	# Upstream refuses to build a wheel against a system FFmpeg unless told
	# otherwise. This is not a self-contained wheel: FFmpeg is only linked,
	# and its license travels with media-video/ffmpeg.
	export I_CONFIRM_THIS_IS_NOT_A_LICENSE_VIOLATION=1

	# AVIF is the only image codec upstream downloads (libavif from S3 at
	# configure time, fetch_avif_from_s3.cmake) instead of finding a system
	# library, so it stays off; decode_avif then raises at call time.
	export TORCHCODEC_BUILD_AVIF=OFF
	export TORCHCODEC_BUILD_GIF=$(usex gif ON OFF)
	export TORCHCODEC_BUILD_HEIC=$(usex heif ON OFF)
	export TORCHCODEC_BUILD_JPEG=$(usex jpeg ON OFF)
	export TORCHCODEC_BUILD_PNG=$(usex png ON OFF)
	export TORCHCODEC_BUILD_WEBP=$(usex webp ON OFF)
	export TORCHCODEC_BUILD_NVJPEG=$(usex cuda ON OFF)

	if use cuda; then
		export ENABLE_CUDA=1
		addpredict /dev/nvidiactl
		if [[ -z ${TORCH_CUDA_ARCH_LIST} ]]; then
			ewarn "TORCH_CUDA_ARCH_LIST is unset: building for compute capability"
			ewarn "7.5 plus PTX, which the driver JIT-compiles for newer GPUs."
			ewarn "Set TORCH_CUDA_ARCH_LIST through package.env to target yours."
		fi
		export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-7.5+PTX}"
	else
		export ENABLE_CUDA=
	fi

	distutils-r1_python_compile
}
