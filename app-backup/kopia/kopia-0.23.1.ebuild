# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module shell-completion

DESCRIPTION="Fast and secure open-source backup tool with end-to-end encryption"
HOMEPAGE="https://kopia.io/ https://github.com/kopia/kopia"

if [[ ${PV} == 9999 ]]; then
	inherit git-r3
	EGIT_REPO_URI="https://github.com/kopia/kopia.git"
else
	SRC_URI="https://github.com/kopia/kopia/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
	KEYWORDS="~amd64 ~arm64"
	S="${WORKDIR}/${PN}-${PV}"
fi

LICENSE="Apache-2.0"
# Dependent (bundled, statically linked) Go module licenses
LICENSE+=" Apache-2.0 BSD BSD-2 CC0-1.0 ISC MIT MPL-2.0"
SLOT="0"

# webui embeds the kopia server HTML UI (github.com/kopia/htmluibuild). Disable
# for headless/container/edge deployments that only ever run the CLI or the
# server API, producing a smaller binary via the upstream "nohtmlui" build tag.
IUSE="+webui"

# Go modules are downloaded in src_unpack (upstream does not publish a vendor
# tarball), so the network sandbox must be disabled. The test suite spins up
# real repositories/servers and reaches external storage backends, so it is
# restricted.
RESTRICT="network-sandbox test"

# go.mod requires go 1.25.
BDEPEND=">=dev-lang/go-1.25"

src_unpack() {
	if [[ ${PV} == 9999 ]]; then
		git-r3_src_unpack
	else
		default
	fi
	cd "${S}" || die
	ego mod download
}

src_compile() {
	# Mirror upstream's Makefile version injection (repo.BuildVersion drives
	# `kopia --version`). BuildInfo/BuildGitHubRepo are cosmetic build metadata.
	local version_pkg="github.com/kopia/kopia/repo"
	local go_ldflags=(
		-s -w
		-X "${version_pkg}.BuildVersion=${PV}"
		-X "${version_pkg}.BuildInfo=gentoo"
		-X "${version_pkg}.BuildGitHubRepo=kopia/kopia"
	)

	local go_tags=()
	use webui || go_tags+=( nohtmlui )

	ego build -trimpath -o kopia \
		${go_tags:+-tags "${go_tags[*]}"} \
		-ldflags "${go_ldflags[*]}" .

	# kopia uses kingpin, which exposes hidden completion-script generators.
	# HOME is redirected so the binary never touches the real user config.
	HOME="${T}" ./kopia --completion-script-bash > "${PN}.bash" || die
	HOME="${T}" ./kopia --completion-script-zsh > "${PN}.zsh" || die
}

src_install() {
	dobin kopia

	newbashcomp "${PN}.bash" "${PN}"
	newzshcomp "${PN}.zsh" "_${PN}"

	einstalldocs
}
