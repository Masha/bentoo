# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit acct-user

DESCRIPTION="User for the lemonade local LLM server"

SLOT="0"
KEYWORDS="~amd64 ~arm64"

# No reserved UID in the Gentoo GID/UID assignment table for lemonade,
# so let the system pick the next free one.
# 601, static, and the pair with acct-group/lemonade. It was -1 (dynamic),
# which breaks the three cases this overlay is supposed to cover: a container
# image and its host disagree on the number, NFS maps the wrong owner, and an
# image built on one machine is wrong on the next. 601 sits above ::gentoo's
# highest assigned account id (563 as of 2026-09-06) and next to
# acct-user/localai at 600, so it cannot collide with an existing assignment.
ACCT_USER_ID=601
ACCT_USER_GROUPS=( lemonade )
ACCT_USER_HOME=/var/lib/lemonade
ACCT_USER_HOME_PERMS=0750
ACCT_USER_SHELL=/sbin/nologin

acct-user_add_deps
