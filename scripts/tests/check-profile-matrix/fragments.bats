#!/usr/bin/env bats
# Unit -- Task 2.3: fragment tree checks of `--static`.
# Requirements: R5.1, R5.2, R5.3, R5.4, R5.5 (and R4.3 for layers/<unknown-id>).
#
# Contract (design.md C4): a fragment is layers/<id>/etc/**/<x>.d/<file>;
# the file name contains `bentoo-`; no symlink; no execute bit; nothing
# outside layers/<id>/etc/; has_files = true <=> layers/<id>/ exists;
# layers/<id> with an id that is not a catalog layer fails.
#
# A failure must name the offending file (or layer). Paths are matched by
# their tail, so a tree-relative or an absolute spelling both count.

load lib/fixture

setup() {
  fx_standard   # server + nvidia + nvidia-legacy carry conforming fragments
}

# --- the valid half ---------------------------------------------------------

@test "R5.x a conforming fragment tree passes: exit 0" {
  run "$SCRIPT" --static
  status_is 0
}

@test "R5.1 hostile: a .d directory deeper below etc/ is still conforming (etc/**/<x>.d/)" {
  fx_frag features/hardware/nvidia etc/X11/xorg.conf.d/50-bentoo-nvidia.conf
  run "$SCRIPT" --static
  status_is 0
}

@test "R5.2 hostile: bentoo- at the very start of the name is conforming" {
  fx_frag targets/server etc/sysctl.d/bentoo-server-extra.conf
  run "$SCRIPT" --static
  status_is 0
}

# --- R5.1: only inside a *.d directory below etc/ ----------------------------

@test "R5.1 a file directly in etc/ is named" {
  fx_frag targets/server etc/50-bentoo-server.conf
  run "$SCRIPT" --static
  status_is 1
  line_names_file targets/server/etc/50-bentoo-server.conf
}

@test "R5.1 a file in an etc/ subdirectory that is not a .d directory is named" {
  fx_frag targets/server etc/security/50-bentoo-server.conf
  run "$SCRIPT" --static
  status_is 1
  line_names_file targets/server/etc/security/50-bentoo-server.conf
}

@test "R5.1 hostile: a directory that merely contains .d (sysctl.d.bak, sysctl.dx) is not a .d directory" {
  fx_frag targets/server etc/sysctl.d.bak/50-bentoo-server.conf
  fx_frag targets/server etc/sysctl.dx/50-bentoo-server.conf
  run "$SCRIPT" --static
  status_is 1
  line_names_file targets/server/etc/sysctl.d.bak/50-bentoo-server.conf
  line_names_file targets/server/etc/sysctl.dx/50-bentoo-server.conf
}

@test "R5.1 hostile: a file in a plain subdirectory of a .d directory is not directly in a .d directory" {
  fx_frag targets/server etc/sysctl.d/extra/50-bentoo-server.conf
  run "$SCRIPT" --static
  status_is 1
  line_names_file targets/server/etc/sysctl.d/extra/50-bentoo-server.conf
}

@test "R5.1 a .d directory outside etc/ is named" {
  fx_frag targets/server usr/lib/sysctl.d/50-bentoo-server.conf
  run "$SCRIPT" --static
  status_is 1
  line_names_file targets/server/usr/lib/sysctl.d/50-bentoo-server.conf
}

@test "R5.1 hostile: an etc/ that is not directly under layers/<id>/ does not count as etc/" {
  fx_frag targets/server opt/etc/sysctl.d/50-bentoo-server.conf
  run "$SCRIPT" --static
  status_is 1
  line_names_file targets/server/opt/etc/sysctl.d/50-bentoo-server.conf
}

# --- R5.2: the name contains bentoo- -----------------------------------------

@test "R5.2 a fragment name without bentoo- is named" {
  fx_frag targets/server etc/sysctl.d/50-server.conf
  run "$SCRIPT" --static
  status_is 1
  line_names_file targets/server/etc/sysctl.d/50-server.conf
}

@test "R5.2 hostile: bentoo- in the directory name does not make the FILE name conforming" {
  fx_frag targets/server etc/bentoo-sysctl.d/50-server.conf
  run "$SCRIPT" --static
  status_is 1
  line_names_file targets/server/etc/bentoo-sysctl.d/50-server.conf
}

@test "R5.2 hostile: 'bentoo' without the dash is not 'bentoo-'" {
  fx_frag targets/server etc/sysctl.d/50-bentoo.conf
  run "$SCRIPT" --static
  status_is 1
  line_names_file targets/server/etc/sysctl.d/50-bentoo.conf
}

# --- R5.3: no symlink, no execute bit ----------------------------------------

@test "R5.3 hostile: a symlink is rejected even when its target is a conforming fragment" {
  ln -s 50-bentoo-server.conf "$FX/layers/targets/server/etc/sysctl.d/60-bentoo-server.conf"
  run "$SCRIPT" --static
  status_is 1
  line_names_file targets/server/etc/sysctl.d/60-bentoo-server.conf
}

@test "R5.3 hostile: a symlinked .d directory is rejected (the walk must not follow it)" {
  rm -r "$FX/layers/targets/server/etc/sysctl.d"
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere/sysctl.d"
  printf 'net.core.somaxconn = 4096\n' >"$BATS_TEST_TMPDIR/elsewhere/sysctl.d/50-bentoo-server.conf"
  ln -s "$BATS_TEST_TMPDIR/elsewhere/sysctl.d" "$FX/layers/targets/server/etc/sysctl.d"
  run "$SCRIPT" --static
  status_is 1
  line_names_file targets/server/etc/sysctl.d
}

@test "R5.3 a fragment with the execute bit is named" {
  chmod 0755 "$FX/layers/targets/server/etc/sysctl.d/50-bentoo-server.conf"
  run "$SCRIPT" --static
  status_is 1
  line_names_file targets/server/etc/sysctl.d/50-bentoo-server.conf
}

@test "R5.3 hostile: an execute bit for 'other' only (0645) is still an execute bit" {
  chmod 0645 "$FX/layers/targets/server/etc/sysctl.d/50-bentoo-server.conf"
  run "$SCRIPT" --static
  status_is 1
  line_names_file targets/server/etc/sysctl.d/50-bentoo-server.conf
}

# --- R5.4 / R5.5: has_files <=> layers/<id>/ exists ---------------------------

@test "R5.5/R5.4 hostile: nvidia-legacy's tree belongs to nvidia-legacy, not to the prefix id nvidia" {
  # nvidia has NO tree and has_files = false; nvidia-legacy HAS a tree and
  # has_files = true. A walk that attributes layers/features/hardware/
  # nvidia-legacy/... to the first id it starts with would see a tree for
  # nvidia and fire R5.4 wrongly.
  fx_base
  # setup() already built fx_standard; fx_base rewrites the catalog but leaves
  # those layer directories behind, so drop them or R4.2 names each of them.
  rm -rf "$FX/layers" "$FX/profiles/targets" "$FX/profiles/features/games" \
    "$FX/profiles/features/hardware"
  mkdir -p "$FX/layers"
  fx_layer features/hardware/nvidia hardware 'conflicts = ["features/hardware/nvidia-legacy"]'
  fx_layer features/hardware/nvidia-legacy hardware \
    'conflicts = ["features/hardware/nvidia"]' 'has_files = true'
  fx_frag features/hardware/nvidia-legacy etc/modprobe.d/50-bentoo-nvidia.conf
  run "$SCRIPT" --static
  status_is 0
}

@test "R5.4 a layer with a tree but no has_files key is named" {
  fx_base
  fx_raw <<'EOF'

[[layer]]
id          = "targets/server"
type        = "flavor"
description = "fixture layer"
base        = { desktop = ["none"] }
EOF
  mkdir -p "$FX/profiles/targets/server"
  printf '5\n' >"$FX/profiles/targets/server/eapi"
  fx_frag targets/server etc/sysctl.d/50-bentoo-server.conf
  run "$SCRIPT" --static
  status_is 1
  line_names targets/server
}

@test "R5.4 a layer with a tree and has_files = false is named" {
  fx_base
  fx_layer targets/server flavor 'base = { desktop = ["none"] }' 'has_files = false'
  fx_frag targets/server etc/sysctl.d/50-bentoo-server.conf
  run "$SCRIPT" --static
  status_is 1
  line_names targets/server
}

@test "R5.5 has_files = true without a tree is named" {
  rm -r "$FX/layers/targets/server"
  run "$SCRIPT" --static
  status_is 1
  line_names targets/server
}

@test "R5.5 hostile: nvidia-legacy declares has_files but only nvidia has a tree -- nvidia-legacy is named" {
  rm -r "$FX/layers/features/hardware/nvidia-legacy"
  [ -d "$FX/layers/features/hardware/nvidia" ]
  run "$SCRIPT" --static
  status_is 1
  line_names features/hardware/nvidia-legacy
}

# --- R4.3 through layers/: a tree for an id the catalog does not know ---------

@test "R4.3 layers/<id> for an id that is not a catalog layer is named" {
  fx_frag targets/bogus etc/sysctl.d/50-bentoo-bogus.conf
  run "$SCRIPT" --static
  status_is 1
  line_names targets/bogus
}

@test "R4.3 hostile: a tree for features/branding (a directory, but not a layer) is named" {
  fx_frag features/branding etc/sysctl.d/50-bentoo-branding.conf
  run "$SCRIPT" --static
  status_is 1
  line_names features/branding
}

# --- every failure is reported -----------------------------------------------

@test "R5.x failures in two layers are both reported" {
  fx_frag targets/server etc/sysctl.d/50-server.conf
  chmod 0755 "$FX/layers/features/hardware/nvidia/etc/modprobe.d/50-bentoo-nvidia.conf"
  run "$SCRIPT" --static
  status_is 1
  line_names_file targets/server/etc/sysctl.d/50-server.conf
  line_names_file features/hardware/nvidia/etc/modprobe.d/50-bentoo-nvidia.conf
}

# --- tech-review fix round (sub-task 2.3) ------------------------------------

@test "has_files hostile: an empty layers/<id>/ directory is not a tree (git never commits it)" {
  mkdir -p "$FX/layers/targets/headless"
  run "$SCRIPT" --static
  status_is 0
  rm -r "$FX/layers/features/hardware/nvidia"
  mkdir -p "$FX/layers/features/hardware/nvidia"
  run "$SCRIPT" --static
  status_is 1
  line_names features/hardware/nvidia
}

@test "symlink: a symlinked directory above every layer id is named as a symlink" {
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere/server/etc/sysctl.d"
  rm -r "$FX/layers/targets"
  ln -s "$BATS_TEST_TMPDIR/elsewhere" "$FX/layers/targets"
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names symlink layers/targets
}

@test "a stray file outside any layers/<id>/etc/ is a location failure, not an unknown layer" {
  printf 'notes\n' >"$FX/layers/README"
  run "$SCRIPT" --static
  status_is 1
  catalog_line_names fragment-location layers/README
}
