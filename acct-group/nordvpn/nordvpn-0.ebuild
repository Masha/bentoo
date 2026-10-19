# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit acct-group

DESCRIPTION="Group allowed to control the NordVPN daemon"

SLOT="0"
KEYWORDS="~amd64"

# 604 continues this overlay's own run (localai 600, lemonade 601,
# ai-memory 602, obscura 603) above ::gentoo's highest assigned account id,
# 563 as of 2026-10-19.
ACCT_GROUP_ID=604
