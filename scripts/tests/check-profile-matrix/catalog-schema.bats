#!/usr/bin/env bats
# Unit -- Task 2.2: catalog schema checks of `--static`.
# Requirements: R4.1, R4.2, R4.3, R4.4, R4.5, R4.6.
#
# Contract (design.md C3 / "Data Models", schema 2): top-level `schema = 2`,
# [attributes], [types.*], [[preset]], [[layer]]; ids are paths relative to
# profiles/; preset ids equal the amd64 lines of profiles/profiles.desc;
# features/branding is not a layer. Failure lines are
# `catalog: <rule>: <id/key>`; every failure is reported, then exit 1.
#
# Each rule is exercised from both sides. For the identity rules (an id
# matches a directory, a preset matches a profiles.desc line, a conflict
# matches its mirror) the fixture that would make the rule fire WRONGLY comes
# first: near-identical ids that must stay apart, and differently-written
# inputs that must still match.

load lib/fixture

# --- R4.1: the valid half ---------------------------------------------------

@test "R4.1 a complete schema-2 catalog matching its tree passes --static: exit 0" {
  fx_standard
  run "$SCRIPT" --static
  status_is 0
}

@test "R4.2 features/branding and the features/hardware container dir need no catalog entry" {
  # fx_standard has both directories and neither has an entry; this pins the
  # exception on its own so a regression names it.
  fx_standard
  [ -d "$FX/profiles/features/branding" ]
  [ -d "$FX/profiles/features/hardware" ]
  run "$SCRIPT" --static
  status_is 0
}

# --- R4.1: schema = 2 -------------------------------------------------------

@test "R4.1 schema = 1 is rejected naming schema" {
  FX_SCHEMA='schema = 1' fx_standard
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names schema
}

@test "R4.1 a catalog without a schema key is rejected naming schema" {
  FX_SCHEMA= fx_standard
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names schema
}

@test "R4.1 schema = true is not schema 2 (a boolean must not pass as an integer)" {
  FX_SCHEMA='schema = true' fx_standard
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names schema
}

@test "R4.1 schema = \"2\" (a string) is not schema 2" {
  FX_SCHEMA='schema = "2"' fx_standard
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names schema
}

@test "R4.1 a catalog that is not valid TOML exits 1 naming catalog.toml" {
  fx_standard
  printf '\n[[layer]\nid = "broken\n' >>"$CAT"
  run "$SCRIPT" --static
  status_is 1
  line_names_file catalog.toml
}

# --- R4.2: every layer directory has an entry --------------------------------

@test "R4.2 hostile: an undeclared targets/server-lite is caught although targets/server is declared" {
  fx_standard
  mkdir -p "$FX/profiles/targets/server-lite"
  printf '5\n' >"$FX/profiles/targets/server-lite/eapi"
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names targets/server-lite
}

@test "R4.2 an undeclared directory nested under features/hardware is named" {
  fx_standard
  mkdir -p "$FX/profiles/features/hardware/nvidia-open"
  printf '5\n' >"$FX/profiles/features/hardware/nvidia-open/eapi"
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names features/hardware/nvidia-open
}

@test "R4.2 an undeclared directory under features/ is named" {
  fx_standard
  mkdir -p "$FX/profiles/features/vr"
  printf '5\n' >"$FX/profiles/features/vr/eapi"
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names features/vr
}

# --- R4.3: every entry has a directory ---------------------------------------

@test "R4.3 hostile: features/hardware/nvidia-legacy without a directory is caught although nvidia has one" {
  fx_standard
  rm -r "$FX/profiles/features/hardware/nvidia-legacy" "$FX/layers/features/hardware/nvidia-legacy"
  # keep has_files consistent so only R4.3 can fire for nvidia-legacy
  sed -i '/^id          = "features\/hardware\/nvidia-legacy"$/,/^has_files/ s/^has_files = true$/has_files = false/' "$CAT"
  # guard: the mutation really happened (a silent sed no-op would leave R5.5 to fire)
  [ "$(sed -n '/"features\/hardware\/nvidia-legacy"$/,/^has_files/p' "$CAT" | tail -n1)" = 'has_files = false' ]
  [ -d "$FX/profiles/features/hardware/nvidia" ]
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names features/hardware/nvidia-legacy
}

@test "R4.3 a layer entry with no directory is named" {
  fx_standard
  FX_NODIR=1 fx_layer targets/router flavor 'base = { desktop = ["none"] }'
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names targets/router
}

@test "R4.3 a preset entry (also in profiles.desc) with no directory is named" {
  fx_standard
  FX_NODIR=1 fx_preset default/linux/amd64/23.0/ghost openrc true none
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names default/linux/amd64/23.0/ghost
}

# --- R4.4: presets == amd64 lines of profiles.desc ---------------------------

@test "R4.4 hostile: a desc-only preset whose id extends a catalog preset id is named" {
  fx_standard
  fx_preset_dir default/linux/amd64/23.0/sd   # in desc and on disk, not in the catalog
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names default/linux/amd64/23.0/sd
}

@test "R4.4 hostile: desc lines written differently still match (comments, blanks, spaces, other arches)" {
  fx_standard
  # Rewrite profiles.desc with the same three amd64 presets, one of them
  # space-separated instead of tab-separated, plus lines the rule must ignore.
  {
    printf '# Select with: eselect profile set bentoo:<id>\n\n'
    printf 'amd64\t%s\tstable\n' "$P_PLAIN"
    printf 'amd64   %s   stable\n' "$P_PURE"
    printf 'x86\tdefault/linux/x86/23.0\tstable\n'
    printf '\n# trailing comment\n'
    printf 'amd64\t%s\tstable\n' "$P_KDE"
  } >"$DESC"
  run "$SCRIPT" --static
  status_is 0
}

@test "R4.4 a catalog-only preset is named" {
  fx_standard
  FX_NODESC=1 fx_preset default/linux/amd64/23.0/orphan openrc true none
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names default/linux/amd64/23.0/orphan
}

@test "R4.4 presets on each side only are both named" {
  fx_standard
  FX_NODESC=1 fx_preset default/linux/amd64/23.0/only-catalog openrc true none
  fx_preset_dir default/linux/amd64/23.0/only-desc
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names default/linux/amd64/23.0/only-catalog
  catalog_line_names default/linux/amd64/23.0/only-desc
}

# --- R4.5: unknown keys and values ------------------------------------------

@test "R4.5 an unknown top-level key is named" {
  fx_standard
  sed -i '1a colour = "blue"' "$CAT"
  [ "$(sed -n 2p "$CAT")" = 'colour = "blue"' ] # guard: top level, before [attributes]
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names colour
}

@test "R4.5 an unknown preset key is named with its preset" {
  fx_standard
  sed -i "/^id       = \"default\/linux\/amd64\/23.0\/pure64\"\$/a kernel   = \"gentoo-kernel\"" "$CAT"
  grep -qx 'kernel   = "gentoo-kernel"' "$CAT" # guard: the key was inserted
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names kernel "$P_PURE"
}

@test "R4.5 hostile: a near-miss of a known layer key (conflict, has_file) is unknown, named with its layer" {
  fx_base
  fx_layer features/hardware/amd hardware 'conflict = ["features/hardware/intel"]'
  fx_layer features/hardware/intel hardware 'has_file = true'
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names conflict features/hardware/amd
  catalog_line_names has_file features/hardware/intel
}

@test "R4.5 a preset attribute value outside [attributes] is named with its preset" {
  fx_base
  fx_raw <<'EOF'

[[preset]]
id       = "default/linux/amd64/23.0/kwin"
status   = "stable"
init     = "openrc"
multilib = true
desktop  = "kde"
hardened = false
selinux  = false
toolchain = "gcc"
libc     = "glibc"
EOF
  fx_preset_dir default/linux/amd64/23.0/kwin
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names 'kde|desktop' default/linux/amd64/23.0/kwin
}

@test "R4.5 hostile: multilib = 1 is outside [true, false] (an integer must not pass as a boolean)" {
  fx_base
  fx_raw <<'EOF'

[[preset]]
id       = "default/linux/amd64/23.0/one"
status   = "stable"
init     = "openrc"
multilib = 1
desktop  = "none"
hardened = false
selinux  = false
toolchain = "gcc"
libc     = "glibc"
EOF
  fx_preset_dir default/linux/amd64/23.0/one
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names 'multilib|1' default/linux/amd64/23.0/one
}

@test "R4.5 hostile: multilib = \"true\" (a string) is outside [true, false]" {
  fx_base
  fx_raw <<'EOF'

[[preset]]
id       = "default/linux/amd64/23.0/quoted"
status   = "stable"
init     = "openrc"
multilib = "true"
desktop  = "none"
hardened = false
selinux  = false
toolchain = "gcc"
libc     = "glibc"
EOF
  fx_preset_dir default/linux/amd64/23.0/quoted
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names 'multilib|true' default/linux/amd64/23.0/quoted
}

@test "R4.5 a base value outside [attributes] is named with its layer" {
  fx_base
  fx_layer targets/server flavor 'base = { desktop = ["kde"] }'
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names 'kde|desktop' targets/server
}

@test "R4.5 a base key that is not an attribute is named with its layer" {
  fx_base
  fx_layer targets/server flavor 'base = { colour = ["red"] }'
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names colour targets/server
}

@test "R4.5 a layer type not declared in [types] is named with its layer" {
  fx_base
  fx_layer targets/server flavour
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names flavour targets/server
}

# --- ids are unique (design: id is the primary key) --------------------------

@test "ids: hostile: two layers whose ids share a prefix are distinct, not duplicates" {
  fx_base
  fx_layer targets/server flavor 'base = { desktop = ["none"] }'
  fx_layer targets/server-lite flavor 'base = { desktop = ["none"] }'
  run "$SCRIPT" --static
  status_is 0
}

@test "ids: the same layer id declared twice is rejected naming it" {
  fx_base
  fx_layer targets/server flavor 'base = { desktop = ["none"] }'
  fx_layer targets/server flavor 'base = { desktop = ["none"] }'
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names targets/server
}

# --- R4.6: conflicts are declared on both sides ------------------------------

@test "R4.6 a conflict declared by only one of the two layers names both" {
  fx_base
  fx_layer features/hardware/nvidia hardware 'conflicts = ["features/hardware/nvidia-legacy"]'
  fx_layer features/hardware/nvidia-legacy hardware
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names features/hardware/nvidia features/hardware/nvidia-legacy
}

@test "R4.6 hostile third element: A<->B symmetric, C lists A, A does not list C -- names C and A" {
  fx_base
  fx_layer features/hardware/nvidia hardware 'conflicts = ["features/hardware/nvidia-legacy"]'
  fx_layer features/hardware/nvidia-legacy hardware 'conflicts = ["features/hardware/nvidia"]'
  fx_layer features/hardware/nouveau hardware 'conflicts = ["features/hardware/nvidia"]'
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names features/hardware/nouveau features/hardware/nvidia
}

@test "R4.6 a conflict naming a layer that does not exist names both" {
  fx_base
  fx_layer features/hardware/amd hardware 'conflicts = ["features/hardware/radeon"]'
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names features/hardware/amd features/hardware/radeon
}

# --- every failure is reported, not the first --------------------------------

@test "--static reports every failure before exiting 1" {
  fx_base
  fx_layer features/hardware/amd hardware 'colour = "red"'
  fx_layer features/hardware/nvidia hardware 'conflicts = ["features/hardware/intel"]'
  fx_layer features/hardware/intel hardware
  FX_NODIR=1 fx_layer targets/router flavor
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names colour features/hardware/amd
  catalog_line_names features/hardware/nvidia features/hardware/intel
  catalog_line_names targets/router
}

# --- required keys and types (design.md "Data Models" table) -----------------

@test "types: a layer without description is rejected naming description and the layer" {
  fx_base
  fx_raw <<'TOML'

[[layer]]
id        = "features/hardware/amd"
type      = "hardware"
has_files = false
TOML
  mkdir -p "$FX/profiles/features/hardware/amd"
  printf '5\n' >"$FX/profiles/features/hardware/amd/eapi"
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names description features/hardware/amd
}

@test "types: a [types] rank that is not an integer is rejected naming rank" {
  fx_init
  fx_header
  sed -i '/^\[types.mix-in\]$/,/^rank/ s/^rank = 2$/rank = "2"/' "$CAT"
  grep -qx 'rank = "2"' "$CAT" # guard: the mutation happened
  fx_preset "$P_PLAIN" openrc true none
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names 'rank' 'mix-in|types.mix-in'
}

@test "types: hostile: rank = 2.0 (a float) is not an integer" {
  fx_init
  fx_header
  sed -i '/^\[types.mix-in\]$/,/^rank/ s/^rank = 2$/rank = 2.0/' "$CAT"
  grep -qx 'rank = 2.0' "$CAT"
  fx_preset "$P_PLAIN" openrc true none
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names 'rank' 'mix-in|types.mix-in'
}

@test "types: an exclusive that is not a boolean is rejected naming exclusive" {
  fx_init
  fx_header
  sed -i '/^\[types.flavor\]$/,/^exclusive/ s/^exclusive = true$/exclusive = "yes"/' "$CAT"
  grep -qx 'exclusive = "yes"' "$CAT"
  fx_preset "$P_PLAIN" openrc true none
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names 'exclusive' 'flavor|types.flavor'
}

@test "types: hostile: exclusive = 1 (an integer) is not a boolean" {
  fx_init
  fx_header
  sed -i '/^\[types.flavor\]$/,/^exclusive/ s/^exclusive = true$/exclusive = 1/' "$CAT"
  grep -qx 'exclusive = 1' "$CAT"
  fx_preset "$P_PLAIN" openrc true none
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names 'exclusive' 'flavor|types.flavor'
}

@test "types: an [attributes] table missing one of the seven is rejected naming it" {
  fx_init
  fx_header
  sed -i '/^toolchain = \["gcc", "llvm"\]$/d' "$CAT"
  [ -z "$(grep '^toolchain' "$CAT")" ] # guard: the attribute is gone
  fx_preset "$P_PLAIN" openrc true none
  sed -i '/^toolchain = "gcc"$/d' "$CAT" # the preset must not carry it either
  [ -z "$(grep '^toolchain' "$CAT")" ] # guard: neither does the preset
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names toolchain
}

@test "types: a services entry missing systemd is rejected naming the layer" {
  fx_base
  fx_layer targets/server flavor 'base = { desktop = ["none"] }' 'services = [{ openrc = "sshd" }]'
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names 'systemd|services' targets/server
}

@test "types: hostile: the complete services entry passes" {
  fx_base
  fx_layer targets/server flavor 'base = { desktop = ["none"] }' \
    'services = [{ openrc = "sshd", systemd = "sshd.service" }]'
  run "$SCRIPT" --static
  status_is 0
}

# --- a layer directory is one holding eapi -------------------------------------

@test "R4.2 hostile: a directory without eapi under targets/ (a grouping folder) needs no entry" {
  fx_standard
  mkdir -p "$FX/profiles/targets/docs"
  printf 'notes\n' >"$FX/profiles/targets/docs/README"
  [ ! -e "$FX/profiles/features/hardware/eapi" ]
  run "$SCRIPT" --static
  status_is 0
}

@test "R4.2 a directory holding eapi with no entry is named, even one level below a grouping folder" {
  fx_standard
  mkdir -p "$FX/profiles/features/audio/pro"
  printf '5\n' >"$FX/profiles/features/audio/pro/eapi"
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names features/audio/pro
}

@test "R4.3 an entry whose directory exists but holds no eapi is named" {
  fx_standard
  rm "$FX/profiles/features/hardware/intel/eapi"
  printf '# no eapi here\n' >"$FX/profiles/features/hardware/intel/make.defaults"
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names features/hardware/intel
}

# --- parent is optional, checked when present -----------------------------------

@test "parent: hostile: presets and layers holding only eapi (no parent) pass" {
  fx_standard
  [ -z "$(find "$FX/profiles" -name parent)" ]
  run "$SCRIPT" --static
  status_is 0
}

@test "parent: hostile: parent lines that resolve inside the tree pass (relative and :repo-local)" {
  fx_standard
  printf '../server\n' >"$FX/profiles/targets/headless/parent"
  printf ':features/branding\n' >"$FX/profiles/$P_PLAIN/parent"
  run "$SCRIPT" --static
  status_is 0
}

@test "parent: a parent line that resolves to nothing is named with its directory" {
  fx_standard
  printf '../does-not-exist\n' >"$FX/profiles/targets/headless/parent"
  run "$SCRIPT" --static
  status_is 1
  line_names targets/headless
}

# --- tech-review fix round (sub-task 2.2) ------------------------------------
# Added after the 2.2 tech review: each rule with its benign half beside it.

@test "layer id: features/branding declared as a [[layer]] is not a layer" {
  fx_standard
  FX_NODIR=1 fx_layer features/branding mix-in
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names not-a-layer features/branding
}

@test "layer id: a [[layer]] outside targets/ and features/ is not a layer" {
  fx_standard
  FX_NODIR=1 fx_layer "$P_PLAIN" mix-in
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names not-a-layer "$P_PLAIN"
}

@test "parent: an absolute line is named, even when the path exists on this host" {
  fx_standard
  printf '/etc\n' >"$FX/profiles/targets/headless/parent"
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names parent targets/headless
}

@test "parent: a relative line climbing out of profiles/ is named, even when it exists" {
  fx_standard
  printf '../../../../..\n' >"$FX/profiles/targets/headless/parent"
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names parent targets/headless
}

@test "parent: hostile: a :/abs line is named (it leaves the repository)" {
  fx_standard
  printf ':/etc\n' >"$FX/profiles/targets/headless/parent"
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names parent targets/headless
}

@test "parent: hostile: a master's line (gentoo:, listed in layout.conf masters) is out of scope and passes" {
  fx_standard
  printf 'gentoo:default/linux/amd64/23.0\n:features/branding\n' >"$FX/profiles/$P_PLAIN/parent"
  run "$SCRIPT" --static
  status_is 0
}

@test "parent: a repository name that is neither this repo nor a master is named" {
  fx_standard
  printf 'bento:targets/server\n' >"$FX/profiles/targets/headless/parent"
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names parent targets/headless
}

@test "parent: hostile: this repository's own name from layout.conf repo-name resolves and is checked" {
  fx_standard
  printf 'repo-name = bentoo\n' >>"$FX/metadata/layout.conf"
  printf 'other\n' >"$FX/profiles/repo_name"
  printf 'bentoo:targets/server\n' >"$FX/profiles/targets/headless/parent"
  run "$SCRIPT" --static
  status_is 0
  printf 'bentoo:targets/nope\n' >"$FX/profiles/targets/headless/parent"
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names parent targets/headless
}

@test "symlink: a symlinked layer directory is named and never read" {
  fx_standard
  mkdir -p "$BATS_TEST_TMPDIR/outside"
  printf '5\n' >"$BATS_TEST_TMPDIR/outside/eapi"
  ln -s "$BATS_TEST_TMPDIR/outside" "$FX/profiles/targets/linked"
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names symlink targets/linked
}

@test "id: a control character in an id cannot forge a second output line" {
  fx_standard
  FX_NODIR=1 fx_layer 'targets/x\ncatalog: forged: line' flavor
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names bad-id
  ! grep -q '^catalog: forged' <<<"$output"
}

@test "status: a preset whose catalog status differs from profiles.desc is named" {
  fx_standard
  sed -i "s|^amd64\t$P_PURE\tstable|amd64\t$P_PURE\texp|" "$DESC"
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names status-mismatch "$P_PURE"
}

@test "status: an amd64 line of profiles.desc with no status column is named" {
  fx_standard
  sed -i "s|^amd64\t$P_PURE\tstable|amd64\t$P_PURE|" "$DESC"
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names desc-status "$P_PURE"
}

@test "tree path: hostile: a valid tree reached by a relative or symlinked path still passes" {
  fx_standard
  printf ':features/branding\n' >"$FX/profiles/$P_PLAIN/parent"
  printf '../headless\n' >"$FX/profiles/targets/server/parent"
  ln -s "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR/via-link"
  BENTOO_TREE=$BATS_TEST_TMPDIR/via-link/tree run "$SCRIPT" --static
  status_is 0
  cd "$BATS_TEST_TMPDIR"
  BENTOO_TREE=tree run "$SCRIPT" --static
  status_is 0
}

@test "parent: a line resolving to profiles/ itself or to a grouping folder is not a profile directory" {
  fx_standard
  printf ':\n' >"$FX/profiles/targets/headless/parent"
  printf '..\n' >"$FX/profiles/features/hardware/amd/parent"
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names parent targets/headless
  catalog_line_names parent features/hardware/amd
}

@test "self-reference: a layer listing itself in conflicts or requires is a catalog error" {
  fx_standard
  fx_layer targets/router flavor 'conflicts = ["targets/router"]'
  fx_layer features/loop mix-in 'requires = ["features/loop"]'
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names self-conflict targets/router
  catalog_line_names self-require features/loop
}
