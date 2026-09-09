#!/bin/bash
# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# Entry point for both /usr/bin/opencodex and /usr/bin/ocx (the second is a
# symlink to the first).  opencodex is TypeScript with no build step, so this
# hands the CLI source straight to the Bun runtime from net-libs/bun-bin.
#
# /opt/bin/bun is itself a symlink to /opt/bun-bin/bin/bun, which is fine: it
# is Bun that gets exec'd, and nothing downstream resolves $0.
#
# Launching Bun here rather than upstream's bin/ocx.mjs Node shim is what keeps
# net-libs/nodejs out of the dependency graph AND what makes `ocx update`
# recognise a source layout and refuse to overwrite /usr.

set -euo pipefail

exec /opt/bin/bun /usr/lib/opencodex/src/cli/index.ts "$@"
