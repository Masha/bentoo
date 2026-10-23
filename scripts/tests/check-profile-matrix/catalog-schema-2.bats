#!/usr/bin/env bats
# Unit -- story 002, Task 1.1: `--static` speaks catalog schema 2.
# Requirements: R1.1, R1.2, R1.3, R1.4, R1.5 (and R3.1 on a fixture: a libc
# `base` refuses a musl preset through --compose).
#
# Contract (design.md C1/C4): top-level `schema = 2`, rejected otherwise with
# `expected schema = 2`, and a mismatched schema reports only that gap;
# [attributes] holds exactly init, multilib, desktop, hardened, selinux,
# toolchain = ["gcc", "llvm"] and libc = ["glibc", "musl"]; the schema-1 key
# `llvm` is gone everywhere; a preset's toolchain/libc is one of the declared
# STRINGS. Failure lines are `catalog: <rule>: <subject>[: <detail>]`.
#
# Identity is the trap here: `llvm` is a retired KEY, a toolchain VALUE and a
# path SEGMENT at once, and "musl"/"llvm" are valid values of the OTHER axis.
# The hostile fixtures come first: a value of one axis offered to the other
# must not be accepted, and the value/segment `llvm` must not be mistaken for
# the retired key.

load lib/fixture
load lib/vectors-fixture

# vfx_odd TOOLCHAIN LIBC -- the standard valid tree plus one preset `.../odd`
# whose toolchain and libc are written verbatim.
VP_ODD=default/linux/amd64/23.0/odd
vfx_odd() {
  vfx_tree
  vfx_preset "$VP_ODD" openrc false none false false "$1" "$2"
}

# --- R1.5: a value of the wrong axis or the wrong type (hostile first) ------

@test "R1.5 hostile: toolchain = \"musl\" (a libc value) is rejected naming the preset, toolchain and musl" {
  vfx_odd '"musl"' '"glibc"'
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names "$VP_ODD" toolchain musl
}

@test "R1.5 hostile: libc = \"llvm\" (a toolchain value) is rejected naming the preset, libc and llvm" {
  vfx_odd '"gcc"' '"llvm"'
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names "$VP_ODD" libc llvm
}

@test "R1.5 hostile: toolchain = true (a schema-1 boolean) is rejected naming the preset, toolchain and true" {
  vfx_odd 'true' '"glibc"'
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names "$VP_ODD" toolchain true
}

@test "R1.5 hostile: libc = false (a boolean) is rejected naming the preset, libc and false" {
  vfx_odd '"gcc"' 'false'
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names "$VP_ODD" libc false
}

@test "R1.5 libc = \"uclibc\" is rejected naming the preset, libc and uclibc" {
  vfx_odd '"gcc"' '"uclibc"'
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names "$VP_ODD" libc uclibc
}

@test "R1.5 toolchain = \"clang\" is rejected naming the preset, toolchain and clang" {
  vfx_odd '"clang"' '"glibc"'
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names "$VP_ODD" toolchain clang
}

@test "R1.5 a preset without libc is rejected naming libc and the preset" {
  vfx_tree
  # drop the FIRST preset's libc only (that preset is VP_PLAIN)
  awk '!d && /^libc      = "glibc"$/ { d = 1; next } 1' "$CAT" >"$CAT.new"
  mv "$CAT.new" "$CAT"
  [ "$(grep -c '^libc      = "' "$CAT")" -eq 5 ] # guard: exactly one of six presets lost it
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names libc "$VP_PLAIN"
}

@test "R1.5 a layer base naming a libc value that is not declared is rejected naming libc and the layer" {
  vfx_tree
  fx_layer features/hardware/vendor hardware 'base = { libc = ["uclibc"] }'
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names uclibc features/hardware/vendor
}

# --- R1.1 / R1.3: the valid half -------------------------------------------

@test "R1.1/R1.3 a schema-2 catalog with the seven attributes and string toolchain/libc passes --static: exit 0" {
  vfx_tree
  run "$SCRIPT" --static
  status_is 0
}

@test "R1.3 [attributes] without libc is rejected naming libc" {
  vfx_tree
  # gone from [attributes], every preset AND the nvidia bases, so only the
  # missing attribute itself can name libc
  sed -i '/libc/d' "$CAT"
  [ "$(grep -c 'libc' "$CAT")" -eq 0 ] # guard
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names libc
}

@test "R1.3 [attributes] without toolchain is rejected naming toolchain" {
  vfx_tree
  sed -i '/^toolchain = \["gcc", "llvm"\]$/d; /^toolchain = "/d' "$CAT"
  [ "$(grep -c '^toolchain' "$CAT")" -eq 0 ] # guard
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names toolchain
}

# --- R1.4: the retired llvm key ---------------------------------------------

@test "R1.4 hostile: the toolchain VALUE \"llvm\" and a preset id SEGMENT llvm are not the retired key: exit 0" {
  vfx_tree
  vfx_preset default/linux/amd64/23.0/llvm openrc true none false false '"llvm"' '"glibc"'
  fx_layer features/compiler-rt mix-in 'base = { toolchain = ["llvm"] }'
  run "$SCRIPT" --static
  status_is 0
}

@test "R1.4 [attributes] still declaring llvm is rejected naming llvm and [attributes]" {
  vfx_tree
  sed -i '/^libc      = \["glibc", "musl"\]$/a llvm      = [true, false]' "$CAT"
  grep -qx 'llvm      = \[true, false\]' "$CAT" # guard: inserted
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names llvm 'attributes'
}

@test "R1.4 a preset still carrying llvm = false is rejected naming llvm and the preset" {
  vfx_tree
  sed -i "/^id        = \"default\/linux\/amd64\/23.0\/pure64\"\$/a llvm      = false" "$CAT"
  grep -qx 'llvm      = false' "$CAT"
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names llvm "$VP_PURE"
}

@test "R1.4 a layer base still constraining llvm is rejected naming llvm and the layer" {
  vfx_tree
  fx_layer features/compiler-rt mix-in 'base = { llvm = [true] }'
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names llvm features/compiler-rt
}

# --- R1.2: schema = 2 ---------------------------------------------------------

@test "R1.2 schema = 1 is rejected naming schema and the expected value 2" {
  VFX_SCHEMA='schema = 1' vfx_tree
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names schema 'expected schema = 2'
}

@test "R1.2 hostile: schema = \"2\" (a string) is not schema 2" {
  VFX_SCHEMA='schema = "2"' vfx_tree
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names schema 'expected schema = 2'
}

@test "R1.2 hostile: schema = 2.0 (a float) is not schema 2" {
  VFX_SCHEMA='schema = 2.0' vfx_tree
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names schema 'expected schema = 2'
}

@test "R1.2 a catalog without schema is rejected naming the expected value 2" {
  VFX_SCHEMA='' vfx_tree
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names schema 'expected schema = 2'
}

@test "R1.2 a schema-1 catalog reports only the schema gap (nothing else is judged)" {
  # A genuine schema-1 shape: llvm booleans, no toolchain/libc. Judged under
  # schema 2 it would otherwise also raise unknown/required-key lines.
  fx_init
  printf 'schema = 1\n' >>"$CAT"
  cat >>"$CAT" <<'EOF'

[attributes]
init     = ["openrc", "systemd"]
multilib = [true, false]
desktop  = ["none", "generic", "plasma", "gnome"]
hardened = [true, false]
selinux  = [true, false]
llvm     = [true, false]

[types.hardware]
rank = 3
exclusive = false

[[preset]]
id       = "default/linux/amd64/23.0"
status   = "stable"
init     = "openrc"
multilib = true
desktop  = "none"
hardened = false
selinux  = false
llvm     = false
EOF
  printf 'amd64\tdefault/linux/amd64/23.0\tstable\n' >>"$DESC"
  mkdir -p "$FX/profiles/default/linux/amd64/23.0"
  printf '5\n' >"$FX/profiles/default/linux/amd64/23.0/eapi"
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names schema 'expected schema = 2'
  [ "$(grep -c '^catalog: ' <<<"$output")" -eq 1 ] || {
    _dump "a schema mismatch must report the schema gap alone"
    false
  }
}

# --- --compose over schema 2: a libc base (R3.1 on a fixture) ------------------

@test "R3.1 hostile: a layer with base libc = [glibc] is valid over a glibc preset whose toolchain is llvm" {
  vfx_tree
  run --separate-stderr "$SCRIPT" --compose "$VP_CLANG" features/hardware/nvidia
  status_is 0
  output_is "$(printf '%s\n' "bentoo:$VP_CLANG" bentoo:features/hardware/nvidia)"
}

@test "R3.1 a layer with base libc = [glibc] over a musl preset is invalid with a base line naming libc" {
  vfx_tree
  run "$SCRIPT" --compose "$VP_TINY" features/hardware/nvidia features/hardware/amd
  status_is 1
  line_names base features/hardware/nvidia libc
  # the rule fires for the constrained layer only, never for amd beside it
  if grep -qE '^compose: base: features/hardware/amd ' <<<"$output"; then
    _dump "amd (no libc constraint) was named by a base rule"
    false
  fi
}
