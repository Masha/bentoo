#!/usr/bin/env bats
# bats file_tags=integration
#
# Integration -- Task 4.1: flavor layers targets/{workstation,server,headless,
# container} on the real tree, read back from Portage.
# Requirements: R2.1, R2.2, R2.3, R2.4, R2.5, R1.2 (and R4.10 on the real
# catalog).
#
# Every effect is measured against the SAME preset without the layer, so a
# check cannot pass because the preset already had the property: on
# desktop = none presets the global USE already lacks X, so R2.2/R2.3 are
# measured on packages whose IUSE turns X / wayland on by default.

load lib

PLAIN=default/linux/amd64/23.0
PLASMA=default/linux/amd64/23.0/desktop/plasma/systemd

setup() {
  need_portage
  CROOT0=$BATS_TEST_TMPDIR/croot-preset
  CROOT1=$BATS_TEST_TMPDIR/croot-layer
}

# --- catalog -----------------------------------------------------------------

@test "R2.5 targets/server lists sshd with its OpenRC and systemd names" {
  catalog_py '
l = [x for x in cat["layer"] if x["id"] == "targets/server"]
assert len(l) == 1, l
svc = l[0].get("services", [])
assert {"openrc": "sshd", "systemd": "sshd.service"} in svc, svc
'
}

@test "R4.10 workstation on a desktop = none preset is rejected naming desktop" {
  run "$SCRIPT" --compose "$PLAIN" targets/workstation
  status_is 1
  output=$(strip_ids "$output" "$PLAIN")
  line_names desktop
}

@test "R4.10 server, headless and container are rejected on a desktop preset" {
  for l in targets/server targets/headless targets/container; do
    run "$SCRIPT" --compose "$PLASMA" "$l"
    status_is 1
  done
}

# --- R2.1 workstation ------------------------------------------------------------

@test "R2.1 workstation on a desktop preset puts NetworkManager, CUPS and Flatpak in @profile, not @system" {
  compose_croot "$CROOT0" "$PLASMA"
  compose_croot "$CROOT1" "$PLASMA" targets/workstation
  local before profile system a
  before=$(pq "$CROOT0" set profile)
  profile=$(pq "$CROOT1" set profile)
  system=$(pq "$CROOT1" set system)
  for a in net-misc/networkmanager net-print/cups sys-apps/flatpak; do
    ! words_has "$before" "$a" || {
      echo "$a is in @profile without the layer: the check proves nothing" >&2
      false
    }
    words_has "$profile" "$a" || {
      echo "$a missing from @profile: [$profile]" >&2
      false
    }
    ! words_has "$system" "$a" || {
      echo "$a landed in @system" >&2
      false
    }
  done
}

# --- R2.2 / R2.3 server and headless -------------------------------------------------

# X and wayland are on for X_PKG / W_PKG on the bare preset (asserted, the
# hostile baseline) and off once LAYER is composed; the global USE lacks both.
assert_x_wayland_off() { # LAYER
  compose_croot "$CROOT0" "$PLAIN"
  compose_croot "$CROOT1" "$PLAIN" "$1"
  local x_pkg w_pkg
  x_pkg=$(first_with_default X media-libs/mesa x11-libs/gtk+ media-video/mpv)
  w_pkg=$(first_with_default wayland x11-wm/mutter kde-plasma/plasma-login-sessions www-client/chromium)
  words_has "$(pq "$CROOT0" use "$x_pkg")" X
  words_has "$(pq "$CROOT0" use "$w_pkg")" wayland
  ! words_has "$(pq "$CROOT1" use "$x_pkg")" X || {
    echo "$1: X still enabled on $x_pkg" >&2
    false
  }
  ! words_has "$(pq "$CROOT1" use "$w_pkg")" wayland || {
    echo "$1: wayland still enabled on $w_pkg" >&2
    false
  }
  local use
  use=$(pq "$CROOT1" var USE)
  ! words_has "$use" X && ! words_has "$use" wayland
}

@test "R2.2 server disables X and wayland globally, overriding packages that default them on" {
  assert_x_wayland_off targets/server
}

@test "R2.3 headless disables X and wayland globally, overriding packages that default them on" {
  assert_x_wayland_off targets/headless
}

@test "R2.3 headless adds no package to @profile" {
  compose_croot "$CROOT0" "$PLAIN"
  compose_croot "$CROOT1" "$PLAIN" targets/headless
  [ "$(pq "$CROOT1" set profile)" = "$(pq "$CROOT0" set profile)" ]
}

# --- R2.4 container ------------------------------------------------------------------

CONTAINER_MASKED=(
  sys-kernel/gentoo-kernel
  sys-kernel/gentoo-kernel-bin
  virtual/dist-kernel
  sys-kernel/linux-firmware
  sys-firmware/intel-microcode
  sys-boot/grub
)

@test "R2.4 container masks every kernel, firmware, bootloader and microcode version (visible without it)" {
  compose_croot "$CROOT0" "$PLAIN"
  compose_croot "$CROOT1" "$PLAIN" targets/container
  local a line bad=0
  for a in "${CONTAINER_MASKED[@]}"; do
    [ -n "$(pq "$CROOT0" visible "$a")" ] || {
      echo "$a is not visible even without the layer: the check proves nothing" >&2
      false
    }
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      if [[ ",${line#* }," != *",package.mask,"* ]]; then
        echo "not masked by package.mask under targets/container: $line" >&2
        bad=1
      fi
    done < <(pq "$CROOT1" masks "$a")
  done
  [ "$bad" -eq 0 ]
}

@test "R2.4 container: requesting a kernel reports it as masked" {
  compose_croot "$CROOT1" "$PLAIN" targets/container
  run env PORTAGE_CONFIGROOT="$CROOT1" emerge -p --nodeps sys-kernel/gentoo-kernel
  [ "$status" -ne 0 ]
  [[ $output == *"masked by: package.mask"* ]]
}

@test "R2.4 hostile: container does not mask the ordinary userland" {
  compose_croot "$CROOT1" "$PLAIN" targets/container
  for a in app-shells/bash sys-apps/coreutils sys-apps/portage; do
    [ -n "$(pq "$CROOT1" visible "$a")" ] || {
      echo "targets/container masks $a" >&2
      false
    }
  done
}

# --- R2.6 container keeps the build base -----------------------------------------
# Hostile half of R2.4: a kernel mask written as `sys-kernel/*` also masks
# sys-kernel/linux-headers, which glibc needs, and @system stops resolving.

@test "R2.6 container keeps sys-kernel/linux-headers and sys-libs/glibc unmasked" {
  compose_croot "$CROOT0" "$PLAIN"
  compose_croot "$CROOT1" "$PLAIN" targets/container
  local a line
  for a in sys-kernel/linux-headers sys-libs/glibc; do
    [ -n "$(pq "$CROOT1" visible "$a")" ] || {
      echo "targets/container leaves no visible $a" >&2
      false
    }
    # Only a package.mask the layer ADDS counts: ::gentoo already masks some
    # old versions (glibc-2.19-r3), and those are no concern of this layer.
    local before
    before=$(pq "$CROOT0" masks "$a")
    while IFS= read -r line; do
      [[ ",${line#* }," != *",package.mask,"* ]] && continue
      grep -qxF -- "$line" <<<"$before" && continue
      echo "masked by package.mask under targets/container: $line" >&2
      false
    done < <(pq "$CROOT1" masks "$a")
  done
}

@test "R2.6 container: @system resolves" {
  compose_croot "$CROOT1" "$PLAIN" targets/container
  run isolated_emerge "$CROOT1" -p @system
  resolves_ok
}

# --- R2.7 container excludes hardware layers (real catalog) -----------------------

@test "R2.7 container with any features/hardware/* layer is rejected naming the pair" {
  local hw n=0
  for hw in $(catalog_py 'print("\n".join(l["id"] for l in cat["layer"] if l["id"].startswith("features/hardware/")))'); do
    n=$((n + 1))
    run "$SCRIPT" --compose "$PLAIN" targets/container "$hw"
    status_is 1
    line_names targets/container "$hw"
  done
  [ "$n" -ge 4 ]
}
