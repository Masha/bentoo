#!/usr/bin/env bats
# Unit -- Task 2.4: the composition validity rule and `--compose`.
# Requirements: R4.7, R4.8, R4.9, R4.10, R4.11, R4.12 (R6.7: both halves of
# every rule, so a forbidden combination is provably rejected by the rules).
#
# Contract (design.md "Composition validity rule" + C6): valid IFF exactly one
# preset; at most one layer per exclusive type; no selected pair declares a
# conflict; every `requires` is selected; every selected layer's `base` holds
# for the preset. On success stdout is exactly `bentoo:<preset-id>` then one
# `bentoo:<layer-id>` per layer, ordered by type rank then catalog declaration
# order, exit 0; a layer given twice counts once; the same selection in any
# input order gives byte-identical output. Otherwise exit 1 naming the unknown
# id / the exclusive type / the conflicting pair / the missing required layer
# / the violated base attribute.
#
# Identity is the core of this rule (is a selected layer "the same" as another,
# a required one, a conflicting one?), so the fixture is built to make it fire
# wrongly: ids that are prefixes of other ids (server / server-lite, games /
# games-vr, intel / intel-arc, nvidia / nvidia-legacy), types declared out of
# rank order with a rank (10) that sorts before 2 as text, and hardware layers
# declared in non-alphabetical order (intel before amd).

# Shared with `bentoo profile` (app-portage/bentoolkit): the Go tool must give
# the same verdict as --compose on every case below, and the same --static
# verdict on catalog-schema.bats and fragments.bats. Reuse, unchanged:
#   scripts/tests/check-profile-matrix/compose.bats         composition rule, parent order
#   scripts/tests/check-profile-matrix/catalog-schema.bats  catalog.toml schema 1
#   scripts/tests/check-profile-matrix/fragments.bats       layers/ tree rules
#   scripts/tests/check-profile-matrix/lib/fixture.bash     the fixture builders
# A schema bump in profiles/catalog.toml invalidates them together.

load lib/fixture

setup() {
  fx_init
  fx_raw <<'EOF'
schema = 1

[attributes]
init     = ["openrc", "systemd"]
multilib = [true, false]
desktop  = ["none", "generic", "plasma", "gnome"]
hardened = [true, false]
selinux  = [true, false]
llvm     = [true, false]

# declared out of rank order on purpose; 10 < 2 as text, 10 > 2 as a number
[types.hardware]
rank = 10
exclusive = false

[types.mix-in]
rank = 2
exclusive = false

[types.flavor]
rank = 1
exclusive = true
EOF
  fx_preset "$P_PLAIN" openrc true none
  fx_preset "$P_PURE" openrc false none
  fx_preset "$P_KDE" systemd true plasma
  # declaration order below is the tie-break order within a type
  fx_layer features/hardware/nvidia hardware 'conflicts = ["features/hardware/nvidia-legacy", "targets/container"]'
  fx_layer features/hardware/intel hardware 'conflicts = ["targets/container"]'
  fx_layer features/hardware/amd hardware 'conflicts = ["targets/container"]'
  fx_layer features/hardware/intel-arc hardware 'conflicts = ["targets/container"]'
  fx_layer features/games mix-in 'base = { multilib = [true] }'
  fx_layer features/games-vr mix-in 'requires = ["features/games"]'
  fx_layer features/streaming mix-in 'base = { multilib = [true], init = ["systemd"] }'
  fx_layer targets/server flavor 'base = { desktop = ["none"] }'
  fx_layer targets/server-lite flavor 'base = { desktop = ["none"] }'
  fx_layer targets/workstation flavor 'base = { desktop = ["generic", "plasma", "gnome"] }'
  # R2.7: container declares a conflict with every hardware layer (and each back)
  fx_layer targets/container flavor 'base = { desktop = ["none"] }' \
    'conflicts = ["features/hardware/nvidia", "features/hardware/intel", "features/hardware/amd", "features/hardware/intel-arc", "features/hardware/nvidia-legacy"]'
  fx_layer features/hardware/nvidia-legacy hardware 'conflicts = ["features/hardware/nvidia", "targets/container"]'
}

# expect_parent LINE... -- stdout of the last run is exactly these lines.
expect_parent() {
  output_is "$(printf '%s\n' "$@")"
}

# --- R4.11: a valid selection -------------------------------------------------

@test "R4.11 a selection breaking no rule is valid: exit 0, preset then layers" {
  run --separate-stderr "$SCRIPT" --compose "$P_KDE" targets/workstation features/games \
    features/hardware/nvidia features/hardware/amd
  status_is 0
  expect_parent "bentoo:$P_KDE" bentoo:targets/workstation bentoo:features/games \
    bentoo:features/hardware/nvidia bentoo:features/hardware/amd
}

@test "R4.11 a preset alone is a valid selection: exactly one line" {
  run --separate-stderr "$SCRIPT" --compose "$P_PURE"
  status_is 0
  expect_parent "bentoo:$P_PURE"
}

# --- R4.12: order is type rank, then declaration order ------------------------

@test "R4.12 hostile: order follows numeric type rank and declaration order, not input, text or alphabet" {
  # input order: hardware, flavor, hardware, mix-in -- amd typed before intel
  run --separate-stderr "$SCRIPT" --compose "$P_PLAIN" features/hardware/amd targets/server \
    features/hardware/intel features/games
  status_is 0
  # flavor (1) < mix-in (2) < hardware (10); intel is declared before amd
  expect_parent "bentoo:$P_PLAIN" bentoo:targets/server bentoo:features/games \
    bentoo:features/hardware/intel bentoo:features/hardware/amd
}

@test "R4.12 the same selection in two input orders gives byte-identical output" {
  "$SCRIPT" --compose "$P_PLAIN" features/hardware/amd targets/server features/hardware/intel \
    features/games features/hardware/nvidia >"$BATS_TEST_TMPDIR/a" 2>/dev/null
  "$SCRIPT" --compose "$P_PLAIN" features/games features/hardware/nvidia features/hardware/intel \
    targets/server features/hardware/amd >"$BATS_TEST_TMPDIR/b" 2>/dev/null
  [ -s "$BATS_TEST_TMPDIR/a" ]
  cmp "$BATS_TEST_TMPDIR/a" "$BATS_TEST_TMPDIR/b"
}

# --- duplicates count once (identity of a selected layer) ---------------------

@test "dedup hostile: a layer given twice, non-adjacent, appears once" {
  run --separate-stderr "$SCRIPT" --compose "$P_PLAIN" features/hardware/amd \
    features/hardware/nvidia features/hardware/amd
  status_is 0
  expect_parent "bentoo:$P_PLAIN" bentoo:features/hardware/nvidia bentoo:features/hardware/amd
}

@test "dedup hostile: ids sharing a prefix (intel, intel-arc) are two layers, both kept" {
  run --separate-stderr "$SCRIPT" --compose "$P_PLAIN" features/hardware/intel-arc features/hardware/intel
  status_is 0
  expect_parent "bentoo:$P_PLAIN" bentoo:features/hardware/intel bentoo:features/hardware/intel-arc
}

# --- R4.7: exclusive types ------------------------------------------------------

@test "R4.7 hostile: the same flavor given twice is ONE flavor -- valid, one line" {
  run --separate-stderr "$SCRIPT" --compose "$P_PLAIN" targets/server targets/server
  status_is 0
  expect_parent "bentoo:$P_PLAIN" bentoo:targets/server
}

@test "R4.7 hostile: two layers of a non-exclusive type are valid" {
  run --separate-stderr "$SCRIPT" --compose "$P_KDE" features/games features/streaming
  status_is 0
  expect_parent "bentoo:$P_KDE" bentoo:features/games bentoo:features/streaming
}

@test "R4.7 two different flavors (ids sharing a prefix) are invalid, naming the type" {
  run "$SCRIPT" --compose "$P_PLAIN" targets/server targets/server-lite
  status_is 1
  line_names flavor
}

# --- R4.8: conflicts ------------------------------------------------------------

@test "R4.8 hostile: a layer alone never conflicts with the layer its id prefixes" {
  run --separate-stderr "$SCRIPT" --compose "$P_PLAIN" features/hardware/nvidia
  status_is 0
  run --separate-stderr "$SCRIPT" --compose "$P_PLAIN" features/hardware/nvidia-legacy
  status_is 0
}

@test "R4.8 hostile: two hardware layers with no declared conflict are valid together" {
  run --separate-stderr "$SCRIPT" --compose "$P_PLAIN" features/hardware/nvidia features/hardware/amd
  status_is 0
  expect_parent "bentoo:$P_PLAIN" bentoo:features/hardware/nvidia bentoo:features/hardware/amd
}

@test "R4.8 two layers that declare a conflict are invalid, naming the pair" {
  run "$SCRIPT" --compose "$P_PLAIN" features/hardware/nvidia features/hardware/nvidia-legacy
  status_is 1
  line_names features/hardware/nvidia features/hardware/nvidia-legacy
}

@test "R4.8 hostile third element: the conflicting pair is caught when not adjacent in any order" {
  # nvidia is declared first and nvidia-legacy last; amd sits between them in
  # both input order and output order
  run "$SCRIPT" --compose "$P_PLAIN" features/hardware/nvidia features/hardware/amd \
    features/hardware/nvidia-legacy
  status_is 1
  line_names features/hardware/nvidia features/hardware/nvidia-legacy
}

# --- R4.9: requires -------------------------------------------------------------

@test "R4.9 hostile: a layer whose id extends the required id does not satisfy the requirement" {
  # games-vr requires games; "features/games-vr" starts with "features/games"
  run "$SCRIPT" --compose "$P_KDE" features/games-vr
  status_is 1
  line_names features/games
}

@test "R4.9 the requirement is met whatever the input order" {
  run --separate-stderr "$SCRIPT" --compose "$P_KDE" features/games-vr features/games
  status_is 0
  expect_parent "bentoo:$P_KDE" bentoo:features/games bentoo:features/games-vr
}

# --- R4.10: base constraints ------------------------------------------------------

@test "R4.10 hostile: a layer without base is valid on every preset" {
  for p in "$P_PLAIN" "$P_PURE" "$P_KDE"; do
    run --separate-stderr "$SCRIPT" --compose "$p" features/hardware/intel
    status_is 0
  done
}

@test "R4.10 a desktop-only flavor on a desktop = none preset is invalid, naming desktop" {
  run "$SCRIPT" --compose "$P_PLAIN" targets/workstation
  status_is 1
  line_names desktop
}

@test "R4.10 a desktop = none flavor on a plasma preset is invalid, naming desktop" {
  run "$SCRIPT" --compose "$P_KDE" targets/server
  status_is 1
  line_names desktop
}

@test "R4.10 a multilib-only mix-in on a multilib = false preset is invalid, naming multilib" {
  run "$SCRIPT" --compose "$P_PURE" features/games
  status_is 1
  line_names multilib
}

@test "R4.10 with two constrained attributes, the one that fails is named (init)" {
  # streaming: multilib = [true] holds on P_PLAIN, init = [systemd] does not
  run "$SCRIPT" --compose "$P_PLAIN" features/streaming
  status_is 1
  line_names init
}

# --- unknown ids --------------------------------------------------------------

@test "--compose: an unknown layer id is invalid, naming it" {
  run "$SCRIPT" --compose "$P_PLAIN" targets/router
  status_is 1
  line_names targets/router
}

@test "--compose: an unknown preset id is invalid, naming it" {
  run "$SCRIPT" --compose default/linux/amd64/17.1 targets/server
  status_is 1
  line_names default/linux/amd64/17.1
}

@test "--compose hostile: features/branding has a directory but is not a layer" {
  run "$SCRIPT" --compose "$P_PLAIN" features/branding
  status_is 1
  line_names features/branding
}

@test "--compose hostile: a layer id in the preset position is not a preset" {
  run "$SCRIPT" --compose targets/server
  status_is 1
  line_names targets/server
}

@test "--compose: a second preset is not a layer (exactly one preset)" {
  run "$SCRIPT" --compose "$P_PLAIN" "$P_PURE"
  status_is 1
  line_names "$P_PURE"
}

# --- R2.7: container excludes every hardware layer -------------------------------

@test "R2.7 hostile: container alone, and container with a mix-in, are valid" {
  run --separate-stderr "$SCRIPT" --compose "$P_PLAIN" targets/container
  status_is 0
  run --separate-stderr "$SCRIPT" --compose "$P_PLAIN" targets/container features/games
  status_is 0
  expect_parent "bentoo:$P_PLAIN" bentoo:targets/container bentoo:features/games
}

@test "R2.7 container with each hardware layer is invalid, naming the pair" {
  local hw
  for hw in nvidia intel amd intel-arc nvidia-legacy; do
    run "$SCRIPT" --compose "$P_PLAIN" targets/container "features/hardware/$hw"
    status_is 1
    line_names targets/container "features/hardware/$hw"
  done
}

@test "R2.7 hostile third element: container + amd + intel names a container pair" {
  run "$SCRIPT" --compose "$P_PLAIN" features/hardware/amd features/hardware/intel targets/container
  status_is 1
  line_names targets/container 'features/hardware/amd|features/hardware/intel'
}

# --- a catalog that does not parse is not a rejected selection -----------------

@test "--compose: an unparsable catalog exits 2 with nothing on stdout (not a rule rejection)" {
  printf 'schema = = 1\n' >>"$CAT"
  run --separate-stderr "$SCRIPT" --compose "$P_PLAIN" targets/server
  status_is 2
  output_is ""
}
