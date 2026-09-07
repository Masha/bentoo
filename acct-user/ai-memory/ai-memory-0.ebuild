# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit acct-user

DESCRIPTION="User for the ai-memory MCP server"

SLOT="0"
KEYWORDS="~amd64 ~arm64"

# See acct-group/ai-memory for why 602 and not a hole inside ::gentoo's range.
ACCT_USER_ID=602
ACCT_USER_GROUPS=( ai-memory )
# Matches the StateDirectory the systemd unit declares and the path upstream's
# sysusers.d entry gives the account, so the service finds its database where
# the packaging on every other distribution puts it.
ACCT_USER_HOME=/var/lib/ai-memory
ACCT_USER_SHELL=/sbin/nologin

acct-user_add_deps
