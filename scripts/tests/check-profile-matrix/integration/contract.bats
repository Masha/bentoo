#!/usr/bin/env bats
# bats file_tags=integration
#
# Integration -- Task 7.1: what the catalog promises matches what the tree
# and Portage do, for EVERY layer (not a hand-picked few).
# Requirements: R4.1, R4.11, R4.12, R5.6, R1.1, R1.2.
#
# The compatible preset for a layer is derived here from the catalog's own
# data (first preset, in catalog order, whose attributes satisfy the layer's
# base, plus whatever the layer requires) -- an independent reading of the
# composition rule, so a disagreement with --compose shows up as a failure.

load lib

setup() {
  need_portage
}

# one line per layer: "<preset> <layer> [<required layer>...]"
compatible_selections() {
  catalog_py '
presets = cat.get("preset", [])
for l in cat.get("layer", []):
    sel = [l["id"]] + list(l.get("requires", []))
    layers = {x["id"]: x for x in cat["layer"]}
    def ok(p):
        for lid in sel:
            for attr, allowed in layers[lid].get("base", {}).items():
                v = p.get(attr)
                # type-exact: 1 must not satisfy [true]
                if not any(type(a) is type(v) and a == v for a in allowed):
                    return False
        return True
    match = [p["id"] for p in presets if ok(p)]
    print(" ".join([match[0] if match else "NONE"] + sel))
'
}

@test "R4.11/R1.1 every catalog layer composes on a compatible preset and Portage loads it without a parse error" {
  local sel n=0 failed=0 cr preset
  while read -r preset sel; do
    n=$((n + 1))
    [ "$preset" != NONE ] || {
      echo "no preset satisfies the base of: $sel" >&2
      failed=1
      continue
    }
    # shellcheck disable=SC2086
    run --separate-stderr "$SCRIPT" --compose "$preset" $sel
    if [ "$status" -ne 0 ]; then
      _dump "--compose $preset $sel"
      failed=1
      continue
    fi
    local id=${sel%% *}
    [[ $'\n'"$output"$'\n' == *$'\n'"bentoo:$id"$'\n'* ]] || {
      _dump "--compose output lacks bentoo:$id"
      failed=1
    }
    cr=$BATS_TEST_TMPDIR/croot-$n
    mk_croot "$cr" "$TREE"
    printf '%s\n' "$output" >"$cr/etc/portage/make.profile/parent"
    run --separate-stderr pq "$cr" stack
    if [ "$status" -ne 0 ] || [[ $stderr == *'!!!'* ]]; then
      _dump "Portage failed to load $preset + $sel"
      failed=1
      continue
    fi
    [[ $'\n'"$output"$'\n' == *$'\n'"$TREE/profiles/$id"$'\n'* ]] || {
      _dump "the loaded stack does not include profiles/$id"
      failed=1
    }
  done < <(compatible_selections)
  [ "$n" -ge 9 ] || {
    echo "only $n layers in the catalog (v1 ships 9)" >&2
    false
  }
  [ "$failed" -eq 0 ]
}

@test "R1.2 every atom a layer adds to @profile names a package that exists" {
  # A bare atom for a package no repository has is silently inert in
  # @profile; it only surfaces as a resolution failure on a user's machine.
  local preset sel n=0 bad=0 cr a
  while read -r preset sel; do
    [ "$preset" != NONE ] || continue
    n=$((n + 1))
    cr=$BATS_TEST_TMPDIR/croot-atoms-$n
    mk_croot "$cr" "$TREE"
    # shellcheck disable=SC2086
    "$SCRIPT" --compose "$preset" $sel >"$cr/etc/portage/make.profile/parent"
    for a in $(pq "$cr" set profile); do
      [ -n "$(pq "$cr" all "$a")" ] || {
        echo "${sel%% *}: @profile atom $a matches no package" >&2
        bad=1
      }
    done
  done < <(compatible_selections)
  [ "$n" -ge 1 ]
  [ "$bad" -eq 0 ]
}

@test "R4.1 every services entry names both an OpenRC and a systemd form" {
  catalog_py '
errors = []
for l in cat.get("layer", []):
    for s in l.get("services", []):
        o, d = s.get("openrc"), s.get("systemd")
        if set(s) != {"openrc", "systemd"}:
            errors.append("%s: keys %s" % (l["id"], sorted(s)))
        if not isinstance(o, str) or not o or o.endswith((".service", ".socket", ".timer", ".target")):
            errors.append("%s: openrc = %r" % (l["id"], o))
        if not isinstance(d, str) or not d.endswith((".service", ".socket", ".timer", ".target")):
            errors.append("%s: systemd = %r" % (l["id"], d))
assert not errors, "\n".join(errors)
'
}

@test "R5.6/R4.1 every fragment maps to an /etc/<x>.d/ destination of a has_files layer, and back" {
  catalog_py '
import os
root = sys.argv[2]
layers = {l["id"]: l for l in cat.get("layer", [])}
errors, seen = [], set()
for dirpath, dirnames, filenames in os.walk(os.path.join(root, "layers")):
    for fn in filenames:
        rel = os.path.relpath(os.path.join(dirpath, fn), os.path.join(root, "layers"))
        lid = next((i for i in sorted(layers, key=len, reverse=True)
                    if rel.startswith(i + "/etc/")), None)
        if lid is None:
            errors.append("no layer owns layers/" + rel)
            continue
        seen.add(lid)
        dest = "/" + rel[len(lid) + 1:]
        if not os.path.dirname(dest).endswith(".d") or "bentoo-" not in fn:
            errors.append("%s -> %s is not /etc/**/<x>.d/<bentoo-...>" % (rel, dest))
        if layers[lid].get("has_files") is not True:
            errors.append(lid + " ships files but has_files is not true")
for lid, l in layers.items():
    if l.get("has_files") is True and lid not in seen:
        errors.append(lid + " declares has_files but ships nothing")
for lid in ("features/hardware/nvidia", "features/hardware/nvidia-legacy"):
    if lid not in seen:
        errors.append(lid + " ships no fragment (R5.6)")
assert not errors, "\n".join(errors)
' "$TREE"
}

@test "R4.12 on the real catalog: two input orders, one byte-identical parent; flavor, mix-in, hardware" {
  # games needs a desktop preset (catalog base), so the only flavor that
  # combines with it is workstation.
  local p=default/linux/amd64/23.0/desktop/plasma/systemd
  "$SCRIPT" --compose "$p" features/hardware/amd features/games targets/workstation \
    features/hardware/nvidia >"$BATS_TEST_TMPDIR/a" 2>/dev/null
  "$SCRIPT" --compose "$p" features/hardware/nvidia targets/workstation features/hardware/amd \
    features/games >"$BATS_TEST_TMPDIR/b" 2>/dev/null
  cmp "$BATS_TEST_TMPDIR/a" "$BATS_TEST_TMPDIR/b"
  [ "$(sed -n 1p "$BATS_TEST_TMPDIR/a")" = "bentoo:$p" ]
  [ "$(sed -n 2p "$BATS_TEST_TMPDIR/a")" = "bentoo:targets/workstation" ]
  [ "$(sed -n 3p "$BATS_TEST_TMPDIR/a")" = "bentoo:features/games" ]
  [ "$(sed -n 4,5p "$BATS_TEST_TMPDIR/a" | sed 's/^bentoo://' | LC_ALL=C sort | tr '\n' ' ')" = \
    "features/hardware/amd features/hardware/nvidia " ]
  [ "$(wc -l <"$BATS_TEST_TMPDIR/a")" -eq 5 ]
}
