#!/usr/bin/env bats
# bats file_tags=integration,resolution
#
# Integration -- Task 5.4: the validator checks what a layer DOES, not only
# that it resolves. Each test plants a change that still resolves cleanly but
# breaks the layer's requirement, stages it in a scratch copy, and expects
# `--staged` to exit 1 naming the layer (and the property, where one word
# names it).
# Requirements: R3.2, R2.3, R2.2 (as checked by the script).

load lib

setup() {
  need_portage
  scratch_repo
}

@test "R3.2 nvidia resetting VIDEO_CARDS (-* nvidia) resolves but fails the content check" {
  local f=profiles/features/hardware/nvidia/make.defaults
  [ -f "$R/$f" ]
  printf '\n# probe: wipes the cards arch/amd64 set (the hybrid-machine bug)\nVIDEO_CARDS="-* nvidia"\n' >>"$R/$f"
  git -C "$R" add -- "$f"
  run_staged
  status_is 1
  line_names features/hardware/nvidia VIDEO_CARDS
}

@test "R2.3 headless adding a package to @profile resolves but fails the content check" {
  local d=profiles/targets/headless
  [ -d "$R/$d" ]
  printf 'app-misc/screen\n' >>"$R/$d/packages"
  git -C "$R" add -- "$d/packages"
  run_staged
  status_is 1
  line_names targets/headless
}

@test "R2.2 server re-enabling X resolves but fails the content check" {
  local f=profiles/targets/server/make.defaults
  [ -f "$R/$f" ]
  printf '\n# probe\nUSE="X"\n' >>"$R/$f"
  git -C "$R" add -- "$f"
  run_staged
  status_is 1
  line_names targets/server X
}
