# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

USE_RUBY="ruby32 ruby33 ruby34 ruby40"

# Wrap every executable the gemspec declares (ruby-lsp, ruby-lsp-check,
# ruby-lsp-launcher, ruby-lsp-test-exec); the default "*" does exactly that.
RUBY_FAKEGEM_BINDIR="exe"
RUBY_FAKEGEM_EXTRADOC="README.md"
# lib/ruby-lsp.rb reads ../VERSION at load time and lib/ruby_lsp/static_docs.rb
# serves files from ../static_docs; without them the server cannot start.
RUBY_FAKEGEM_EXTRAINSTALL="VERSION static_docs"
RUBY_FAKEGEM_RECIPE_DOC="none"
# The gem ships no test suite; the upstream one needs a large development
# bundle (minitest-reporters, mocha, rubocop, sorbet, syntax_tree...).
RUBY_FAKEGEM_RECIPE_TEST="none"

inherit ruby-fakegem

DESCRIPTION="Opinionated language server for Ruby"
HOMEPAGE="https://shopify.github.io/ruby-lsp/ https://github.com/Shopify/ruby-lsp"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

# Ranges mirror the gemspec: language_server-protocol ~> 3.17.0,
# prism >= 1.2 < 2.0, rbs >= 3 < 5. bundler is required at runtime: the
# server composes a bundle under .ruby-lsp/ and re-execs through it.
ruby_add_rdepend "
	dev-ruby/bundler
	=dev-ruby/language_server-protocol-3.17*
	>=dev-ruby/prism-1.2:1
	>=dev-ruby/rbs-3:0
	<dev-ruby/rbs-5:0
"

pkg_postinst() {
	elog "In a project without its own Gemfile, ruby-lsp writes .ruby-lsp/Gemfile"
	elog "and runs 'bundle install' against rubygems.org. Bundler resolves the"
	elog "newest versions from the remote index, not the ones installed by"
	elog "Portage, and fails when it cannot write to the system gem directory."
	elog "Either give bundler a user-writable location, for example:"
	elog "  bundle config set --global path ~/.local/share/gem"
	elog "or add ruby-lsp to the project's own Gemfile."
}
