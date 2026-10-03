# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{12..14} )
DISTUTILS_SINGLE_IMPL=1
DISTUTILS_USE_PEP517=setuptools
DISTUTILS_EXT=1
inherit cuda distutils-r1 multiprocessing

DESCRIPTION="Audio signal processing, transforms and models for PyTorch"
HOMEPAGE="https://github.com/pytorch/audio"
SRC_URI="
	https://github.com/pytorch/audio/archive/refs/tags/v${PV}.tar.gz
		-> ${P}.gh.tar.gz
"
S="${WORKDIR}/audio-${PV}"

LICENSE="BSD-2 cuda? ( BSD Apache-2.0 )"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
# No ROCm flag: tools/setup_helpers/extension.py reads USE_ROCM but only
# USE_CUDA switches to CUDAExtension, so a ROCm pytorch gets the same C++
# extension as a CPU one and the GPU work is done by torch itself.
IUSE="cuda"

# Upstream is in maintenance mode and 2.11.0 is its last release; it has no
# version pin on torch (setup.py dropped install_requires) and builds against
# torch's stable ABI (TORCH_TARGET_VERSION 2.10, py_limited_api), so a pytorch
# upgrade does not need a rebuild and a floor is enough. The floor is 2.13,
# the first pytorch carrying the cuda flag itself (2.12 still split it out to
# sci-ml/caffe2). load()/save() are thin wrappers over torchcodec
# (src/torchaudio/_torchcodec.py), so it is a hard dependency.
RDEPEND="
	>=sci-ml/pytorch-2.13[${PYTHON_SINGLE_USEDEP},cuda?]
	sci-ml/torchcodec[${PYTHON_SINGLE_USEDEP},cuda?]
	$(python_gen_cond_dep '
		dev-python/numpy[${PYTHON_USEDEP}]
	')
"
DEPEND="${RDEPEND}"

# The suite needs librosa, a model download and a media corpus.
RESTRICT="test"

src_prepare() {
	use cuda && cuda_src_prepare
	distutils-r1_src_prepare
}

python_compile() {
	# Importing torch probes the GPU and the entropy pool at build time.
	addpredict /dev/kfd
	addpredict /dev/random

	# setup.py records "git rev-parse HEAD" in version.py.
	export GIT_CEILING_DIRECTORIES="${WORKDIR}"

	# Pin every switch tools/setup_helpers/extension.py reads, so the
	# caller's environment cannot change what gets built.
	export BUILD_VERSION="${PV}"
	export BUILD_ALIGN=1
	export BUILD_CPP_TEST=0
	export BUILD_RNNT=1
	export USE_CUDA=$(usex cuda 1 0)
	export USE_ROCM=0
	export USE_OPENMP=1
	export BUILD_CUDA_CTC_DECODER=$(usex cuda 1 0)

	if use cuda; then
		addpredict /dev/nvidiactl
		if [[ -z ${TORCH_CUDA_ARCH_LIST} ]]; then
			ewarn "TORCH_CUDA_ARCH_LIST is unset: building for compute capability"
			ewarn "7.5 plus PTX, which the driver JIT-compiles for newer GPUs."
			ewarn "Set TORCH_CUDA_ARCH_LIST through package.env to target yours."
		fi
		export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-7.5+PTX}"
	fi

	MAX_JOBS="$(get_makeopts_jobs)" \
		distutils-r1_python_compile -j1
}
