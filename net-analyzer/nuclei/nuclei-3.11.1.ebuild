# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module

DESCRIPTION="Fast, template-based vulnerability scanner driven by a YAML DSL"
HOMEPAGE="https://github.com/projectdiscovery/nuclei"
SRC_URI="https://github.com/projectdiscovery/nuclei/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
# Vendored dependency tree, generated with `go mod vendor` and hosted by the
# overlay, so the build carries a checksum and needs no network.
SRC_URI+=" https://distfiles.obentoo.org/${P}-vendor.tar.xz"

# nuclei itself is MIT, but it statically links github.com/projectdiscovery/
# ldapserver, which is GPL-2. The resulting binary is therefore effectively
# under the GPL-2, not the MIT the project README advertises. Keep GPL-2 in
# this list until that dependency is relicensed or dropped.
LICENSE="MIT GPL-2"
# Dependent (bundled, statically linked) Go module licenses
LICENSE+=" Apache-2.0 BSD BSD-2 CC0-1.0 ISC LGPL-3 MPL-2.0 Unlicense"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

BDEPEND=">=dev-lang/go-1.26"

# The suite drives live HTTP targets and downloads the template catalogue.
RESTRICT="test"

src_compile() {
	ego build -trimpath -o nuclei ./cmd/nuclei
}

src_install() {
	dobin nuclei
	einstalldocs
}

pkg_postinst() {
	elog "nuclei ships no templates. Fetch the catalogue as the user that"
	elog "will run it:"
	elog ""
	elog "    nuclei -update-templates"
	elog ""
	elog "That writes to ~/.local/nuclei-templates and needs network access."
}
