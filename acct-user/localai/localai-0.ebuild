# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit acct-user

DESCRIPTION="User for the LocalAI inference server"

SLOT="0"
KEYWORDS="~amd64 ~arm64"

# See acct-group/localai for why 600 and not a hole inside ::gentoo's range.
ACCT_USER_ID=600
ACCT_USER_GROUPS=( localai )
ACCT_USER_HOME=/var/lib/localai
ACCT_USER_SHELL=/sbin/nologin

acct-user_add_deps
