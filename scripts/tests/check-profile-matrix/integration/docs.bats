#!/usr/bin/env bats
# bats file_tags=integration
#
# Integration -- Task 7.2: CLAUDE.md documents the validator and the model.
# Requirements: R8.1, R8.2.

load lib

DOC=$TREE/CLAUDE.md

@test "R8.1 the verification-scripts table has a check-profile-matrix.sh row naming every mode" {
  local row
  row=$(grep -E '^\|[^|]*check-profile-matrix\.sh' "$DOC" | head -n1)
  [ -n "$row" ] || {
    echo "no table row for check-profile-matrix.sh in CLAUDE.md" >&2
    false
  }
  local m
  for m in --static --staged --full --compose --self-test; do
    [[ $row == *"$m"* ]] || {
      echo "the row does not name $m: $row" >&2
      false
    }
  done
}

@test "R8.1 CLAUDE.md says when to run --full" {
  # one line that pairs --full with its moment (before a push / after a batch)
  grep -E -- '--full' "$DOC" | grep -Eiq 'push|batch' || {
    echo "no line in CLAUDE.md says when to run --full" >&2
    false
  }
}

@test "R8.2 the repository-layout section explains presets, layers, the catalog and layers/" {
  local section
  section=$(awk '/^## Repository layout/ { on = 1; next } /^## / { on = 0 } on' "$DOC")
  [ -n "$section" ]
  local w
  for w in 'preset' 'layer' 'profiles/catalog.toml' 'layers/'; do
    grep -qi -- "$w" <<<"$section" || {
      echo "the Repository layout section does not mention $w" >&2
      false
    }
  done
  # the schema bump rule travels with the contract
  grep -Eqi 'schema' <<<"$section"
}
