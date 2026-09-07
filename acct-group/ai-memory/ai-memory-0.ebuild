# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit acct-group

DESCRIPTION="Group for the ai-memory MCP server"

SLOT="0"
KEYWORDS="~amd64 ~arm64"

# 602 continues this overlay's own run (localai 600, lemonade 601) above
# ::gentoo's highest assigned account id, 563 as of 2026-09-07. Picking a hole
# inside the range ::gentoo allocates from -- as acct-user/ntpd-rs{,-observe}
# did with 466 and 500 -- turns into a collision the day ::gentoo hands it out.
ACCT_GROUP_ID=602
