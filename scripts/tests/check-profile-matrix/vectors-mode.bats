#!/usr/bin/env bats
# Unit -- story 002, Task 3.2: the `--vectors` mode.
# Requirements: R5.1, R5.2, R5.3, R5.4, R5.5, R5.6, R7.4.
#
# Contract (design.md C4, "Error Handling Strategy"): `--vectors` runs
# `--static` first (a failing static is exit 1 with its report, nothing
# compared), then runs every vector through the --compose code path: a valid
# vector agrees when --compose accepts and prints exactly its `parent` lines
# in order; an invalid one agrees when --compose rejects and the SET of rule
# names it reports equals `rules`, in any order. Each disagreement is one line
# `vector <name>: expected ..., --compose gave ...`; every one is reported,
# then exit 1. It never reads /var/db/repos/gentoo nor calls Portage.
#
# Comparison is identity, so both hostile halves are here: two lists with the
# same content in another order must NOT agree for `parent` (order is the
# contract), and two rule lists with the same members in another order, or
# with a rule --compose prints twice, MUST agree for `rules` (a set).

load lib/fixture
load lib/vectors-fixture

# --- R5.3: rules compare as a set (hostile halves first) -------------------------

@test "R5.3 hostile: rules listed in another order than --compose prints them (base, exclusive) agree: exit 0" {
  vfx_catalog
  vfx_vectors two-rules-flavors-on-desktop
  # --compose prints exclusive first, then base once PER constrained layer
  # (server and headless): as a set that is {exclusive, base}
  vfx_vec_raw <<EOF

[[vector]]
name   = "two-rules-reordered"
preset = "$VP_KDE"
layers = ["targets/server", "targets/headless"]
expect = "invalid"
rules  = ["base", "exclusive"]
EOF
  run "$SCRIPT" --vectors
  status_is 0
  no_vector_line two-rules-reordered
}

@test "R5.3 an invalid vector missing a rule of the set exits 1 naming the vector and both sets" {
  vfx_tree
  vfx_vec_raw <<EOF

[[vector]]
name   = "rules-short"
preset = "$VP_KDE"
layers = ["targets/server", "targets/headless"]
expect = "invalid"
rules  = ["exclusive"]
EOF
  run "$SCRIPT" --vectors
  status_is 1
  vector_line rules-short expected '--compose gave' exclusive base
}

@test "R5.3 an invalid vector with an extra rule exits 1 naming the vector and both sets" {
  vfx_tree
  vfx_vec_raw <<EOF

[[vector]]
name   = "rules-long"
preset = "$VP_KDE"
layers = ["targets/server", "targets/headless"]
expect = "invalid"
rules  = ["exclusive", "base", "conflict"]
EOF
  run "$SCRIPT" --vectors
  status_is 1
  vector_line rules-long expected '--compose gave' conflict
}

# --- R5.2: parent compares exactly, in order (hostile halves first) ---------------

@test "R5.2 hostile: a parent with the right lines in the wrong order exits 1 naming the vector and both lists" {
  vfx_tree
  vfx_vec_raw <<EOF

[[vector]]
name   = "parent-swapped"
preset = "$VP_KDE"
layers = ["targets/workstation", "features/games"]
expect = "valid"
parent = ["bentoo:$VP_KDE", "bentoo:features/games", "bentoo:targets/workstation"]
EOF
  run "$SCRIPT" --vectors
  status_is 1
  vector_line parent-swapped expected '--compose gave' bentoo:features/games bentoo:targets/workstation
}

@test "R5.2 hostile: a parent repeating a layer given twice disagrees (a layer given twice is one line)" {
  vfx_tree
  vfx_vec_raw <<EOF

[[vector]]
name   = "parent-not-deduplicated"
preset = "$VP_PLAIN"
layers = ["features/hardware/intel", "features/hardware/intel"]
expect = "valid"
parent = ["bentoo:$VP_PLAIN", "bentoo:features/hardware/intel", "bentoo:features/hardware/intel"]
EOF
  run "$SCRIPT" --vectors
  status_is 1
  vector_line parent-not-deduplicated expected '--compose gave'
}

@test "R5.2 a parent missing a line exits 1 naming the vector" {
  vfx_tree
  vfx_vec_raw <<EOF

[[vector]]
name   = "parent-short"
preset = "$VP_TINY"
layers = ["targets/server", "features/hardware/amd"]
expect = "valid"
parent = ["bentoo:$VP_TINY", "bentoo:targets/server"]
EOF
  run "$SCRIPT" --vectors
  status_is 1
  vector_line parent-short expected '--compose gave' bentoo:features/hardware/amd
}

# --- R5.1 / R5.6: agreement --------------------------------------------------------

@test "R5.1 every standard vector (input out of rank order, duplicates, a two-rule set) agrees: exit 0" {
  vfx_tree
  run "$SCRIPT" --vectors
  status_is 0
  if grep -q '^vector ' <<<"$output"; then
    _dump "a vector was reported as a mismatch"
    false
  fi
}

@test "R5.6 --vectors needs no Portage: with emerge, portageq and bwrap off PATH it still exits 0" {
  vfx_tree
  local p
  p=$(path_without emerge portageq bwrap)
  run env PATH="$p" "$SCRIPT" --vectors
  status_is 0
}

# --- R5.4: the verdict itself flips ------------------------------------------------

@test "R5.4 a vector expecting invalid that --compose accepts exits 1 naming the vector" {
  vfx_tree
  vfx_vec_raw <<EOF

[[vector]]
name   = "expects-invalid-but-accepted"
preset = "$VP_PLAIN"
layers = ["features/hardware/amd"]
expect = "invalid"
rules  = ["base"]
EOF
  run "$SCRIPT" --vectors
  status_is 1
  vector_line expects-invalid-but-accepted
}

@test "R5.4 a vector expecting valid that --compose rejects exits 1 naming the vector" {
  vfx_tree
  vfx_vec_raw <<EOF

[[vector]]
name   = "expects-valid-but-rejected"
preset = "$VP_TINY"
layers = ["features/hardware/nvidia"]
expect = "valid"
parent = ["bentoo:$VP_TINY", "bentoo:features/hardware/nvidia"]
EOF
  run "$SCRIPT" --vectors
  status_is 1
  vector_line expects-valid-but-rejected
}

# --- R5.5: every disagreement in one run -------------------------------------------

@test "R5.5 three disagreeing vectors of three kinds are all reported in one run" {
  vfx_tree
  vfx_vec_raw <<EOF

[[vector]]
name   = "bad-order"
preset = "$VP_KDE"
layers = ["targets/workstation", "features/games"]
expect = "valid"
parent = ["bentoo:$VP_KDE", "bentoo:features/games", "bentoo:targets/workstation"]

[[vector]]
name   = "bad-set"
preset = "$VP_KDE"
layers = ["targets/server", "targets/headless"]
expect = "invalid"
rules  = ["exclusive"]

[[vector]]
name   = "bad-verdict"
preset = "$VP_PLAIN"
layers = ["features/hardware/amd"]
expect = "invalid"
rules  = ["base"]
EOF
  run "$SCRIPT" --vectors
  status_is 1
  vector_line bad-order
  vector_line bad-set
  vector_line bad-verdict
  # the agreeing standard vectors are not reported
  no_vector_line musl-server-amd
}

# --- --static first ----------------------------------------------------------------

@test "C4 a vectors file failing --static exits 1 with the static gap and compares nothing" {
  vfx_tree
  vfx_vec_raw <<EOF

[[vector]]
name    = "with-comment"
preset  = "$VP_PLAIN"
layers  = ["features/hardware/intel"]
expect  = "valid"
parent  = ["bentoo:$VP_PLAIN", "bentoo:features/hardware/intel"]
comment = "not a vector key"

[[vector]]
name   = "would-disagree"
preset = "$VP_PLAIN"
layers = ["features/hardware/amd"]
expect = "invalid"
rules  = ["base"]
EOF
  run "$SCRIPT" --vectors
  status_is 1
  line_names vector-key with-comment comment
  ! grep -qF -- '--compose gave' <<<"$output" || {
    _dump "vectors were compared although --static failed"
    false
  }
}

# --- R7.4: the mode is documented ---------------------------------------------------

@test "R7.4 --help lists --vectors" {
  run "$SCRIPT" --help
  status_is 0
  line_names --vectors
}

@test "R7.4 the script header's mode list names --vectors" {
  local header
  header=$(awk 'NR > 1 && !/^#/ { exit } { print }' "$SCRIPT")
  grep -qE '^#[[:space:]]+--vectors' <<<"$header" || {
    echo "the header's mode list does not name --vectors" >&2
    false
  }
}
