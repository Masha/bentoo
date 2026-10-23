# shellcheck shell=bash
# Schema-2 scratch tree plus a conformance-vectors file, for the story-002
# unit suites (catalog-schema-2.bats, vectors.bats, vectors-mode.bats).
#
# It writes the schema-2 catalog itself (design.md C1) instead of going
# through fx_header/fx_preset, so these suites pin the schema-2 contract
# independently of how the shared builders evolve; only fx_init (the overlay
# skeleton) and fx_layer come from lib/fixture.bash, which the suite loads
# first. The vectors file always ships with the tree because `--static`
# treats a missing profiles/catalog-vectors.toml as a gap (design.md "Error
# Handling Strategy"): a "valid tree" without it would not be valid.
#
# Fixture preset ids name no attribute value (no musl, glibc, llvm, gcc), so
# an assertion that a line "names musl" is never met by an id.

VP_PLAIN=default/linux/amd64/23.0              # openrc  multilib       none    gcc  glibc
VP_PURE=default/linux/amd64/23.0/pure64        # openrc  multilib false none    gcc  glibc
VP_KDE=default/linux/amd64/23.0/kde/sd         # systemd multilib       plasma  gcc  glibc
VP_CLANG=default/linux/amd64/23.0/clang        # openrc  multilib       none    llvm glibc
VP_TINY=default/linux/amd64/23.0/tiny          # openrc  multilib false none    gcc  musl
VP_TINYCL=default/linux/amd64/23.0/tiny/clang  # openrc  multilib false none    llvm musl

VECTORS_FILE_NAME=catalog-vectors.toml

# vfx_header -- `schema = 2`, the seven [attributes] of design.md C1 and the
# three layer types. VFX_SCHEMA replaces the schema line; VFX_SCHEMA= omits it.
vfx_header() {
  local schema=${VFX_SCHEMA-schema = 2}
  if [ -n "$schema" ]; then printf '%s\n' "$schema" >>"$CAT"; fi
  cat >>"$CAT" <<'EOF'

[attributes]
init      = ["openrc", "systemd"]
multilib  = [true, false]
desktop   = ["none", "generic", "plasma", "gnome"]
hardened  = [true, false]
selinux   = [true, false]
toolchain = ["gcc", "llvm"]
libc      = ["glibc", "musl"]

[types.flavor]
rank = 1
exclusive = true

[types.mix-in]
rank = 2
exclusive = false

[types.hardware]
rank = 3
exclusive = false
EOF
}

# vfx_preset ID INIT MULTILIB DESKTOP HARDENED SELINUX TOOLCHAIN LIBC
#   catalog entry + profiles.desc line + directory. Every value is written
#   VERBATIM as TOML, so a string value is passed with its quotes ('"gcc"')
#   and a hostile one without ('true').
vfx_preset() {
  printf '\n[[preset]]\nid        = "%s"\nstatus    = "stable"\ninit      = "%s"\nmultilib  = %s\ndesktop   = "%s"\nhardened  = %s\nselinux   = %s\ntoolchain = %s\nlibc      = %s\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" >>"$CAT"
  printf 'amd64\t%s\tstable\n' "$1" >>"$DESC"
  mkdir -p "$FX/profiles/$1"
  printf '5\n' >"$FX/profiles/$1/eapi"
}

# vfx_catalog -- skeleton + schema-2 header + six presets + eight layers. No
# layer declares `requires`, so the shipped vectors list it as having no
# instance. Both NVIDIA layers carry `base = { libc = ["glibc"] }`.
vfx_catalog() {
  fx_init
  vfx_header
  vfx_preset "$VP_PLAIN" openrc true none false false '"gcc"' '"glibc"'
  vfx_preset "$VP_PURE" openrc false none false false '"gcc"' '"glibc"'
  vfx_preset "$VP_KDE" systemd true plasma false false '"gcc"' '"glibc"'
  vfx_preset "$VP_CLANG" openrc true none false false '"llvm"' '"glibc"'
  vfx_preset "$VP_TINY" openrc false none false false '"gcc"' '"musl"'
  vfx_preset "$VP_TINYCL" openrc false none false false '"llvm"' '"musl"'
  fx_layer targets/server flavor 'base = { desktop = ["none"] }'
  fx_layer targets/headless flavor 'base = { desktop = ["none"] }'
  fx_layer targets/workstation flavor 'base = { desktop = ["generic", "plasma", "gnome"] }'
  fx_layer features/games mix-in 'base = { multilib = [true] }'
  fx_layer features/hardware/nvidia hardware \
    'conflicts = ["features/hardware/nvidia-legacy"]' 'base = { libc = ["glibc"] }'
  fx_layer features/hardware/nvidia-legacy hardware \
    'conflicts = ["features/hardware/nvidia"]' 'base = { libc = ["glibc"] }'
  fx_layer features/hardware/amd hardware
  fx_layer features/hardware/intel hardware
  VEC=$FX/profiles/$VECTORS_FILE_NAME
}

# vfx_vector NAME -- the TOML of one standard vector. Every expected `parent`
# is computed by hand from the rule (type rank, then declaration order; a
# layer given twice counts once), never copied from --compose.
vfx_vector() {
  case $1 in
  unknown-preset-17-1)
    cat <<'EOF'

[[vector]]
name   = "unknown-preset-17-1"
preset = "default/linux/amd64/17.1"
layers = []
expect = "invalid"
rules  = ["unknown-preset"]
EOF
    ;;
  unknown-layer-router)
    cat <<EOF

[[vector]]
name   = "unknown-layer-router"
preset = "$VP_PLAIN"
layers = ["targets/router"]
expect = "invalid"
rules  = ["unknown-layer"]
EOF
    ;;
  exclusive-two-flavors)
    cat <<EOF

[[vector]]
name   = "exclusive-two-flavors"
preset = "$VP_PLAIN"
layers = ["targets/server", "targets/headless"]
expect = "invalid"
rules  = ["exclusive"]
EOF
    ;;
  conflict-nvidia-pair)
    cat <<EOF

[[vector]]
name   = "conflict-nvidia-pair"
preset = "$VP_PLAIN"
layers = ["features/hardware/nvidia", "features/hardware/nvidia-legacy"]
expect = "invalid"
rules  = ["conflict"]
EOF
    ;;
  base-musl-nvidia)
    cat <<EOF

[[vector]]
name   = "base-musl-nvidia"
preset = "$VP_TINY"
layers = ["features/hardware/nvidia"]
expect = "invalid"
rules  = ["base"]
EOF
    ;;
  two-rules-flavors-on-desktop)
    # exclusive (two flavors) AND base (both need desktop = none)
    cat <<EOF

[[vector]]
name   = "two-rules-flavors-on-desktop"
preset = "$VP_KDE"
layers = ["targets/server", "targets/headless"]
expect = "invalid"
rules  = ["exclusive", "base"]
EOF
    ;;
  duplicate-layer-amd)
    cat <<EOF

[[vector]]
name   = "duplicate-layer-amd"
preset = "$VP_PLAIN"
layers = ["features/hardware/amd", "features/hardware/amd"]
expect = "valid"
parent = ["bentoo:$VP_PLAIN", "bentoo:features/hardware/amd"]
EOF
    ;;
  rank-order-desktop)
    cat <<EOF

[[vector]]
name   = "rank-order-desktop"
preset = "$VP_KDE"
layers = ["features/hardware/amd", "features/games", "targets/workstation"]
expect = "valid"
parent = [
  "bentoo:$VP_KDE",
  "bentoo:targets/workstation",
  "bentoo:features/games",
  "bentoo:features/hardware/amd",
]
EOF
    ;;
  musl-server-amd)
    cat <<EOF

[[vector]]
name   = "musl-server-amd"
preset = "$VP_TINY"
layers = ["targets/server", "features/hardware/amd"]
expect = "valid"
parent = ["bentoo:$VP_TINY", "bentoo:targets/server", "bentoo:features/hardware/amd"]
EOF
    ;;
  llvm-headless)
    cat <<EOF

[[vector]]
name   = "llvm-headless"
preset = "$VP_CLANG"
layers = ["targets/headless"]
expect = "valid"
parent = ["bentoo:$VP_CLANG", "bentoo:targets/headless"]
EOF
    ;;
  *)
    printf 'vfx_vector: no standard vector %s\n' "$1" >&2
    return 1
    ;;
  esac
}

VFX_STANDARD_VECTORS=(
  unknown-preset-17-1 unknown-layer-router exclusive-two-flavors
  conflict-nvidia-pair base-musl-nvidia two-rules-flavors-on-desktop
  duplicate-layer-amd rank-order-desktop musl-server-amd llvm-headless
)

# vfx_vectors [EXCEPT-NAME...] -- write the vectors file: schema, the
# rules_without_instance line, then every standard vector but EXCEPT-NAME.
#   VFX_VSCHEMA replaces the schema line (VFX_VSCHEMA= omits it);
#   VFX_WITHOUT replaces the rules_without_instance line (VFX_WITHOUT= omits it).
vfx_vectors() {
  local name skip x
  {
    printf '# fixture conformance vectors (story 002)\n'
    local schema=${VFX_VSCHEMA-schema = 2}
    if [ -n "$schema" ]; then printf '%s\n' "$schema"; fi
    local without=${VFX_WITHOUT-rules_without_instance = [\"requires\"]}
    if [ -n "$without" ]; then printf '%s\n' "$without"; fi
    for name in "${VFX_STANDARD_VECTORS[@]}"; do
      skip=0
      for x in "$@"; do [ "$x" = "$name" ] && skip=1; done
      [ "$skip" -eq 1 ] || vfx_vector "$name"
    done
  } >"$VEC"
}

# vfx_vec_raw -- append stdin verbatim to the vectors file.
vfx_vec_raw() { cat >>"$VEC"; }

# vfx_tree -- the complete valid fixture: catalog + every standard vector.
vfx_tree() {
  vfx_catalog
  vfx_vectors
}

# vector_line NAME [TEXT...] -- some output line starts with `vector NAME:`
# (the --vectors mismatch format of design.md "Error Handling Strategy") and
# holds every TEXT verbatim. The colon keeps NAME whole: `vector a:` is never
# met by a line about `vector a-b:`.
vector_line() {
  local name=$1 line t ok
  shift
  while IFS= read -r line; do
    [[ $line == "vector $name:"* ]] || continue
    ok=1
    for t in "$@"; do
      [[ $line == *"$t"* ]] || {
        ok=0
        break
      }
    done
    ((ok)) && return 0
  done <<<"$output"
  _dump "no 'vector $name:' line holds all of: $*"
  return 1
}

# no_vector_line NAME -- no output line reports a mismatch for vector NAME.
no_vector_line() {
  if grep -qF -- "vector $1:" <<<"$output"; then
    _dump "vector $1 was reported as a mismatch"
    return 1
  fi
}
