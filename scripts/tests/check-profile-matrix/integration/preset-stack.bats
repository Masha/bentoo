#!/usr/bin/env bats
# bats file_tags=integration
#
# Integration -- Task 3.2: the presets still load the same profile stack.
# Requirement: R1.3. Story 002 grew the list from 20 to 27 presets (R2.1).
#
# "Before this story" a preset was selected by pointing make.profile at the
# preset directory (eselect). "After", the sibling tool writes a make.profile
# whose parent is what `--compose <preset>` prints. With no layer selected the
# two must give Portage the same directory stack:
#   baseline : make.profile -> <BASELINE_REF tree>/profiles/<preset>
#   composed : make.profile/parent = `--compose <preset>`, bentoo = TREE
# BASELINE_REF (default: master) is extracted with `git archive` -- read-only
# for the repository. Every preset must exist on the baseline: master has all
# 27 since 6ba1d30fd, so a preset missing there is a failure, not a skip. Set
# BASELINE_REF to an older commit only to compare against it on purpose.

load lib

setup() {
  need_portage
}

# normalised stack: repo prefixes replaced, the config root's own
# make.profile entry dropped (it carries no settings of its own here).
norm_stack() { # CROOT BENTOO-LOCATION
  pq "$1" stack | while IFS= read -r p; do
    case $p in
      "$1"/*) ;;
      "$2"/*) printf 'BENTOO%s\n' "${p#"$2"}" ;;
      *) printf '%s\n' "$p" ;;
    esac
  done
}

@test "R1.3 each of the 27 presets composed with no layer loads the stack it loaded before" {
  local ref=${BASELINE_REF:-master}
  git -C "$TREE" rev-parse --verify -q "$ref^{commit}" >/dev/null ||
    skip "baseline ref $ref not found in $TREE"
  local base=$BATS_TEST_TMPDIR/baseline
  mkdir -p "$base"
  git -C "$TREE" archive "$ref" profiles metadata/layout.conf | tar -C "$base" -xf -

  local presets n=0 compared=0 failed=0 p cr0 cr1 want got
  presets=$(awk '$1 == "amd64" { print $2 }' "$TREE/profiles/profiles.desc")
  for p in $presets; do
    n=$((n + 1))
    run --separate-stderr "$SCRIPT" --compose "$p"
    status_is 0
    output_is "bentoo:$p"
    if [ ! -d "$base/profiles/$p" ]; then
      printf '%s: not on the baseline %s\n' "$p" "$ref" >&2
      continue
    fi

    compared=$((compared + 1))
    cr0=$BATS_TEST_TMPDIR/base-$n
    cr1=$BATS_TEST_TMPDIR/comp-$n
    mk_croot "$cr0" "$base"
    rmdir "$cr0/etc/portage/make.profile"
    ln -s "$base/profiles/$p" "$cr0/etc/portage/make.profile"
    mk_croot "$cr1" "$TREE"
    printf '%s\n' "$output" >"$cr1/etc/portage/make.profile/parent"

    want=$(norm_stack "$cr0" "$base")
    got=$(norm_stack "$cr1" "$TREE")
    if [ "$want" != "$got" ]; then
      failed=$((failed + 1))
      printf '%s: stack differs\n--- before ---\n%s\n--- composed ---\n%s\n' "$p" "$want" "$got" >&2
    fi
  done
  [ "$n" -eq 27 ]
  # every preset was compared against the baseline, none skipped
  [ "$compared" -eq "$n" ]
  [ "$failed" -eq 0 ]
}
