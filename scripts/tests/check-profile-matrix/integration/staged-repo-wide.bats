#!/usr/bin/env bats
# bats file_tags=integration,resolution
#
# Integration -- Task 8.1: repository-wide profile files under profiles/.
# Requirements: R6.15, R6.13.
#
# Portage reads some files directly under profiles/ for EVERY profile of the
# repository (package.*, use.* except use.desc / use.local.desc,
# license_groups, eapi, updates/), so a change there can break any
# composition: --staged must treat every layer as touched (R6.15). Purely
# descriptive files (use.desc, use.local.desc, desc/, categories, repo_name,
# arch.list) change no resolution: static checks only, exit 0 (R6.13).
#
# Both halves use the same probe: amd is broken in a COMMIT (an atom no
# repository provides), then only the file under test is staged.
#   touch-all path   -> amd is resolved, so the run exits 1 naming amd
#   descriptive path -> nothing is resolved, so the run exits 0, quickly
# The descriptive half is the hostile guard of the use.* rule: a prefix match
# on "use." would wrongly make use.desc / use.local.desc touch every layer.

load lib

PROBE_ATOM=app-misc/bentoo-matrix-probe-nonexistent

setup() {
  need_portage
  scratch_repo
}

break_amd_in_a_commit() {
  local pk=profiles/features/hardware/amd/packages
  [ -f "$R/$pk" ]
  printf '%s\n' "$PROBE_ATOM" >>"$R/$pk"
  git -C "$R" add -- "$pk"
  _git_commit -qm 'break amd'
}

# stage_only PATH CONTENT -- append CONTENT to PATH (created if absent) and
# stage nothing else.
stage_only() {
  mkdir -p "$R/$(dirname "$1")"
  printf '%s' "$2" >>"$R/$1"
  git -C "$R" add -- "$1"
  [ "$(git -C "$R" diff --cached --name-only)" = "$1" ]
}

expect_touch_all() {
  run_staged
  status_is 1
  line_names features/hardware/amd
  [[ $output == *"$PROBE_ATOM"* ]] || {
    _dump "the broken amd layer was not resolved"
    false
  }
  assert_tmp_clean
}

expect_static_only() {
  local t0=$SECONDS took
  run_staged
  took=$((SECONDS - t0))
  status_is 0
  [[ $output != *"$PROBE_ATOM"* ]]
  # one emerge -p is ~3 s and touch-all is dozens of them
  [ "$took" -lt 20 ] || {
    echo "took ${took}s: looks like it resolved combinations" >&2
    false
  }
  assert_tmp_clean
}

# --- R6.15: Portage-read files touch every layer ------------------------------------

# bats test_tags=slow
@test "R6.15 staging only profiles/package.use.mask treats every layer as touched" {
  break_amd_in_a_commit
  stage_only profiles/package.use.mask $'\n# probe: staged comment\n'
  expect_touch_all
}

# bats test_tags=slow
@test "R6.15 staging only a file under profiles/updates/ treats every layer as touched" {
  break_amd_in_a_commit
  # an empty updates file: valid for Portage, and still a staged path
  stage_only profiles/updates/4Q-2026 ''
  expect_touch_all
}

# bats test_tags=slow
@test "R6.15 staging only profiles/license_groups treats every layer as touched" {
  break_amd_in_a_commit
  stage_only profiles/license_groups $'# probe: staged comment\n'
  expect_touch_all
}

# --- R6.13: descriptive files stay static-only (hostile half) -----------------------

@test "R6.13 staging only profiles/use.desc runs the static checks only and exits 0" {
  break_amd_in_a_commit
  stage_only profiles/use.desc $'# probe: staged comment\n'
  expect_static_only
}

@test "R6.13 hostile: profiles/use.local.desc starts with use. but stays static-only" {
  break_amd_in_a_commit
  [ -f "$R/profiles/use.local.desc" ]
  stage_only profiles/use.local.desc $'# probe: staged comment\n'
  expect_static_only
}

@test "R6.13 staging only a profiles/desc/<x>.desc file runs the static checks only and exits 0" {
  break_amd_in_a_commit
  local d
  d=$(cd "$R" && ls profiles/desc/*.desc 2>/dev/null | head -n1)
  [ -n "$d" ] || d=profiles/desc/probe.desc
  stage_only "$d" $'# probe: staged comment\n'
  expect_static_only
}
