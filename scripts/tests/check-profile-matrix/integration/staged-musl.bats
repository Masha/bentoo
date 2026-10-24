#!/usr/bin/env bats
# bats file_tags=integration,resolution
#
# Integration -- story 002, Task 4.1: the hook mode (--staged) checks the
# vectors and resolves over a musl reference preset.
# Requirements: R5.7, R6.2.
#
# Same harness as staged.bats: every test works on a private scratch git
# repository (scratch_repo), never on the checkout. Breakage is planted with
# an atom no repository provides, so every reference preset the hook resolves
# over must FAIL and therefore be named -- which is how this suite observes
# the reference preset set without reading the script's constants.
#
# R6.2 is conditional: if Task 2.4 recorded default/linux/amd64/23.0/musl's
# @system as failing (a story deviation), that preset stays out of the
# reference set and the R6.2 case below is replaced by a skip citing the
# deviation -- never weakened.
#
# Each case resolves one touched layer over the reference presets (about a
# minute or two each; staged.bats budgets 3 minutes for the same shape).

load lib

PROBE_ATOM=app-misc/bentoo-matrix-probe-nonexistent
MUSL_REF=default/linux/amd64/23.0/musl

setup() {
  need_portage
  scratch_repo
}

@test "R6.2 a broken touched layer fails over the musl reference preset too, named whole" {
  local f=profiles/features/hardware/intel/packages
  [ -f "$R/$f" ]
  printf '%s\n' "$PROBE_ATOM" >>"$R/$f"
  git -C "$R" add -- "$f"
  run_staged
  status_is 1
  # whole token: .../musl/systemd or .../musl/llvm would not count
  line_names "$MUSL_REF"
  [[ $output == *"$PROBE_ATOM"* ]]
  assert_tmp_clean
}

@test "R5.7 --staged runs the vectors check: a disagreeing vector in the tree fails the hook naming it" {
  # the selection is valid (amd alone on the plain preset); the vector claims
  # it is invalid, so --compose and the vector disagree
  cat >>"$R/profiles/catalog-vectors.toml" <<'EOF'

[[vector]]
name   = "staged-probe-disagrees"
preset = "default/linux/amd64/23.0"
layers = ["features/hardware/amd"]
expect = "invalid"
rules  = ["base"]
EOF
  # touch one layer so the hook has something to resolve, as a real commit does
  local f=profiles/features/games/package.use
  [ -f "$R/$f" ]
  printf '# probe: staged comment\n' >>"$R/$f"
  git -C "$R" add -- "$f"
  run_staged
  status_is 1
  grep -q '^vector staged-probe-disagrees:' <<<"$output" || {
    _dump "--staged did not report the disagreeing vector"
    false
  }
  assert_tmp_clean
}
