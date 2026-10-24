#!/usr/bin/env bats
# Unit -- story 002, Task 3.1: `--static` validates profiles/catalog-vectors.toml.
# Requirements: R4.1, R4.2, R4.3, R4.4, R4.5, R4.6, R4.7.
#
# Contract (design.md C3/C4): the vectors file declares the catalog's
# `schema`; each [[vector]] has name, preset, layers, expect; `parent` exactly
# when expect = "valid", `rules` exactly when expect = "invalid", no other key
# (rule vector-key); names are unique and a valid vector names only catalog
# ids (rule vector-id); every rule name of --compose (unknown-preset,
# unknown-layer, exclusive, conflict, requires, base) has a vector or is in
# rules_without_instance, a listed rule has no instance (for requires: no
# layer declares requires), and both libc values and both toolchain values
# appear in a VALID vector (rule vector-coverage); a missing file is a
# vector-schema gap. Every gap is reported, then exit 1. The line prefix is
# not pinned: a gap is any output line naming its rule and its subject.
#
# The coverage rules are identity rules (does THIS vector cover THAT rule or
# value?), so each comes with both hostile halves: a vector that looks like
# coverage but is not (named after a rule, or invalid over a musl preset), and
# coverage that does not look like it but is (a rule reached only inside a
# two-rule vector, values covered by different vectors).

load lib/fixture
load lib/vectors-fixture

# --- the valid half ------------------------------------------------------------

@test "vectors: the complete fixture (every coverage rule met) passes --static: exit 0" {
  vfx_tree
  run "$SCRIPT" --static
  status_is 0
}

# --- R4.5: rule coverage (hostile halves first) ----------------------------------

@test "R4.5 hostile: a vector NAMED after conflict but expecting base does not cover conflict" {
  vfx_catalog
  vfx_vectors conflict-nvidia-pair
  vfx_vec_raw <<EOF

[[vector]]
name   = "conflict-in-name-only"
preset = "$VP_TINY"
layers = ["features/hardware/nvidia-legacy"]
expect = "invalid"
rules  = ["base"]
EOF
  run "$SCRIPT" --static
  status_is 1
  line_names vector-coverage conflict
}

@test "R4.5 hostile converse: a rule reached only inside a two-rule vector is covered (exclusive): exit 0" {
  vfx_catalog
  vfx_vectors exclusive-two-flavors # two-rules-flavors-on-desktop still lists exclusive
  run "$SCRIPT" --static
  status_is 0
}

@test "R4.5 a rule with no vector and no rules_without_instance listing is named (conflict)" {
  vfx_catalog
  vfx_vectors conflict-nvidia-pair
  run "$SCRIPT" --static
  status_is 1
  line_names vector-coverage conflict
}

@test "R4.5 requires with no vector, once removed from rules_without_instance, is named" {
  vfx_catalog
  VFX_WITHOUT='rules_without_instance = []' vfx_vectors
  run "$SCRIPT" --static
  status_is 1
  line_names vector-coverage requires
}

# --- R4.6: a listed rule must have no instance ---------------------------------

@test "R4.6 a rule listed in rules_without_instance while a layer declares requires is named" {
  vfx_catalog
  fx_layer features/games-vr mix-in 'requires = ["features/games"]' 'base = { multilib = [true] }'
  vfx_vectors
  run "$SCRIPT" --static
  status_is 1
  line_names vector-coverage requires
}

@test "R4.6 hostile converse: requires with an instance, a vector and no listing is clean: exit 0" {
  vfx_catalog
  fx_layer features/games-vr mix-in 'requires = ["features/games"]' 'base = { multilib = [true] }'
  VFX_WITHOUT='rules_without_instance = []' vfx_vectors
  vfx_vec_raw <<EOF

[[vector]]
name   = "requires-games-vr"
preset = "$VP_KDE"
layers = ["features/games-vr"]
expect = "invalid"
rules  = ["requires"]
EOF
  run "$SCRIPT" --static
  status_is 0
}

# --- R4.7: attribute-value coverage by VALID vectors ----------------------------

@test "R4.7 hostile: an INVALID vector over a musl preset does not cover musl" {
  vfx_catalog
  vfx_vectors musl-server-amd # base-musl-nvidia (invalid, musl) remains
  run "$SCRIPT" --static
  status_is 1
  line_names vector-coverage musl
}

@test "R4.7 hostile converse: coverage is per value, not per pair (musl+gcc and glibc+llvm only): exit 0" {
  vfx_catalog
  vfx_vectors duplicate-layer-amd rank-order-desktop # the two glibc+gcc valid vectors
  # keep a duplicate-layer and an out-of-rank-order case (R4.8), both on musl+gcc
  vfx_vec_raw <<EOF

[[vector]]
name   = "duplicate-layer-musl"
preset = "$VP_TINY"
layers = ["features/hardware/amd", "features/hardware/amd"]
expect = "valid"
parent = ["bentoo:$VP_TINY", "bentoo:features/hardware/amd"]

[[vector]]
name   = "rank-order-musl"
preset = "$VP_TINY"
layers = ["features/hardware/amd", "targets/server"]
expect = "valid"
parent = ["bentoo:$VP_TINY", "bentoo:targets/server", "bentoo:features/hardware/amd"]
EOF
  run "$SCRIPT" --static
  status_is 0
}

@test "R4.7 no valid vector with toolchain = llvm is named (llvm)" {
  vfx_catalog
  vfx_vectors llvm-headless
  run "$SCRIPT" --static
  status_is 1
  line_names vector-coverage llvm
}

@test "R4.7 no valid vector with libc = glibc is named (glibc)" {
  vfx_catalog
  vfx_vectors duplicate-layer-amd rank-order-desktop llvm-headless
  vfx_vec_raw <<EOF

[[vector]]
name   = "musl-llvm-headless"
preset = "$VP_TINYCL"
layers = ["targets/headless"]
expect = "valid"
parent = ["bentoo:$VP_TINYCL", "bentoo:targets/headless"]
EOF
  run "$SCRIPT" --static
  status_is 1
  line_names vector-coverage glibc
}

@test "R4.7 no valid vector with toolchain = gcc is named (gcc)" {
  vfx_catalog
  vfx_vectors duplicate-layer-amd rank-order-desktop musl-server-amd
  vfx_vec_raw <<EOF

[[vector]]
name   = "musl-llvm-headless"
preset = "$VP_TINYCL"
layers = ["targets/headless"]
expect = "valid"
parent = ["bentoo:$VP_TINYCL", "bentoo:targets/headless"]
EOF
  run "$SCRIPT" --static
  status_is 1
  line_names vector-coverage gcc
}

# --- R4.3: unique names (identity) ----------------------------------------------

@test "R4.3 hostile: names sharing a prefix (base-musl-nvidia, base-musl-nvidia-legacy) are distinct: exit 0" {
  vfx_tree
  vfx_vec_raw <<EOF

[[vector]]
name   = "base-musl-nvidia-legacy"
preset = "$VP_TINY"
layers = ["features/hardware/nvidia-legacy"]
expect = "invalid"
rules  = ["base"]
EOF
  run "$SCRIPT" --static
  status_is 0
}

@test "R4.3 a duplicated name is named even when the two vectors are first and last and differ in content" {
  vfx_tree
  vfx_vec_raw <<EOF

[[vector]]
name   = "unknown-preset-17-1"
preset = "$VP_PLAIN"
layers = ["features/hardware/intel"]
expect = "valid"
parent = ["bentoo:$VP_PLAIN", "bentoo:features/hardware/intel"]
EOF
  run "$SCRIPT" --static
  status_is 1
  line_names vector-id unknown-preset-17-1
}

# --- R4.4: ids of valid vectors resolve -----------------------------------------

@test "R4.4 hostile: a valid vector naming a PREFIX of a real preset id (.../kde) is named with that id" {
  vfx_tree
  vfx_vec_raw <<'EOF'

[[vector]]
name   = "ghost-preset"
preset = "default/linux/amd64/23.0/kde"
layers = []
expect = "valid"
parent = ["bentoo:default/linux/amd64/23.0/kde"]
EOF
  run "$SCRIPT" --static
  status_is 1
  line_names vector-id ghost-preset default/linux/amd64/23.0/kde
}

@test "R4.4 hostile: a valid vector naming a layer that EXTENDS a real id (amd-pro) is named with that id" {
  vfx_tree
  vfx_vec_raw <<EOF

[[vector]]
name   = "ghost-layer"
preset = "$VP_PLAIN"
layers = ["features/hardware/amd-pro"]
expect = "valid"
parent = ["bentoo:$VP_PLAIN", "bentoo:features/hardware/amd-pro"]
EOF
  run "$SCRIPT" --static
  status_is 1
  line_names vector-id ghost-layer features/hardware/amd-pro
}

@test "R4.4 hostile: features/branding (a directory, not a layer) in a valid vector is named" {
  vfx_tree
  vfx_vec_raw <<EOF

[[vector]]
name   = "branding-is-not-a-layer"
preset = "$VP_PLAIN"
layers = ["features/branding"]
expect = "valid"
parent = ["bentoo:$VP_PLAIN", "bentoo:features/branding"]
EOF
  run "$SCRIPT" --static
  status_is 1
  line_names vector-id branding-is-not-a-layer features/branding
}

# --- R4.2: keys ------------------------------------------------------------------

@test "R4.2 a vector lacking any one of name, preset, layers, expect is named with the key" {
  local key
  for key in name preset layers expect; do
    rm -rf "$FX"
    vfx_tree
    {
      printf '\n[[vector]]\n'
      [ "$key" = name ] || printf 'name   = "probe-missing"\n'
      [ "$key" = preset ] || printf 'preset = "%s"\n' "$VP_PLAIN"
      [ "$key" = layers ] || printf 'layers = ["features/hardware/intel"]\n'
      [ "$key" = expect ] || printf 'expect = "valid"\n'
      printf 'parent = ["bentoo:%s", "bentoo:features/hardware/intel"]\n' "$VP_PLAIN"
    } | vfx_vec_raw
    run "$SCRIPT" --static
    status_is 1
    if [ "$key" = name ]; then
      line_names vector-key name
    else
      line_names vector-key probe-missing "$key"
    fi
  done
}

@test "R4.2 a valid vector carrying rules is named with rules" {
  vfx_tree
  vfx_vec_raw <<EOF

[[vector]]
name   = "valid-with-rules"
preset = "$VP_PLAIN"
layers = ["features/hardware/intel"]
expect = "valid"
parent = ["bentoo:$VP_PLAIN", "bentoo:features/hardware/intel"]
rules  = []
EOF
  run "$SCRIPT" --static
  status_is 1
  line_names vector-key valid-with-rules rules
}

@test "R4.2 an invalid vector carrying parent is named with parent" {
  vfx_tree
  vfx_vec_raw <<EOF

[[vector]]
name   = "invalid-with-parent"
preset = "$VP_TINY"
layers = ["features/hardware/nvidia"]
expect = "invalid"
rules  = ["base"]
parent = ["bentoo:$VP_TINY"]
EOF
  run "$SCRIPT" --static
  status_is 1
  line_names vector-key invalid-with-parent parent
}

@test "R4.2 hostile: a near-miss key (rule, singular) on an invalid vector is an unknown key, named" {
  vfx_tree
  vfx_vec_raw <<EOF

[[vector]]
name   = "near-miss-rule"
preset = "$VP_TINY"
layers = ["features/hardware/nvidia"]
expect = "invalid"
rule   = ["base"]
EOF
  run "$SCRIPT" --static
  status_is 1
  line_names vector-key near-miss-rule rule
}

@test "R4.2 any other key (comment) is named with the vector" {
  vfx_tree
  vfx_vec_raw <<EOF

[[vector]]
name    = "with-comment"
preset  = "$VP_PLAIN"
layers  = ["features/hardware/intel"]
expect  = "valid"
parent  = ["bentoo:$VP_PLAIN", "bentoo:features/hardware/intel"]
comment = "not a vector key"
EOF
  run "$SCRIPT" --static
  status_is 1
  line_names vector-key with-comment comment
}

@test "C3 a valid vector without parent is named with parent (parent exactly when expect = valid)" {
  vfx_tree
  vfx_vec_raw <<EOF

[[vector]]
name   = "valid-without-parent"
preset = "$VP_PLAIN"
layers = ["features/hardware/intel"]
expect = "valid"
EOF
  run "$SCRIPT" --static
  status_is 1
  line_names vector-key valid-without-parent parent
}

# --- R4.1: the file and its schema -----------------------------------------------

@test "R4.1 a missing vectors file is a vector-schema gap naming catalog-vectors.toml" {
  vfx_catalog
  [ ! -e "$VEC" ]
  run "$SCRIPT" --static
  status_is 1
  line_names vector-schema catalog-vectors.toml
}

@test "R4.1 a vectors schema different from the catalog's (1 vs 2) is a vector-schema gap naming schema" {
  vfx_catalog
  VFX_VSCHEMA='schema = 1' vfx_vectors
  run "$SCRIPT" --static
  status_is 1
  line_names vector-schema schema
}

@test "R4.1 hostile: vectors schema = \"2\" (a string) is not the catalog's schema 2" {
  vfx_catalog
  VFX_VSCHEMA='schema = "2"' vfx_vectors
  run "$SCRIPT" --static
  status_is 1
  line_names vector-schema schema
}

# --- every gap is reported -------------------------------------------------------

@test "vectors: --static reports every vector gap (coverage and key) before exiting 1" {
  vfx_catalog
  vfx_vectors conflict-nvidia-pair
  vfx_vec_raw <<EOF

[[vector]]
name    = "with-comment"
preset  = "$VP_PLAIN"
layers  = ["features/hardware/intel"]
expect  = "valid"
parent  = ["bentoo:$VP_PLAIN", "bentoo:features/hardware/intel"]
comment = "not a vector key"
EOF
  run "$SCRIPT" --static
  status_is 1
  line_names vector-coverage conflict
  line_names vector-key with-comment comment
}
