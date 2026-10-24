#!/usr/bin/env bats
# bats file_tags=integration
#
# Integration -- story 002, Task 4.3: CLAUDE.md documents catalog schema 2.
# Requirements: R7.3 (and Q9: the Verification scripts row names --vectors).

load lib

DOC=$TREE/CLAUDE.md

# section TITLE -- the body of the CLAUDE.md section whose heading is TITLE.
section() {
  awk -v t="$1" '
    /^#+ / { on = (substr($0, index($0, " ") + 1) == t); next }
    on' "$DOC"
}

@test "R7.3 the check-profile-matrix.sh row of Verification scripts names --vectors and 27 presets" {
  local row
  row=$(section 'Verification scripts' | grep -E '^\|[^|]*check-profile-matrix\.sh' | head -n1)
  [ -n "$row" ] || {
    echo "no check-profile-matrix.sh row under Verification scripts" >&2
    false
  }
  [[ $row == *--vectors* ]] || {
    echo "the row does not name --vectors: $row" >&2
    false
  }
  [[ $row =~ (^|[^0-9])27([^0-9]|$) ]] || {
    echo "the row does not say 27 presets: $row" >&2
    false
  }
  ! [[ $row =~ (^|[^0-9])20\ presets ]] || {
    echo "the row still says 20 presets: $row" >&2
    false
  }
}

@test "R7.3 the row states the measured cost of --vectors" {
  local row
  row=$(section 'Verification scripts' | grep -E '^\|[^|]*check-profile-matrix\.sh' | head -n1)
  # a figure with a time unit in the same row that names --vectors
  grep -Eq -- '--vectors[^|]*[0-9][^|]*(ms|s\b|sec|second)' <<<"$row" || {
    echo "the row gives no measured cost for --vectors: $row" >&2
    false
  }
}

@test "R7.3 Composable profiles names 27 presets, toolchain, libc and the vectors file" {
  local body w
  body=$(section 'Composable profiles')
  [ -n "$body" ]
  for w in toolchain libc musl catalog-vectors.toml; do
    grep -qi -- "$w" <<<"$body" || {
      echo "Composable profiles does not mention $w" >&2
      false
    }
  done
  grep -Eq '(^|[^0-9])27([^0-9]|$)' <<<"$body" || {
    echo "Composable profiles does not say 27 presets" >&2
    false
  }
}
