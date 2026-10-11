#!/usr/bin/env bats
# bats file_tags=integration
#
# Integration -- Task 4.2: the features/games mix-in on the real tree.
# Requirements: R3.1 (and R4.10 on the real catalog).

load lib

PLAIN=default/linux/amd64/23.0/desktop
NOML=default/linux/amd64/23.0/no-multilib

setup() {
  need_portage
  CROOT0=$BATS_TEST_TMPDIR/croot-preset
  CROOT1=$BATS_TEST_TMPDIR/croot-layer
}

@test "R4.10 games on a no-multilib preset is rejected naming multilib (not just echoing the preset id)" {
  run "$SCRIPT" --compose "$NOML" features/games
  status_is 1
  # the preset id itself contains "multilib": remove it before looking
  output=$(strip_ids "$output" "$NOML")
  line_names multilib
}

@test "R3.1 games on a multilib preset: gamemode in @profile, abi_x86_32 on Mesa and the Vulkan loader" {
  compose_croot "$CROOT0" "$PLAIN"
  compose_croot "$CROOT1" "$PLAIN" features/games
  # hostile baseline: none of it holds on the bare preset
  ! words_has "$(pq "$CROOT0" set profile)" games-util/gamemode || {
    echo "gamemode is in @profile without the layer: the check proves nothing" >&2
    false
  }
  local a
  for a in media-libs/mesa media-libs/vulkan-loader; do
    ! words_has "$(pq "$CROOT0" use "$a")" abi_x86_32 || {
      echo "$a already has abi_x86_32 without the layer: the check proves nothing" >&2
      false
    }
  done

  words_has "$(pq "$CROOT1" set profile)" games-util/gamemode || {
    echo "gamemode missing from @profile" >&2
    false
  }
  for a in media-libs/mesa media-libs/vulkan-loader; do
    words_has "$(pq "$CROOT1" use "$a")" abi_x86_32 || {
      echo "$a: abi_x86_32 not enabled under features/games" >&2
      false
    }
  done
}

@test "games: Mesa and the Vulkan loader resolve with their whole 32-bit closure" {
  compose_croot "$CROOT1" "$PLAIN" features/games
  run isolated_emerge "$CROOT1" -pq @profile media-libs/mesa media-libs/vulkan-loader
  if [[ $output == *"USE changes are necessary"* ]]; then
    grep -E 'abi_x86_32' <<<"$output" >&2
  fi
  resolves_ok
}
