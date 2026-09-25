# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit acct-group

DESCRIPTION="Group allowed to operate the Obscura VPN service"

SLOT="0"
KEYWORDS="~amd64 ~arm64"

# 603 continues this overlay's own run (localai 600, lemonade 601, ai-memory
# 602) above ::gentoo's highest assigned account id, 563 as of 2026-09-24.
# Static rather than -1 for the reason acct-user/lemonade gives: a container
# image and its host, or two machines sharing an image, must agree on it.
# The obscura service checks peers against its own effective GID, so members
# of this group may drive the VPN through /run/obscura.sock.
ACCT_GROUP_ID=603
