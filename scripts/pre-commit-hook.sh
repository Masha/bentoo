#!/usr/bin/env bash
# Refuse a commit carrying autoupdate damage.
#
# Thin on purpose: the checks live in scripts/check-autoupdate-damage.sh, which
# is versioned and reviewable. This file is not — .git/hooks is per-clone — so
# it must hold no logic worth reading.
#
# Install in a fresh clone with:
#   ln -sf ../../scripts/pre-commit-hook.sh .git/hooks/pre-commit
#
# Bypass, when you genuinely mean it: git commit --no-verify

set -euo pipefail
exec "$(git rev-parse --show-toplevel)/scripts/check-autoupdate-damage.sh" --staged
