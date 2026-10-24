#!/usr/bin/env bats
# bats file_tags=integration
#
# Integration -- Task 3.1: profiles/catalog.toml on the real tree.
# Requirements: R4.1, R4.4, R6.1, R8.3; schema 2 since story 002 (R1.3, R1.6).
#
# The preset attributes are checked against what each preset PATH says,
# because a wrong attribute silently mis-classifies every composition built on
# that preset (e.g. games allowed on a no-multilib preset).

load lib

@test "R6.1 --static exits 0 on this tree within 10 seconds" {
  local t0 t1
  t0=$(date +%s%N)
  run "$SCRIPT" --static
  t1=$(date +%s%N)
  status_is 0
  local ms=$(((t1 - t0) / 1000000))
  [ "$ms" -lt 10000 ] || {
    echo "--static took ${ms} ms (limit 10000)" >&2
    false
  }
}

@test "R8.3 catalog.toml opens with a header comment naming schema 2 and its consumers" {
  local f=$TREE/profiles/catalog.toml header
  [ -f "$f" ]
  # the leading block of comment / blank lines
  header=$(awk '/^[[:space:]]*(#|$)/ { print; next } { exit }' "$f")
  [ -n "$header" ]
  grep -Eqi 'schema[^0-9]*2' <<<"$header" || {
    echo "header does not describe schema 2" >&2
    false
  }
  grep -q 'check-profile-matrix' <<<"$header"
  grep -q 'bentoo profile' <<<"$header"
  grep -q 'shidashi order' <<<"$header"
}

@test "R4.1 catalog.toml declares schema = 2 (an integer)" {
  catalog_py 'assert type(cat.get("schema")) is int and cat["schema"] == 2, cat.get("schema")'
}

@test "R4.1/R4.4 one [[preset]] per amd64 line of profiles.desc: same ids, same status" {
  catalog_py '
desc = {}
for line in open(sys.argv[2]):
    f = line.split()
    if len(f) >= 3 and f[0] == "amd64":
        desc[f[1]] = f[2]
cat_p = {p["id"]: p.get("status") for p in cat.get("preset", [])}
assert len(cat_p) == len(cat.get("preset", [])), "duplicate preset ids"
only_cat = sorted(set(cat_p) - set(desc))
only_desc = sorted(set(desc) - set(cat_p))
assert not only_cat and not only_desc, (only_cat, only_desc)
bad = sorted(i for i in desc if desc[i] != cat_p[i])
assert not bad, ["%s: desc=%s catalog=%s" % (i, desc[i], cat_p[i]) for i in bad]
assert len(desc) == 27, len(desc)
' "$TREE/profiles/profiles.desc"
}

@test "R4.1 every preset's attributes match what its path says" {
  catalog_py '
errors = []
for p in cat.get("preset", []):
    seg = p["id"].split("/")[4:]          # after default/linux/amd64/23.0
    want = {
        "init": "systemd" if "systemd" in seg else "openrc",
        # every musl profile of ::gentoo is no-multilib without saying so
        "multilib": "no-multilib" not in seg and "musl" not in seg,
        "desktop": ("plasma" if "plasma" in seg else
                    "gnome" if "gnome" in seg else
                    "generic" if "desktop" in seg else "none"),
        "hardened": "hardened" in seg,
        "selinux": "selinux" in seg,
        "toolchain": "llvm" if "llvm" in seg else "gcc",
        "libc": "musl" if "musl" in seg else "glibc",
    }
    for k, v in want.items():
        got = p.get(k, "<absent>")
        if type(got) is not type(v) or got != v:
            errors.append("%s: %s = %r, path says %r" % (p["id"], k, got, v))
    stale = sorted(set(p) - set(want) - {"id", "status"})
    if stale:
        errors.append("%s: keys outside schema 2: %s" % (p["id"], stale))
assert not errors, "\n".join(errors)
'
}
