#!/usr/bin/env bats
# bats file_tags=integration,resolution
#
# Integration -- Task 5.3 (and 5.2, which it reaches): `--staged` dependency
# resolution on a scratch copy of the real tree.
# Requirements: R6.2, R6.3, R6.4, R6.6, R6.12, R1.1 (and "nothing compared
# => exit 2, never a silent 0", design.md Error Handling).
#
# Every test works on a private git repository holding the working-tree
# state of the checkout (scratch_repo); the checkout itself is never staged
# or modified. Breakage is planted with an atom no repository provides, so
# any combination that includes the broken layer MUST fail to resolve.
#
# Slow: each run resolves real combinations with emerge -p (seconds each).
# Tests tagged `slow` resolve every layer (catalog/layout.conf touched) and
# take several minutes.

load lib

PROBE_ATOM=app-misc/bentoo-matrix-probe-nonexistent

setup() {
  need_portage
  scratch_repo
}

# --- nothing to compare --------------------------------------------------------

@test "--staged with nothing staged exits 2 (nothing compared), never a silent 0" {
  run_staged
  status_is 2
  assert_tmp_clean
}

@test "--staged with only a non-profile path staged exits 2 (no layer touched)" {
  local eb
  eb=$(cd "$R" && git ls-files '*.ebuild' | head -n1)
  [ -n "$eb" ]
  printf '# probe\n' >>"$R/$eb"
  git -C "$R" add -- "$eb"
  run_staged
  status_is 2
}

# --- R6.2 / R6.4 / R6.12: one touched layer, clean ---------------------------------

@test "R6.4 one touched layer (games) resolves within 3 minutes and exits 0, leaving nothing behind" {
  local f=profiles/features/games/package.use
  [ -f "$R/$f" ]
  printf '# probe: staged comment\n' >>"$R/$f"
  git -C "$R" add -- "$f"
  local t0=$SECONDS
  run_staged
  local took=$((SECONDS - t0))
  status_is 0
  [ "$took" -lt 180 ] || {
    echo "--staged took ${took}s (limit 180s)" >&2
    false
  }
  assert_tmp_clean
  # R6.12: the run wrote nothing into the tree it validated
  [ "$(git -C "$R" status --porcelain)" = "M  $f" ] || {
    git -C "$R" status --porcelain >&2
    false
  }
}

# --- R6.6 / R6.2: an allowed combination that cannot resolve ----------------------------

@test "R6.6 a broken touched layer exits 1 naming each reference preset, a pair and the emerge error" {
  local f=profiles/features/hardware/intel/packages
  [ -f "$R/$f" ]
  printf '%s\n' "$PROBE_ATOM" >>"$R/$f"
  git -C "$R" add -- "$f"
  run_staged
  status_is 1
  # R6.2: every reference preset was resolved (intel has no base constraint,
  # so it is allowed -- and broken -- on each of them). Whole-token match:
  # default/linux/amd64/23.0 must not be "named" by .../23.0/systemd.
  local p
  for p in "${REF_PRESETS[@]}"; do line_names "$p"; done
  # the pair: intel with another layer the catalog allows next to it
  line_names features/hardware/intel 'features/hardware/amd|features/hardware/nvidia|features/hardware/nvidia-legacy|features/games'
  # the first error block from emerge: a `!!!` block, or an `emerge:` line --
  # "no ebuilds to satisfy" is reported without any `!!!`
  [[ $output == *'!!!'* || $output == *'emerge: '* ]] || {
    _dump "no emerge error block (!!! or emerge:) in the report"
    false
  }
  [[ $output == *"$PROBE_ATOM"* ]]
  assert_tmp_clean
}

@test "R6.2 a staged change under layers/<id>/ touches <id>" {
  # break nvidia in a COMMIT, then stage only a fragment edit: the breakage is
  # found only if layers/features/hardware/nvidia/... maps to that layer
  local pk=profiles/features/hardware/nvidia/packages
  local fr=layers/features/hardware/nvidia/etc/modprobe.d/50-bentoo-nvidia.conf
  [ -f "$R/$pk" ] && [ -f "$R/$fr" ]
  printf '%s\n' "$PROBE_ATOM" >>"$R/$pk"
  git -C "$R" add -- "$pk"
  _git_commit -qm 'break nvidia'
  printf '# probe\n' >>"$R/$fr"
  git -C "$R" add -- "$fr"
  run_staged
  status_is 1
  line_names features/hardware/nvidia
  [[ $output == *"$PROBE_ATOM"* ]]
}

# --- R6.3: catalog.toml / layout.conf touch every layer -------------------------------

break_amd_in_a_commit() {
  local pk=profiles/features/hardware/amd/packages
  [ -f "$R/$pk" ]
  printf '%s\n' "$PROBE_ATOM" >>"$R/$pk"
  git -C "$R" add -- "$pk"
  _git_commit -qm 'break amd'
}

# bats test_tags=slow
@test "R6.3 staging only profiles/catalog.toml treats every layer as touched" {
  break_amd_in_a_commit
  printf '\n# probe: staged comment\n' >>"$R/profiles/catalog.toml"
  git -C "$R" add -- profiles/catalog.toml
  run_staged
  status_is 1
  line_names features/hardware/amd
  [[ $output == *"$PROBE_ATOM"* ]]
}

# bats test_tags=slow
@test "R6.3 staging only metadata/layout.conf treats every layer as touched" {
  break_amd_in_a_commit
  printf '\n# probe: staged comment\n' >>"$R/metadata/layout.conf"
  git -C "$R" add -- metadata/layout.conf
  run_staged
  status_is 1
  line_names features/hardware/amd
  [[ $output == *"$PROBE_ATOM"* ]]
}

# --- R6.13: a profiles/ path that touches no layer -> static only, exit 0 ----------

@test "R6.13 staging only profiles/package.mask runs the static checks only and exits 0" {
  printf '\n# probe: staged comment\n' >>"$R/profiles/package.mask"
  git -C "$R" add -- profiles/package.mask
  local t0=$SECONDS
  run_staged
  local took=$((SECONDS - t0))
  status_is 0
  # one emerge -p resolution alone takes ~3 s and every layer would be
  # dozens: anything near that means combinations were resolved
  [ "$took" -lt 20 ] || {
    echo "took ${took}s: looks like it resolved combinations" >&2
    false
  }
  assert_tmp_clean
}

# --- design.md Error Handling: --staged needs a git repository -----------------------

@test "--staged on a BENTOO_TREE that is not a git repository exits 2 naming it" {
  local plain=$BATS_TEST_TMPDIR/plain
  mkdir -p "$plain"
  tar -C "$R" --exclude=./.git -cf - . | tar -C "$plain" -xf -
  [ ! -e "$plain/.git" ]
  TMP_PROBE=$BATS_TEST_TMPDIR/tmp-probe
  mkdir -p "$TMP_PROBE"
  run env BENTOO_TREE="$plain" TMPDIR="$TMP_PROBE" \
    bash -c 'cd "$1" && exec "$2" --staged' _ "$BATS_TEST_TMPDIR" "$R/scripts/check-profile-matrix.sh"
  status_is 2
  line_names 'git|repository'
  assert_tmp_clean
}

# --- R6.3 (extended): profiles.desc, a preset directory, branding touch every layer --

# bats test_tags=slow
@test "R6.3 staging only profiles/profiles.desc treats every layer as touched" {
  break_amd_in_a_commit
  printf '\n# probe: staged comment\n' >>"$R/profiles/profiles.desc"
  git -C "$R" add -- profiles/profiles.desc
  run_staged
  status_is 1
  line_names features/hardware/amd
  [[ $output == *"$PROBE_ATOM"* ]]
}

# bats test_tags=slow
@test "R6.3 staging only a file in a preset directory treats every layer as touched" {
  break_amd_in_a_commit
  local f=profiles/default/linux/amd64/23.0/systemd/package.use
  [ -d "$R/${f%/*}" ]
  printf '# probe: staged comment\n' >>"$R/$f"
  git -C "$R" add -- "$f"
  run_staged
  status_is 1
  line_names features/hardware/amd
  [[ $output == *"$PROBE_ATOM"* ]]
}

# bats test_tags=slow
@test "R6.3 staging only profiles/features/branding/* treats every layer as touched" {
  break_amd_in_a_commit
  local f=profiles/features/branding/packages
  [ -f "$R/$f" ]
  printf '# probe: staged comment\n' >>"$R/$f"
  git -C "$R" add -- "$f"
  run_staged
  status_is 1
  line_names features/hardware/amd
  [[ $output == *"$PROBE_ATOM"* ]]
}

# --- R6.2: the largest allowed selection is resolved per reference preset ------------
# Judged independently: the greedy largest selection (catalog order, one
# flavor at most, every compatible mix-in and hardware layer) is computed
# here from the catalog data. On each reference preset where it includes the
# broken intel layer and has >= 3 layers, a failure line must name the preset,
# intel and at least two other layers -- no single or pair resolution can.

largest_with_intel() { # prints "<preset> <layer> <layer>..." per reference preset
  catalog_py '
cat_l = cat["layer"]; types = cat["types"]
presets = {p["id"]: p for p in cat["preset"]}
def base_ok(l, p):
    return all(any(type(a) is type(p.get(k)) and a == p.get(k) for a in v)
               for k, v in l.get("base", {}).items())
for pid in sys.argv[2:]:
    p, sel = presets[pid], []
    for l in cat_l:
        if not base_ok(l, p): continue
        if types[l["type"]]["exclusive"] and any(s["type"] == l["type"] for s in sel): continue
        if any(l["id"] in s.get("conflicts", []) or s["id"] in l.get("conflicts", []) for s in sel): continue
        sel.append(l)
    ids = {s["id"] for s in sel}
    sel = [s for s in sel if set(s.get("requires", [])) <= ids]
    print(pid, *[s["id"] for s in sel])
' "${REF_PRESETS[@]}"
}

@test "R6.2 the largest allowed selection is resolved on each reference preset" {
  local f=profiles/features/hardware/intel/packages
  [ -f "$R/$f" ]
  printf '%s\n' "$PROBE_ATOM" >>"$R/$f"
  git -C "$R" add -- "$f"
  run_staged
  status_is 1
  local preset layers checked=0 line ok others id
  while read -r preset layers; do
    [[ " $layers " == *" features/hardware/intel "* ]] || continue
    [ "$(wc -w <<<"$layers")" -ge 3 ] || continue
    checked=$((checked + 1))
    ok=0
    while IFS= read -r line; do
      _line_has_one "$line" "$preset" && _line_has_one "$line" features/hardware/intel || continue
      others=0
      for id in $layers; do
        [ "$id" = features/hardware/intel ] && continue
        if _line_has_one "$line" "$id"; then others=$((others + 1)); fi
      done
      if [ "$others" -ge 2 ]; then ok=1; break; fi
    done <<<"$output"
    [ "$ok" -eq 1 ] || {
      _dump "no failure line for the largest selection on $preset: $layers"
      false
    }
  done < <(largest_with_intel)
  [ "$checked" -ge 1 ] || skip "no reference preset's largest selection includes intel with >= 3 layers"
}

# R6.7 (forbidden judged from the catalog data, not from --compose) is NOT
# testable from outside: proving the validator catches a --compose that
# accepts a forbidden selection needs a broken --compose inside the one
# self-contained script. Both halves of every rule are covered against
# --compose in ../compose.bats; the cross-check itself rests on review.

# --- autounmask is not a pass (tech review of task 5) ---------------------------

@test "games with only part of its abi_x86_32 closure fails, though emerge would autounmask it" {
  local f=profiles/features/games/package.use
  [ -f "$R/$f" ]
  printf 'media-libs/mesa abi_x86_32\nmedia-libs/vulkan-loader abi_x86_32\n' >"$R/$f"
  git -C "$R" add -- "$f"
  run_staged
  status_is 1
  line_names features/games
}
