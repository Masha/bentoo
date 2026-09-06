# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit acct-group

DESCRIPTION="Group for the LocalAI inference server"

SLOT="0"
KEYWORDS="~amd64 ~arm64"

# 600 is above ::gentoo's highest assigned account id (563 as of 2026-09-06),
# so it cannot collide with an existing assignment. This deliberately does NOT
# follow acct-user/ntpd-rs{,-observe}, which took 466 and 500 -- both are holes
# INSIDE the range ::gentoo allocates from, and both become collisions the day
# ::gentoo hands them out.
ACCT_GROUP_ID=600
