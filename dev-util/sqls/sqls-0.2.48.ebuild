# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module

DESCRIPTION="SQL language server (MySQL, PostgreSQL, SQLite, MSSQL, Oracle, ClickHouse...)"
HOMEPAGE="https://github.com/sqls-server/sqls"
SRC_URI="https://github.com/sqls-server/sqls/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
# Vendored dependency tree, generated with `go mod vendor` and hosted by the
# overlay (see scripts/go-vendor.sh). It carries a checksum in the Manifest, so
# the build needs no network and stays inside the sandbox.
SRC_URI+=" https://distfiles.obentoo.org/${P}-vendor.tar.xz"

LICENSE="MIT"
# Dependent (bundled, statically linked) Go module licenses, surveyed from the
# modules `go version -m` lists for the built binary. godror's bundled ODPI-C is
# UPL-1.0 OR Apache-2.0, already covered by Apache-2.0.
LICENSE+=" Apache-2.0 BSD BSD-2 MPL-2.0"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

# go-sqlite3 links the system SQLite (-tags libsqlite3) instead of its bundled
# amalgamation. The Oracle driver (godror) needs cgo too, but loads the Oracle
# client library with dlopen only when an Oracle connection is configured.
DEPEND="dev-db/sqlite:3"
RDEPEND="${DEPEND}"
BDEPEND=">=dev-lang/go-1.25.0"

src_compile() {
	# The version is a constant in main.go; only the revision is left for
	# -ldflags, and a tarball build has no commit to report.
	ego build -trimpath -tags libsqlite3 -o sqls .
}

src_test() {
	ego test -tags libsqlite3 ./...
}

src_install() {
	dobin sqls
	dodoc README.md
}
