# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{12..15} )

inherit python-single-r1

# Build timestamp of the milestone tarball. It is part of the distfile name and
# is not derivable from ${PV}: read it from
# https://download.eclipse.org/jdtls/milestones/${PV}/latest.txt on every bump.
MY_BUILD="202609031315"

DESCRIPTION="Eclipse JDT Language Server, a Java language server (LSP)"
HOMEPAGE="https://github.com/eclipse-jdtls/eclipse.jdt.ls"
SRC_URI="https://download.eclipse.org/jdtls/milestones/${PV}/jdt-language-server-${PV}-${MY_BUILD}.tar.gz"
S="${WORKDIR}"

# EPL-2.0 for jdt.ls and the Eclipse platform bundles; the rest covers the
# third-party jars bundled in plugins/ (Bundle-License survey of 1.61.0):
#   Apache-2.0      gson, guava, commons-*, felix.scr, aries.spifly, ant,
#                   jakarta.inject, org.osgi.*, gradle tooling API, maven
#                   runtime, fernflower decompiler, jetbrains annotations
#   BSD             asm, hamcrest
#   BSD-2           commonmark, flexmark
#   EPL-1.0         junit 4, m2e.workspace.cli
#   MIT             slf4j, jsoup
#   EPL-2.0 or GPL-2 with Classpath exception: jakarta.annotation/servlet
#   EPL-1.0 or LGPL-2.1: logback
#   Apache-2.0 or LGPL-2.1+: JNA
LICENSE="EPL-2.0 Apache-2.0 BSD BSD-2 EPL-1.0 MIT
	|| ( EPL-1.0 LGPL-2.1 )
	|| ( Apache-2.0 LGPL-2.1+ )
	|| ( EPL-2.0 GPL-2-with-classpath-exception )
"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
REQUIRED_USE="${PYTHON_REQUIRED_USE}"

RDEPEND="
	${PYTHON_DEPS}
	>=virtual/jre-21:*
"

PATCHES=(
	# Per-user OSGi configuration area under ~/.cache/jdtls (the install
	# tree is read-only) and config_linux_arm on aarch64.
	"${FILESDIR}/${PN}-launcher-config.patch"
)

src_install() {
	insinto /usr/share/${PN}
	# Only the Linux shared configurations; the macOS/Windows ones are dead
	# weight. Both Linux arches are kept: they are plain text, and the
	# launcher picks one at run time.
	doins -r features plugins \
		config_linux config_linux_arm config_ss_linux config_ss_linux_arm

	insinto /usr/share/${PN}/bin
	doins bin/jdtls.py
	exeinto /usr/share/${PN}/bin
	doexe bin/jdtls
	python_fix_shebang "${ED}"/usr/share/${PN}/bin/jdtls

	# bin/jdtls resolves its own realpath to find jdtls.py and the install
	# root, so a symlink is enough.
	dosym -r /usr/share/${PN}/bin/jdtls /usr/bin/jdtls
}

pkg_postinst() {
	elog "jdtls needs a Java 21 or newer runtime. It uses \${JAVA_HOME}/bin/java"
	elog "when JAVA_HOME is set, otherwise the 'java' selected by eselect java-vm;"
	elog "--java-executable=<path> overrides both."
	elog
	elog "Per-user state lives under \${XDG_CACHE_HOME:-~/.cache}/jdtls: the OSGi"
	elog "configuration area (config_linux*) and one workspace per project"
	elog "(jdtls-<hash>). Pass -configuration / -data to relocate them."
}
