#!/usr/bin/env bats
# bats file_tags=integration
#
# Integration -- Task 4.3: hardware layers features/hardware/{nvidia,
# nvidia-legacy,amd,intel} on the real tree, read back from Portage.
# Requirements: R3.2, R3.3, R3.4, R3.5, R5.6 (and R4.8 on the real catalog).
#
# VIDEO_CARDS is compared as a SET against the same preset without the layer:
# ::gentoo's arch/amd64 already sets several cards, so "contains nvidia" alone
# would pass a layer that wiped the others with `-*` (the hybrid-machine bug
# the design warns about).

load lib

PLAIN=default/linux/amd64/23.0
PLASMA=default/linux/amd64/23.0/desktop/plasma/systemd

setup() {
  need_portage
  CROOT0=$BATS_TEST_TMPDIR/croot-preset
  CROOT1=$BATS_TEST_TMPDIR/croot-layer
}

sorted_words() { tr -s '[:space:]' '\n' <<<"$1" | sed '/^$/d' | LC_ALL=C sort -u; }

# --- R5.6 fragments --------------------------------------------------------------

@test "R5.6 nvidia and nvidia-legacy each ship their own modprobe.d fragment enabling nvidia-drm modeset=1" {
  local l f
  for l in nvidia nvidia-legacy; do
    f=$TREE/layers/features/hardware/$l/etc/modprobe.d/50-bentoo-nvidia.conf
    [ -f "$f" ] && [ ! -L "$f" ] || {
      echo "$f: missing or a symlink (each layer carries its own copy)" >&2
      false
    }
    # an active line, not a commented one
    grep -Eq '^[[:space:]]*options[[:space:]]+nvidia[-_]drm([[:space:]]+[^#]*)?[[:space:]]modeset=1([[:space:]]|$)' "$f" || {
      echo "$f: no active 'options nvidia-drm modeset=1' line" >&2
      false
    }
  done
}

# --- R3.2 nvidia ------------------------------------------------------------------

@test "R3.2 nvidia: VIDEO_CARDS is exactly the preset's value plus nvidia" {
  local p want got
  for p in "$PLAIN" "$PLASMA"; do
    compose_croot "$CROOT0" "$p"
    compose_croot "$CROOT1" "$p" features/hardware/nvidia
    want=$(sorted_words "$(pq "$CROOT0" var VIDEO_CARDS) nvidia")
    got=$(sorted_words "$(pq "$CROOT1" var VIDEO_CARDS)")
    [ "$want" = "$got" ] || {
      printf '%s: VIDEO_CARDS\n want: %s\n got:  %s\n' "$p" "$want" "$got" >&2
      false
    }
    rm -rf "$CROOT0" "$CROOT1"
  done
}

# --- R3.3 nvidia-legacy -------------------------------------------------------------

@test "R3.3 nvidia-legacy: nvidia-drivers resolves to 580.x and nothing >= 581 is visible" {
  compose_croot "$CROOT1" "$PLAIN" features/hardware/nvidia-legacy
  local best
  best=$(pq "$CROOT1" best x11-drivers/nvidia-drivers)
  [[ $best == x11-drivers/nvidia-drivers-580.* ]] || {
    echo "best visible nvidia-drivers under nvidia-legacy: '$best'" >&2
    false
  }
  local v
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    local ver=${v#x11-drivers/nvidia-drivers-}
    [ "${ver%%.*}" -lt 581 ] || {
      echo "visible under nvidia-legacy: $v" >&2
      false
    }
  done < <(pq "$CROOT1" visible x11-drivers/nvidia-drivers)
}

@test "R3.3 hostile baseline: without the legacy layer a newer branch IS visible (the hold is the layer's doing)" {
  compose_croot "$CROOT1" "$PLAIN" features/hardware/nvidia
  local best
  best=$(pq "$CROOT1" best x11-drivers/nvidia-drivers)
  [ -n "$best" ]
  local ver=${best#x11-drivers/nvidia-drivers-}
  [ "${ver%%.*}" -ge 581 ] || skip "::gentoo has no visible nvidia-drivers >= 581 today ($best): the hold is untestable"
}

# --- R3.4 amd / intel ----------------------------------------------------------------

assert_firmware_layer() { # LAYER [EXTRA-ATOM]
  compose_croot "$CROOT0" "$PLAIN"
  compose_croot "$CROOT1" "$PLAIN" "$1"
  [ "$(sorted_words "$(pq "$CROOT1" var VIDEO_CARDS)")" = "$(sorted_words "$(pq "$CROOT0" var VIDEO_CARDS)")" ] || {
    echo "$1 changed VIDEO_CARDS" >&2
    false
  }
  local before after added
  before=$(pq "$CROOT0" set profile)
  after=$(pq "$CROOT1" set profile)
  added=$(comm -13 <(sorted_words "$before") <(sorted_words "$after"))
  words_has "$added" sys-kernel/linux-firmware || {
    echo "$1: linux-firmware not added to @profile (added: $added)" >&2
    false
  }
  # firmware AND video acceleration: at least one more package than firmware
  [ "$(grep -cv '^sys-kernel/linux-firmware$' <<<"$added")" -ge 1 ] || {
    echo "$1: adds no video-acceleration package (added: $added)" >&2
    false
  }
  if [ -n "${2:-}" ]; then words_has "$added" "$2"; fi
}

@test "R3.4 amd: firmware and video-acceleration packages in @profile, VIDEO_CARDS unchanged" {
  assert_firmware_layer features/hardware/amd
}

@test "R3.4 intel: firmware and the Intel VA-API driver in @profile, VIDEO_CARDS unchanged" {
  # ::gentoo names the iHD driver media-libs/libva-intel-media-driver
  assert_firmware_layer features/hardware/intel media-libs/libva-intel-media-driver
}

# --- R3.5 / R4.8 combinations -----------------------------------------------------------

@test "R3.5 nvidia + amd compose, and both layers' packages and nvidia's card are present" {
  compose_croot "$CROOT0" "$PLAIN" features/hardware/nvidia
  local nv
  nv=$(pq "$CROOT0" set profile)
  rm -rf "$CROOT0"
  compose_croot "$CROOT0" "$PLAIN" features/hardware/amd
  local amd
  amd=$(pq "$CROOT0" set profile)
  compose_croot "$CROOT1" "$PLAIN" features/hardware/nvidia features/hardware/amd
  local both missing
  both=$(pq "$CROOT1" set profile)
  missing=$(comm -23 <(sorted_words "$nv $amd") <(sorted_words "$both"))
  [ -z "$missing" ] || {
    echo "missing from the combined @profile: $missing" >&2
    false
  }
  words_has "$nv" x11-drivers/nvidia-drivers
  words_has "$(pq "$CROOT1" var VIDEO_CARDS)" nvidia
}

@test "R4.8 nvidia + nvidia-legacy is rejected naming both layers" {
  run "$SCRIPT" --compose "$PLAIN" features/hardware/nvidia features/hardware/nvidia-legacy
  status_is 1
  line_names features/hardware/nvidia features/hardware/nvidia-legacy
}

@test "licences: a hardware layer accepts its driver's licence without replacing @FREE" {
  local hw a
  for hw in nvidia amd intel; do
    compose_croot "$CROOT1" "$PLAIN" "features/hardware/$hw"
    : >"$CROOT1/etc/portage/make.conf"  # the stage3 default: no ACCEPT_LICENSE
    for a in sys-apps/coreutils media-libs/vulkan-loader; do
      [ -n "$(pq "$CROOT1" visible "$a")" ] || {
        echo "features/hardware/$hw hides $a (a licence replaced @FREE)" >&2
        false
      }
    done
  done
  compose_croot "$CROOT1" "$PLAIN" features/hardware/nvidia features/hardware/intel
  : >"$CROOT1/etc/portage/make.conf"
  for a in x11-drivers/nvidia-drivers sys-kernel/linux-firmware media-libs/libva-intel-media-driver; do
    [ -n "$(pq "$CROOT1" visible "$a")" ] || {
      echo "nvidia + intel leaves $a invisible without ACCEPT_LICENSE in make.conf" >&2
      false
    }
  done
}

@test "nvidia layers enable persistenced, so the service the catalog lists exists" {
  local v
  for v in nvidia nvidia-legacy; do
    compose_croot "$CROOT1" "$PLAIN" "features/hardware/$v"
    words_has "$(pq "$CROOT1" use x11-drivers/nvidia-drivers)" persistenced || {
      echo "features/hardware/$v leaves USE=persistenced off" >&2
      false
    }
  done
}
