#!/usr/bin/env bats
# Unit -- story 002, Task 3.2: the failure paths of `--vectors` and `--static`
# that vectors-mode.bats (authored before the code) does not reach.
# Requirements: R5.6, design.md C4 and "Error Handling Strategy".
#
#   * R5.6 by test, not only by construction: /var/db/repos/gentoo is replaced
#     by a tmpfs of mode 000 inside a bwrap mount namespace, so opening or
#     listing anything there fails (an existence test below it just reads
#     false, so this backs the by-construction guarantee rather than
#     replacing it). Skipped (and counted as a skip by bats) where bwrap or
#     unprivileged user namespaces are unavailable.
#   * A --compose that broke (a crash, an exit naming no rule) is exit 2
#     naming the vector, never a mismatch: driven through the test-only seam.
#   * A vectors file that cannot be parsed is exit 2, and the catalog gaps
#     already found are still reported (on stderr, with the rest).

load lib/fixture
load lib/vectors-fixture

GENTOO=/var/db/repos/gentoo

# without_gentoo CMD... -- run CMD with $GENTOO an empty tmpfs of mode 000:
# listing it, or opening anything below it, fails with EACCES.
without_gentoo() {
  bwrap --dev-bind / / --tmpfs "$GENTOO" --chmod 000 "$GENTOO" "$@"
}

need_bwrap() {
  command -v bwrap >/dev/null 2>&1 || skip "bwrap is not installed"
  # The probe proves the sandbox both starts and bites: a read must fail.
  if ! without_gentoo true 2>/dev/null; then
    skip "bwrap cannot create a mount namespace here (user namespaces off?)"
  fi
  if without_gentoo ls "$GENTOO" >/dev/null 2>&1; then
    skip "bwrap ran, but $GENTOO stayed readable inside it"
  fi
}

# --- R5.6: no read of ::gentoo -------------------------------------------------------

@test "R5.6 --vectors exits 0 with $GENTOO unreadable" {
  need_bwrap
  vfx_tree
  run without_gentoo "$SCRIPT" --vectors
  status_is 0
}

@test "R5.6 --static exits 0 with $GENTOO unreadable" {
  need_bwrap
  vfx_tree
  run without_gentoo "$SCRIPT" --static
  status_is 0
}

@test "R5.6 --vectors still reports a disagreement with $GENTOO unreadable" {
  need_bwrap
  vfx_tree
  vfx_vec_raw <<EOF

[[vector]]
name   = "sandboxed-mismatch"
preset = "$VP_PLAIN"
layers = ["features/hardware/amd"]
expect = "invalid"
rules  = ["base"]
EOF
  run without_gentoo "$SCRIPT" --vectors
  status_is 1
  vector_line sandboxed-mismatch expected '--compose gave'
}

# --- a broken --compose is exit 2, never a mismatch -----------------------------------

# broken_compose RC [STDOUT] -- a seam executable exiting RC after printing STDOUT.
broken_compose() {
  local exe=$BATS_TEST_TMPDIR/compose-broken
  printf '#!/bin/sh\nprintf "%%s" "%s"\nexit %s\n' "${2-}" "$1" >"$exe"
  chmod +x "$exe"
  printf '%s\n' "$exe"
}

@test "C4 a --compose crash (exit 5) is exit 2 naming the vector, not a mismatch" {
  vfx_tree
  run env CHECK_PROFILE_MATRIX_COMPOSE="$(broken_compose 5)" "$SCRIPT" --vectors
  status_is 2
  line_names --compose broke
  ! grep -qF -- 'expected' <<<"$output" || {
    _dump "a broken --compose was reported as a vector mismatch"
    false
  }
}

@test "C4 a --compose rejection naming no rule is exit 2, not a mismatch" {
  vfx_tree
  run env CHECK_PROFILE_MATRIX_COMPOSE="$(broken_compose 1 'compose: nonsense')" "$SCRIPT" --vectors
  status_is 2
  line_names 'naming no rule'
}

# --- an unparseable vectors file keeps the catalog gaps ---------------------------------

@test "C4 unparseable vectors: exit 2, and the catalog gap found before it is still printed" {
  vfx_tree
  fx_raw <<'EOF'

[[layer]]
id   = "features/bogus"
type = "nosuchtype"
EOF
  mkdir -p "$BENTOO_TREE/layers/features/bogus"
  printf '[[vector\n' >"$VEC"
  run "$SCRIPT" --static
  status_is 2
  line_names nosuchtype
  line_names 'cannot be read'
}

# --- one mismatch is one line -----------------------------------------------------------

@test "C4 hostile: a newline in a vector name cannot forge a second report line" {
  vfx_tree
  vfx_vec_raw <<EOF2

[[vector]]
name   = "forged\nvector other: expected nothing"
preset = "$VP_PLAIN"
layers = ["features/hardware/amd"]
expect = "invalid"
rules  = ["base"]
EOF2
  run "$SCRIPT" --vectors
  status_is 1
  if grep -q '^vector other:' <<<"$output"; then
    _dump "a vector name forged a report line"
    false
  fi
  [ "$(grep -c '^vector ' <<<"$output")" -eq 1 ] || {
    _dump "one mismatch did not print exactly one line"
    false
  }
}
