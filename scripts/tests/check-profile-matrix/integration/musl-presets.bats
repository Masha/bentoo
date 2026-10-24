#!/usr/bin/env bats
# bats file_tags=integration
#
# Integration -- story 002, Task 2.2: the seven amd64 musl presets.
# Requirements: R2.1, R2.2, R2.3, R2.4, R2.6 (and the 27-preset count R6.1
# resolves over).
#
# Oracles: the attribute values come from the preset PATH segments; the
# status comes from design.md C1 and, when the host has it, from ::gentoo's
# own profiles.desc; the profile stack comes from Portage itself (pq stack),
# never from the script's report. `musl/` is both a preset and the directory
# holding its children, so every id is compared whole (musl is not
# musl/systemd).

load lib

MUSL_IDS=(
  default/linux/amd64/23.0/musl
  default/linux/amd64/23.0/musl/systemd
  default/linux/amd64/23.0/musl/llvm
  default/linux/amd64/23.0/musl/llvm/systemd
  default/linux/amd64/23.0/musl/hardened
  default/linux/amd64/23.0/musl/hardened/systemd
  default/linux/amd64/23.0/musl/hardened/selinux
)

# want_status ID -- the ::gentoo status design.md C1 records for ID.
want_status() {
  case $1 in
  */musl | */musl/systemd) printf 'dev' ;;
  *) printf 'exp' ;;
  esac
}

# real_paths -- every stdin path canonicalised (missing ones kept as given),
# so a symlinked repository location never reads as a different stack.
real_paths() {
  local p
  while IFS= read -r p; do realpath -m -- "$p"; done
}

@test "R2.1/R2.2 each musl id is a catalog preset and an amd64 profiles.desc line, both with its ::gentoo status" {
  local -a pairs=()
  local i
  for i in "${MUSL_IDS[@]}"; do pairs+=("$i=$(want_status "$i")"); done
  catalog_py '
desc = {}
for line in open(sys.argv[2]):
    f = line.split()
    if len(f) >= 3 and f[0] == "amd64":
        desc[f[1]] = f[2]
presets = {p["id"]: p.get("status") for p in cat.get("preset", [])}
errors = []
for pair in sys.argv[3:]:
    ident, want = pair.split("=")
    if presets.get(ident) != want:
        errors.append("catalog %s: status %r, want %r" % (ident, presets.get(ident), want))
    if desc.get(ident) != want:
        errors.append("profiles.desc %s: status %r, want %r" % (ident, desc.get(ident), want))
assert not errors, "\n".join(errors)
' "$TREE/profiles/profiles.desc" "${pairs[@]}"
}

@test "R2.1/R6.1 the catalog and profiles.desc list the same 27 presets, 7 of them musl" {
  catalog_py '
desc = [l.split()[1] for l in open(sys.argv[2]) if len(l.split()) >= 2 and l.split()[0] == "amd64"]
ids = [p["id"] for p in cat.get("preset", [])]
assert sorted(ids) == sorted(desc), (sorted(set(ids) - set(desc)), sorted(set(desc) - set(ids)))
assert len(ids) == 27 and len(set(ids)) == 27, len(ids)
musl = [i for i in ids if "musl" in i.split("/")[4:]]
assert len(musl) == 7, musl
' "$TREE/profiles/profiles.desc"
}

@test "R2.2 the musl statuses match ::gentoo's profiles.desc line for line" {
  [ -f "$GENTOO_REPO/profiles/profiles.desc" ] || skip "no ::gentoo profiles.desc at $GENTOO_REPO"
  local id ours theirs errors=""
  for id in "${MUSL_IDS[@]}"; do
    theirs=$(awk -v id="$id" '$1 == "amd64" && $2 == id { print $3 }' "$GENTOO_REPO/profiles/profiles.desc")
    ours=$(awk -v id="$id" '$1 == "amd64" && $2 == id { print $3 }' "$TREE/profiles/profiles.desc")
    [ -n "$theirs" ] && [ "$ours" = "$theirs" ] || errors+="$id: ours=${ours:-<none>} ::gentoo=${theirs:-<none>}"$'\n'
  done
  [ -z "$errors" ] || {
    printf '%s' "$errors" >&2
    false
  }
}

@test "R2.3 every musl preset: libc musl, multilib false, desktop none, the rest from its path segments" {
  catalog_py '
errors, seen = [], 0
for p in cat.get("preset", []):
    seg = p["id"].split("/")[4:]
    if "musl" not in seg:
        continue
    seen += 1
    want = {
        "libc": "musl",
        "multilib": False,
        "desktop": "none",
        "init": "systemd" if "systemd" in seg else "openrc",
        "hardened": "hardened" in seg,
        "selinux": "selinux" in seg,
        "toolchain": "llvm" if "llvm" in seg else "gcc",
    }
    for k, v in want.items():
        got = p.get(k, "<absent>")
        if type(got) is not type(v) or got != v:
            errors.append("%s: %s = %r, want %r" % (p["id"], k, got, v))
assert not errors, "\n".join(errors)
assert seen == 7, seen
'
}

@test "R2.4 every musl preset directory holds exactly eapi (5) and parent (gentoo:<id>, :features/branding)" {
  local id d files errors=""
  for id in "${MUSL_IDS[@]}"; do
    d=$TREE/profiles/$id
    files=$(find "$d" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')
    [ "$files" = "eapi parent " ] || errors+="$id: files are '${files}', want 'eapi parent '"$'\n'
    [ "$(cat "$d/eapi" 2>/dev/null)" = 5 ] || errors+="$id: eapi is not 5"$'\n'
    [ "$(cat "$d/parent" 2>/dev/null)" = "gentoo:$id"$'\n'":features/branding" ] ||
      errors+="$id: parent is '$(cat "$d/parent" 2>/dev/null || true)'"$'\n'
  done
  [ -z "$errors" ] || {
    printf '%s' "$errors" >&2
    false
  }
}

@test "R2.4 Portage stacks each musl preset as gentoo:<id>, then features/branding, then the preset, nothing else" {
  need_portage
  local id n=0 errors="" cr_g cr_b want got
  for id in "${MUSL_IDS[@]}"; do
    n=$((n + 1))
    cr_g=$BATS_TEST_TMPDIR/gentoo-$n
    cr_b=$BATS_TEST_TMPDIR/bentoo-$n
    mk_croot "$cr_g" "$TREE"
    printf 'gentoo:%s\n' "$id" >"$cr_g/etc/portage/make.profile/parent"
    mk_croot "$cr_b" "$TREE"
    printf 'bentoo:%s\n' "$id" >"$cr_b/etc/portage/make.profile/parent"
    # the ::gentoo stack of the same id, plus exactly the two bentoo dirs
    want=$(
      {
        pq "$cr_g" stack | grep -v "^$cr_g/"
        printf '%s\n' "$TREE/profiles/features/branding" "$TREE/profiles/$id"
      } | real_paths
    )
    got=$(pq "$cr_b" stack | grep -v "^$cr_b/" | real_paths)
    [ "$want" = "$got" ] || errors+="$id:"$'\n'"--- want ---"$'\n'"$want"$'\n'"--- got ---"$'\n'"$got"$'\n'
  done
  [ -z "$errors" ] || {
    printf '%s' "$errors" >&2
    false
  }
}

@test "R2.6 no split-usr, prefix or x32 profile is a catalog preset or a profiles.desc line" {
  catalog_py '
out = {"split-usr", "prefix", "x32"}
ids = [p["id"] for p in cat.get("preset", [])]
ids += [l.split()[1] for l in open(sys.argv[2]) if len(l.split()) >= 2 and not l.startswith("#")]
bad = [i for i in ids if out & set(i.split("/"))]
assert not bad, bad
' "$TREE/profiles/profiles.desc"
}

@test "R2.6 the profiles.desc header states the split-usr/prefix/x32 scope, covers musl, and cites no CLAUDE.md" {
  local header w
  header=$(awk '/^[[:space:]]*(#|$)/ { print; next } { exit }' "$TREE/profiles/profiles.desc")
  [ -n "$header" ]
  for w in split-usr prefix x32 musl; do
    grep -qi -- "$w" <<<"$header" || {
      echo "the profiles.desc header does not mention $w" >&2
      false
    }
  done
  ! grep -q 'CLAUDE.md' <<<"$header" || {
    echo "the profiles.desc header still attributes its scope to CLAUDE.md" >&2
    false
  }
}
