# shellcheck shell=bash
# Scratch-tree builders for the unit suite (../*.bats).
#
# Every unit test builds its own minimal overlay under $BATS_TEST_TMPDIR and
# exports BENTOO_TREE at it (the design's tree-root override), so no unit test
# reads the overlay checkout or the network (R6.11). Only the script under test
# is taken from the checkout.
#
# The suite is run as `bats scripts/tests/check-profile-matrix/` -- never with
# -r: integration/ holds the real-tree tests, which are slow and need Portage.

bats_require_minimum_version 1.5.0

load lib/assert

# The script under test. CHECK_PROFILE_MATRIX overrides it (used to run this
# suite against a copy); the default is the script next to this suite.
SCRIPT=${CHECK_PROFILE_MATRIX:-$BATS_TEST_DIRNAME/../../check-profile-matrix.sh}

# Fixture preset ids deliberately contain no attribute or type name (desktop,
# multilib, init, flavor, ...): an assertion that the output "names the
# attribute" must not be satisfied by an id that merely contains the word.
# P_TINYCL is the one musl + llvm preset: without it no valid conformance
# vector could reach those two values, and --static would fail every fx_base
# tree (fx_vectors).
P_PLAIN=default/linux/amd64/23.0             # openrc, multilib,       desktop none
P_PURE=default/linux/amd64/23.0/pure64       # openrc, multilib false, desktop none
P_KDE=default/linux/amd64/23.0/kde/sd        # systemd, multilib,      desktop plasma
P_TINYCL=default/linux/amd64/23.0/tiny/clang # openrc, multilib false, desktop none, llvm, musl

# fx_init -- empty overlay skeleton: layout.conf, repo_name, eapi, the
# features/branding directory (exists in the real tree, is NOT a layer), an
# empty catalog and an empty profiles.desc.
fx_init() {
  FX=$BATS_TEST_TMPDIR/tree
  CAT=$FX/profiles/catalog.toml
  DESC=$FX/profiles/profiles.desc
  mkdir -p "$FX/metadata" "$FX/profiles/features/branding" "$FX/layers"
  printf '%s\n' 'masters = gentoo' 'thin-manifests = true' \
    'profile-formats = portage-2 profile-repo-deps profile-bashrcs profile-set' \
    >"$FX/metadata/layout.conf"
  printf 'bentoo\n' >"$FX/profiles/repo_name"
  printf '5\n' >"$FX/profiles/eapi"
  printf '5\n' >"$FX/profiles/features/branding/eapi"
  printf '*x11-themes/bentoo-logos\n' >"$FX/profiles/features/branding/packages"
  : >"$CAT"
  : >"$DESC"
  VEC=$FX/profiles/catalog-vectors.toml
  export BENTOO_TREE=$FX
}

# fx_raw -- append stdin verbatim to the catalog.
fx_raw() { cat >>"$CAT"; }

# fx_header -- `schema = 2`, [attributes] and [types] exactly as design.md
# "Data Models". FX_SCHEMA replaces the schema line; FX_SCHEMA= omits it.
fx_header() {
  local schema=${FX_SCHEMA-schema = 2}
  if [ -n "$schema" ]; then printf '%s\n' "$schema" >>"$CAT"; fi
  fx_raw <<'EOF'

[attributes]
init     = ["openrc", "systemd"]
multilib = [true, false]
desktop  = ["none", "generic", "plasma", "gnome"]
hardened = [true, false]
selinux  = [true, false]
toolchain = ["gcc", "llvm"]
libc     = ["glibc", "musl"]

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

# fx_preset_dir ID -- the profiles.desc line and the directory of a preset,
# without its catalog entry.
fx_preset_dir() {
  printf 'amd64\t%s\tstable\n' "$1" >>"$DESC"
  mkdir -p "$FX/profiles/$1"
  printf '5\n' >"$FX/profiles/$1/eapi"
}

# fx_preset ID INIT MULTILIB DESKTOP [HARDENED SELINUX TOOLCHAIN LIBC]
#   catalog entry + profiles.desc line + directory. TOOLCHAIN and LIBC are
#   bare words written as TOML strings (default gcc, glibc).
#   FX_NODESC=1 skips the desc line, FX_NODIR=1 skips the directory.
fx_preset() {
  local id=$1 init=$2 ml=$3 desk=$4 hard=${5:-false} sel=${6:-false}
  local tc=${7:-gcc} libc=${8:-glibc}
  printf '\n[[preset]]\nid       = "%s"\nstatus   = "stable"\ninit     = "%s"\nmultilib = %s\ndesktop  = "%s"\nhardened = %s\nselinux  = %s\ntoolchain = "%s"\nlibc     = "%s"\n' \
    "$id" "$init" "$ml" "$desk" "$hard" "$sel" "$tc" "$libc" >>"$CAT"
  if [ -z "${FX_NODESC:-}" ]; then printf 'amd64\t%s\tstable\n' "$id" >>"$DESC"; fi
  if [ -z "${FX_NODIR:-}" ]; then
    mkdir -p "$FX/profiles/$id"
    printf '5\n' >"$FX/profiles/$id/eapi"
  fi
}

# fx_layer ID TYPE [TOML-LINE...]
#   catalog entry (id, type, description, extra lines; `has_files = false`
#   unless a line sets has_files) + profiles/<id>/eapi.
#   FX_NODIR=1 skips the directory.
fx_layer() {
  local id=$1 type=$2 line has=0
  shift 2
  printf '\n[[layer]]\nid          = "%s"\ntype        = "%s"\ndescription = "fixture layer"\n' \
    "$id" "$type" >>"$CAT"
  for line in "$@"; do
    printf '%s\n' "$line" >>"$CAT"
    if [[ $line == has_files* ]]; then has=1; fi
  done
  if [ "$has" -eq 0 ]; then printf 'has_files   = false\n' >>"$CAT"; fi
  if [ -z "${FX_NODIR:-}" ]; then
    mkdir -p "$FX/profiles/$id"
    printf '5\n' >"$FX/profiles/$id/eapi"
  fi
}

# fx_frag LAYER-ID RELPATH [MODE] -- a file at layers/<id>/<relpath>.
fx_frag() {
  local f=$FX/layers/$1/$2
  mkdir -p "${f%/*}"
  printf '# fixture fragment\n' >"$f"
  chmod "${3:-0644}" "$f"
}

# fx_vectors -- a conformance-vectors file (design.md C3) that meets every
# --static coverage rule over any fx_base catalog, whatever layers a test adds:
# one invalid vector per --compose rule (their ids are never checked by
# --static, so no rule needs a rules_without_instance listing), and two valid
# vectors with no layer over P_PLAIN (glibc, gcc) and P_TINYCL (musl, llvm).
# vectors.bats and its siblings build their own through lib/vectors-fixture.
fx_vectors() {
  local rule
  {
    printf 'schema = 2\nrules_without_instance = []\n'
    for rule in unknown-preset unknown-layer exclusive conflict requires base; do
      printf '\n[[vector]]\nname   = "fx-%s"\npreset = "%s"\nlayers = []\nexpect = "invalid"\nrules  = ["%s"]\n' \
        "$rule" "$P_PLAIN" "$rule"
    done
    for rule in "$P_PLAIN" "$P_TINYCL"; do
      printf '\n[[vector]]\nname   = "fx-valid-%s"\npreset = "%s"\nlayers = []\nexpect = "valid"\nparent = ["bentoo:%s"]\n' \
        "${rule//\//-}" "$rule" "$rule"
    done
  } >"$VEC"
}

# fx_base -- skeleton + header + the four fixture presets + fx_vectors, no
# layer.
fx_base() {
  fx_init
  fx_header
  fx_preset "$P_PLAIN" openrc true none
  fx_preset "$P_PURE" openrc false none
  fx_preset "$P_KDE" systemd true plasma
  fx_preset "$P_TINYCL" openrc false none false false llvm musl
  fx_vectors
}

# fx_standard -- a complete VALID fixture mirroring the v1 layer set:
# flavors (one with a fragment and a service), a mix-in with a base
# constraint, four hardware layers with the symmetric nvidia conflict and the
# two nvidia fragments.
fx_standard() {
  fx_base
  fx_layer targets/server flavor 'base = { desktop = ["none"] }' 'has_files = true' \
    'services = [{ openrc = "sshd", systemd = "sshd.service" }]'
  fx_frag targets/server etc/sysctl.d/50-bentoo-server.conf
  fx_layer targets/headless flavor 'base = { desktop = ["none"] }'
  fx_layer targets/workstation flavor 'base = { desktop = ["generic", "plasma", "gnome"] }'
  fx_layer features/games mix-in 'base = { multilib = [true] }'
  fx_layer features/hardware/nvidia hardware \
    'conflicts = ["features/hardware/nvidia-legacy"]' 'has_files = true'
  fx_frag features/hardware/nvidia etc/modprobe.d/50-bentoo-nvidia.conf
  fx_layer features/hardware/nvidia-legacy hardware \
    'conflicts = ["features/hardware/nvidia"]' 'has_files = true'
  fx_frag features/hardware/nvidia-legacy etc/modprobe.d/50-bentoo-nvidia.conf
  fx_layer features/hardware/amd hardware
  fx_layer features/hardware/intel hardware
}

# path_without CMD... -- a directory of symlinks to every executable on $PATH
# except CMD..., first match wins. Use as `run env PATH="$dir" ...` to make a
# prerequisite disappear without touching the host.
path_without() {
  local dir=$BATS_TEST_TMPDIR/path-without-${*// /-} d f n skip
  local -A seen=()
  local -a targets=()
  mkdir -p "$dir"
  local IFS=:
  for d in $PATH; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      n=${f##*/}
      [ -x "$f" ] && [ ! -d "$f" ] || continue
      [ -z "${seen[$n]:-}" ] || continue
      seen[$n]=1
      skip=0
      for x in "$@"; do [ "$n" = "$x" ] && skip=1; done
      [ "$skip" -eq 1 ] || targets+=("$f")
    done
  done
  unset IFS
  ln -s -t "$dir" -- "${targets[@]}"
  printf '%s' "$dir"
}

# tree_snapshot DIR -- every path with its type, mode and size, sorted: equal
# snapshots before and after a run mean the run wrote nothing there.
tree_snapshot() {
  find "$1" -printf '%P %y %m %s\n' | LC_ALL=C sort
}
