# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

USE_RUBY="ruby32 ruby33 ruby34 ruby40"

# The gem ships neither tests nor a Rakefile.
RUBY_FAKEGEM_EXTRADOC="README.md"
RUBY_FAKEGEM_RECIPE_DOC="none"
RUBY_FAKEGEM_RECIPE_TEST="none"

inherit ruby-fakegem

DESCRIPTION="Language Server Protocol SDK for Ruby"
HOMEPAGE="https://github.com/mtsmfm/language_server-protocol-ruby"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
