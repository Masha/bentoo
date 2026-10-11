#!/usr/bin/env bats
# Unit -- Task 2.1: CLI surface, runtime prerequisites, the --self-test guard
# and cleanup.  Requirements: R6.10, R6.11, R6.12.
#
# Contract (design.md C6): modes --static | --staged | --full |
# --compose <preset-id> [layer-id...] | --self-test; exit 0 clean, 1 gap,
# 2 nothing compared / bad usage / missing prerequisite.

load lib/fixture

setup() {
  fx_standard
}

# A copy of the script in a scratch repository whose suite directory holds
# only what the test puts there. Every --self-test test runs the COPY: running
# the real script's --self-test from inside its own suite would recurse.
self_test_copy() {
  COPY=$BATS_TEST_TMPDIR/copy
  mkdir -p "$COPY/scripts/tests/check-profile-matrix"
  cp "$SCRIPT" "$COPY/scripts/check-profile-matrix.sh"
  chmod +x "$COPY/scripts/check-profile-matrix.sh"
  SUITE=$COPY/scripts/tests/check-profile-matrix
}

# stub_bats COUNT [FAIL] -- a fake `bats` FIRST on PATH: it logs its argv and
# BENTOO_TREE, answers `--count` with COUNT, otherwise prints a TAP plan of COUNT
# tests (the last one "not ok" when FAIL is set) and exits like bats would.
# The --self-test cases use it so the suite under test is never re-entered.
stub_bats() {
  STUB=$BATS_TEST_TMPDIR/stubbin
  STUB_LOG=$BATS_TEST_TMPDIR/stub-bats.log
  mkdir -p "$STUB"
  cat >"$STUB/bats" <<EOF
#!/usr/bin/env bash
printf 'argv:%s\n' "\$*" >>"$STUB_LOG"
printf 'tree:%s\n' "\${BENTOO_TREE:-}" >>"$STUB_LOG"
for a in "\$@"; do
  case \$a in --count | -c) echo $1; exit 0 ;; esac
done
echo "1..$1"
i=1
while [ \$i -le $1 ]; do
  if [ -n "${2:-}" ] && [ \$i -eq $1 ]; then echo "not ok \$i stub"; else echo "ok \$i stub"; fi
  i=\$((i + 1))
done
[ -z "${2:-}" ]
EOF
  chmod +x "$STUB/bats"
}

fake_python_without_tomllib() {
  FAKEPY=$BATS_TEST_TMPDIR/fakepy
  mkdir -p "$FAKEPY"
  printf '%s\n' '#!/bin/sh' \
    "echo \"ModuleNotFoundError: No module named 'tomllib'\" >&2" \
    'exit 1' >"$FAKEPY/python3"
  chmod +x "$FAKEPY/python3"
}

# --- usage -----------------------------------------------------------------

@test "no mode at all is bad usage: exit 2" {
  run "$SCRIPT"
  status_is 2
}

@test "an unknown mode is bad usage: exit 2, and the usage text lists the modes" {
  run "$SCRIPT" --bogus
  status_is 2
  [[ $output == *--static* ]]
  [[ $output == *--compose* ]]
  [[ $output == *--self-test* ]]
}

@test "--compose without a preset id is bad usage: exit 2" {
  run "$SCRIPT" --compose
  status_is 2
}

# --- R6.10: prerequisites ---------------------------------------------------
# Hostile half first: a missing emerge must NOT stop the modes that never call
# Portage. A prerequisite check that fires for every mode would make --static
# and --compose unusable on any host without Portage (e.g. the sibling tool's
# CI reusing these fixtures).

@test "R6.10 without emerge, --static and --compose still run (they never call Portage)" {
  nobin=$(path_without emerge)
  run env PATH="$nobin" "$SCRIPT" --static
  status_is 0
  run env PATH="$nobin" "$SCRIPT" --compose "$P_PLAIN" targets/server
  status_is 0
}

@test "R6.10 without emerge, --full exits 2 naming emerge" {
  [ -d /var/db/repos/gentoo ] || skip "no ::gentoo tree: the script would name it first"
  nobin=$(path_without emerge)
  run env PATH="$nobin" "$SCRIPT" --full
  status_is 2
  line_names emerge
  [[ $output != *"command not found"* ]]
}

@test "R6.10 without emerge, --staged exits 2 naming emerge" {
  [ -d /var/db/repos/gentoo ] || skip "no ::gentoo tree: the script would name it first"
  nobin=$(path_without emerge)
  run env PATH="$nobin" "$SCRIPT" --staged
  status_is 2
  line_names emerge
  [[ $output != *"command not found"* ]]
}

@test "R6.10 without portageq, --full exits 2 naming portageq" {
  [ -d /var/db/repos/gentoo ] || skip "no ::gentoo tree: the script would name it first"
  nobin=$(path_without portageq)
  run env PATH="$nobin" "$SCRIPT" --full
  status_is 2
  line_names portageq
  [[ $output != *"command not found"* ]]
}

# Not simulable: "--static and --compose never read /var/db/repos/gentoo"
# needs that directory to disappear, and the contract has no override for its
# path. Covered only by reading; the emerge/portageq cases above prove the
# per-mode split for the prerequisites that CAN be removed.

@test "R6.10 python3 without tomllib: --static exits 2 naming what is missing" {
  fake_python_without_tomllib
  run env PATH="$FAKEPY:$PATH" "$SCRIPT" --static
  status_is 2
  line_names 'tomllib|python3'
  [[ $output != *"command not found"* ]]
}

@test "R6.10 --self-test without bats exits 2 naming bats" {
  self_test_copy
  printf '%s\n' '#!/usr/bin/env bats' '@test "never reached" { true; }' >"$SUITE/one.bats"
  nobin=$(path_without bats)
  run env PATH="$nobin" "$COPY/scripts/check-profile-matrix.sh" --self-test
  status_is 2
  line_names bats
  [[ $output != *"command not found"* ]]
}

# --- R6.11: --self-test refuses zero assertions -----------------------------

@test "R6.11 --self-test (stub bats, 1 passing test) exits 0" {
  self_test_copy
  printf '%s\n' '#!/usr/bin/env bats' '@test "t" { true; }' >"$SUITE/one.bats"
  stub_bats 1
  run env PATH="$STUB:$PATH" "$COPY/scripts/check-profile-matrix.sh" --self-test
  status_is 0
  grep -q '^argv:' "$STUB_LOG" # the stub, not a real bats, was run
}

@test "R6.11 --self-test fails when bats reports zero tests (stub bats)" {
  self_test_copy
  printf '%s\n' '#!/usr/bin/env bats' >"$SUITE/empty.bats"
  stub_bats 0
  run env PATH="$STUB:$PATH" "$COPY/scripts/check-profile-matrix.sh" --self-test
  [ "$status" -ne 0 ] || {
    _dump "a suite that ran zero tests must not pass"
    false
  }
  [ "$status" -ne 127 ]
}

@test "R6.11 --self-test fails when a fixture test fails (stub bats)" {
  self_test_copy
  printf '%s\n' '#!/usr/bin/env bats' '@test "t" { true; }' >"$SUITE/one.bats"
  stub_bats 2 fail
  run env PATH="$STUB:$PATH" "$COPY/scripts/check-profile-matrix.sh" --self-test
  [ "$status" -ne 0 ] || {
    _dump "a failing fixture must fail --self-test"
    false
  }
  [ "$status" -ne 127 ]
}

@test "R6.11 --self-test hands bats a scratch BENTOO_TREE, never the checkout, and never -r (stub bats)" {
  self_test_copy
  printf '%s\n' '#!/usr/bin/env bats' '@test "t" { true; }' >"$SUITE/one.bats"
  stub_bats 1
  run env -u BENTOO_TREE PATH="$STUB:$PATH" "$COPY/scripts/check-profile-matrix.sh" --self-test
  status_is 0
  local tree
  tree=$(sed -n 's/^tree://p' "$STUB_LOG" | head -n1)
  [ -n "$tree" ] || {
    echo "bats ran without BENTOO_TREE" >&2
    false
  }
  local real copy
  copy=$(cd "$COPY" && pwd -P)
  real=$(cd "$tree" 2>/dev/null && pwd -P || printf '%s' "$tree")
  [ "$real" != "$copy" ] && [[ $real != "$copy"/* ]]
  ! grep -Eq '^argv:.*(^| )(-r|--recursive)( |$)' "$STUB_LOG" || {
    echo "--self-test ran bats recursively: $(cat "$STUB_LOG")" >&2
    false
  }
}

@test "R6.11 --self-test is non-recursive: a failing integration/ file does not fail it (real bats on a copy)" {
  # Safe with the real bats: the copy's suite holds only these two files.
  self_test_copy
  mkdir -p "$SUITE/integration"
  printf '%s\n' '#!/usr/bin/env bats' '@test "top level" { true; }' >"$SUITE/one.bats"
  printf '%s\n' '#!/usr/bin/env bats' '@test "reads the real tree" { false; }' >"$SUITE/integration/real.bats"
  run "$COPY/scripts/check-profile-matrix.sh" --self-test
  status_is 0
}

# --- R6.12: nothing left behind --------------------------------------------
# Every run happens with TMPDIR pointed at an empty directory and the current
# directory at another; afterwards both must still be empty and the fixture
# tree byte-for-byte unchanged -- on the passing path AND on each failing
# path, where a leaked temp dir is most likely.

assert_left_nothing() {
  local leftover
  leftover=$(find "$TMP_PROBE" "$CWD_PROBE" -mindepth 1)
  [ -z "$leftover" ] || {
    _dump "files left behind: $leftover"
    false
  }
  [ "$(tree_snapshot "$FX")" = "$BEFORE" ] || {
    _dump "the run modified the tree it validates"
    false
  }
}

run_clean() {
  TMP_PROBE=$BATS_TEST_TMPDIR/tmp-probe
  CWD_PROBE=$BATS_TEST_TMPDIR/cwd-probe
  rm -rf "$TMP_PROBE" "$CWD_PROBE"
  mkdir -p "$TMP_PROBE" "$CWD_PROBE"
  BEFORE=$(tree_snapshot "$FX")
  run bash -c 'cd "$1" && shift && exec env TMPDIR="$0" "$@"' \
    "$TMP_PROBE" "$CWD_PROBE" "$SCRIPT" "$@"
}

@test "R6.12 --static leaves nothing behind when the tree is clean" {
  run_clean --static
  status_is 0
  assert_left_nothing
}

@test "R6.12 --static leaves nothing behind when it reports gaps" {
  mkdir -p "$FX/profiles/targets/stray"
  printf '5\n' >"$FX/profiles/targets/stray/eapi"
  run_clean --static
  status_is 1
  assert_left_nothing
}

@test "R6.12 --static leaves nothing behind when the catalog is not valid TOML" {
  printf '\n[[layer\nid = \n' >>"$CAT"
  run_clean --static
  status_is 1
  assert_left_nothing
}

@test "R6.12 --compose leaves nothing behind on a valid and on a rejected selection" {
  run_clean --compose "$P_PLAIN" targets/server features/hardware/amd
  status_is 0
  assert_left_nothing
  run_clean --compose "$P_PLAIN" features/hardware/nvidia features/hardware/nvidia-legacy
  status_is 1
  assert_left_nothing
}
