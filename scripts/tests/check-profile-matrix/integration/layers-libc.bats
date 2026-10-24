#!/usr/bin/env bats
# bats file_tags=integration
#
# Integration -- story 002, Task 2.3: the libc axis constrains the real layers.
# Requirements: R3.1, R3.2, R3.3, R3.4, R3.5.
#
# Through the public --compose contract on the real catalog: exit 0 + parent
# lines is "valid"; exit 1 + `compose: <rule>: ...` lines is "invalid". The
# glibc and musl preset sets are read from the catalog's own `libc` values and
# cross-checked against the path (a musl preset has a `musl` segment), so a
# preset mis-tagged on either axis fails here rather than silently changing
# which layers it accepts.

load lib

# presets_with_libc VALUE -- every catalog preset id whose libc is VALUE and
# whose path agrees (musl segment <=> musl), one per line; fails on a mismatch.
presets_with_libc() {
  catalog_py '
want = sys.argv[2]
for p in cat.get("preset", []):
    musl_path = "musl" in p["id"].split("/")[4:]
    assert (p.get("libc") == "musl") == musl_path, "libc/path mismatch: %s libc=%r" % (p["id"], p.get("libc"))
    if p.get("libc") == want:
        print(p["id"])
' "$1"
}

# base_line_names LAYER ATTR -- some `compose: base:` line names LAYER and ATTR.
base_line_names() {
  local line
  while IFS= read -r line; do
    [[ $line == "compose: base: "* ]] || continue
    _line_has "$line" "$1" && _line_has "$line" "$2" && return 0
  done <<<"$output"
  _dump "no 'compose: base:' line names $1 and $2"
  return 1
}

@test "R3.1/R3.2 hostile: over musl, nvidia beside amd is refused with a base line for nvidia only" {
  local musl
  musl=$(presets_with_libc musl | head -n1)
  [ -n "$musl" ]
  run "$SCRIPT" --compose "$musl" features/hardware/amd features/hardware/nvidia
  status_is 1
  base_line_names features/hardware/nvidia libc
  ! base_line_names features/hardware/amd libc 2>/dev/null || {
    _dump "amd (no libc constraint) was named by a base rule"
    false
  }
}

@test "R3.1 features/hardware/nvidia over every musl preset is invalid with a base line naming libc" {
  local p n=0
  for p in $(presets_with_libc musl); do
    n=$((n + 1))
    run "$SCRIPT" --compose "$p" features/hardware/nvidia
    status_is 1
    base_line_names features/hardware/nvidia libc
  done
  [ "$n" -eq 7 ]
}

@test "R3.2 features/hardware/nvidia-legacy over every musl preset is invalid with a base line naming libc" {
  local p n=0
  for p in $(presets_with_libc musl); do
    n=$((n + 1))
    run "$SCRIPT" --compose "$p" features/hardware/nvidia-legacy
    status_is 1
    base_line_names features/hardware/nvidia-legacy libc
  done
  [ "$n" -eq 7 ]
}

@test "R3.3 hostile: features/hardware/nvidia stays valid over every glibc preset, the llvm ones included" {
  local p n=0
  for p in $(presets_with_libc glibc); do
    n=$((n + 1))
    run --separate-stderr "$SCRIPT" --compose "$p" features/hardware/nvidia
    status_is 0
    output_is "$(printf '%s\n' "bentoo:$p" bentoo:features/hardware/nvidia)"
  done
  [ "$n" -eq 20 ]
}

@test "R3.4 amd, intel, server, headless and container alone are valid over every musl preset" {
  local p l n=0
  for p in $(presets_with_libc musl); do
    for l in features/hardware/amd features/hardware/intel targets/server targets/headless targets/container; do
      n=$((n + 1))
      run --separate-stderr "$SCRIPT" --compose "$p" "$l"
      status_is 0
      output_is "$(printf '%s\n' "bentoo:$p" "bentoo:$l")"
    done
  done
  [ "$n" -eq 35 ]
}

@test "R3.5 features/games and targets/workstation over every musl preset are invalid with a base rule" {
  local p l n=0
  for p in $(presets_with_libc musl); do
    for l in features/games targets/workstation; do
      n=$((n + 1))
      run "$SCRIPT" --compose "$p" "$l"
      status_is 1
      grep -q "^compose: base: $l " <<<"$output" || {
        _dump "no base line for $l over $p"
        false
      }
    done
  done
  [ "$n" -eq 14 ]
}
