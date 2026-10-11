#!/usr/bin/env bats
# bats file_tags=integration
#
# Integration -- Task 6.1: scripts/pre-commit-hook.sh wiring.
# Requirements: R7.1, R7.2, R7.3, R7.4.
#
# The real hook runs in a scratch git repository where both checks are
# STUBS that log their invocation and exit with a chosen code
# (AUTOUPDATE_EXIT, MATRIX_EXIT). So this tests the hook's decisions -- which
# check runs, which exit code wins -- not the checks themselves, and needs
# neither Portage nor the real tree beyond the hook file.

load lib

setup() {
  R=$BATS_TEST_TMPDIR/hookrepo
  LOG=$BATS_TEST_TMPDIR/calls.log
  mkdir -p "$R/scripts"
  cp "$TREE/scripts/pre-commit-hook.sh" "$R/scripts/pre-commit-hook.sh"
  chmod +x "$R/scripts/pre-commit-hook.sh"
  local stub
  for stub in check-autoupdate-damage.sh:AUTOUPDATE_EXIT check-profile-matrix.sh:MATRIX_EXIT; do
    printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "%s" "$*" >>"%s"\nexit "${%s:-0}"\n' \
      "${stub%%:*}" "$LOG" "${stub##*:}" >"$R/scripts/${stub%%:*}"
    chmod +x "$R/scripts/${stub%%:*}"
  done
  # a tree shaped like the overlay, including look-alike paths
  local f
  for f in profiles/features/games/package.use profiles/targets/server/make.defaults \
    layers/features/hardware/nvidia/etc/modprobe.d/50-bentoo-nvidia.conf \
    profiles/package.mask profiles/profiles.desc metadata/layout.conf metadata/layout.conf.orig metadata/md5-cache/app-misc/foo-1 \
    app-misc/foo/foo-1.ebuild app-misc/profiles/profiles-1.ebuild docs/layers/notes.md \
    profilesx/README; do
    mkdir -p "$R/${f%/*}"
    printf 'v1\n' >"$R/$f"
  done
  git -C "$R" init -q
  git -C "$R" add -A
  _git_commit -qm baseline
  : >"$LOG"
}

# stage PATH -- modify (or create) PATH and stage it, on a clean index.
stage() {
  git -C "$R" reset -q
  git -C "$R" checkout -q -- . 2>/dev/null || true
  mkdir -p "$R/${1%/*}"
  printf 'v2 %s\n' "$RANDOM" >>"$R/$1"
  git -C "$R" add -- "$1"
}

run_hook() {
  : >"$LOG"
  run env AUTOUPDATE_EXIT="${AUTOUPDATE_EXIT:-0}" MATRIX_EXIT="${MATRIX_EXIT:-0}" \
    bash -c 'cd "$1" && exec ./scripts/pre-commit-hook.sh' _ "$R"
}

ran() { grep -q "^$1 --staged\$" "$LOG"; }

@test "R7.1/R7.2 the matrix runs exactly when profiles/, layers/ or metadata/layout.conf is staged" {
  local p
  # hostile half first: paths that merely LOOK like profile paths
  for p in app-misc/foo/foo-1.ebuild app-misc/profiles/profiles-1.ebuild docs/layers/notes.md \
    profilesx/README metadata/layout.conf.orig metadata/md5-cache/app-misc/foo-1; do
    stage "$p"
    run_hook
    status_is 0
    ! ran check-profile-matrix.sh || {
      echo "matrix ran for unrelated path $p" >&2
      false
    }
  done
  for p in profiles/features/games/package.use layers/features/hardware/nvidia/etc/modprobe.d/50-bentoo-nvidia.conf \
    metadata/layout.conf profiles/targets/new-layer/eapi profiles/package.mask profiles/profiles.desc; do
    # (R6.13: a profiles/ path touching no layer still goes to the matrix,
    # which then runs its static checks only)
    stage "$p"
    run_hook
    status_is 0
    ran check-profile-matrix.sh || {
      echo "matrix did not run for $p (log: $(cat "$LOG"))" >&2
      false
    }
  done
}

@test "R7.1 a staged deletion under profiles/ also runs the matrix" {
  git -C "$R" rm -q profiles/targets/server/make.defaults
  run_hook
  status_is 0
  ran check-profile-matrix.sh
}

@test "R7.3 the autoupdate check still runs on every commit, also when the matrix runs" {
  stage app-misc/foo/foo-1.ebuild
  run_hook
  ran check-autoupdate-damage.sh
  stage profiles/features/games/package.use
  run_hook
  ran check-autoupdate-damage.sh
  ran check-profile-matrix.sh
}

@test "R7.3 a failing autoupdate check still blocks when the matrix passes" {
  stage profiles/features/games/package.use
  AUTOUPDATE_EXIT=1 MATRIX_EXIT=0 run_hook
  status_is 1
  ran check-profile-matrix.sh
}

@test "R7.4 the hook exits with the highest code either check returned" {
  stage profiles/features/games/package.use
  local a m want
  for a in 0 1 2; do
    for m in 0 1 2; do
      want=$((a > m ? a : m))
      AUTOUPDATE_EXIT=$a MATRIX_EXIT=$m run_hook
      [ "$status" -eq "$want" ] || {
        _dump "autoupdate=$a matrix=$m: expected exit $want"
        false
      }
      ran check-autoupdate-damage.sh
      ran check-profile-matrix.sh
    done
  done
}

@test "R7.4 through git commit: a failing matrix blocks the commit" {
  ln -s ../../scripts/pre-commit-hook.sh "$R/.git/hooks/pre-commit"
  stage profiles/features/games/package.use
  local head
  head=$(git -C "$R" rev-parse HEAD)
  run env MATRIX_EXIT=1 git -C "$R" -c user.name=bats -c user.email=bats@localhost \
    -c commit.gpgsign=false -c core.hooksPath="$R/.git/hooks" commit -qm 'should be blocked'
  [ "$status" -ne 0 ] || {
    _dump "the commit went through"
    false
  }
  [ "$(git -C "$R" rev-parse HEAD)" = "$head" ]
  ran check-profile-matrix.sh
}
