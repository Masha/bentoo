#!/usr/bin/env bats
# bats file_tags=integration
#
# Integration -- story 002, Task 2.1: the real profiles/catalog.toml is schema 2.
# Requirements: R1.1, R1.3, R1.4, R1.6, R7.1.
#
# The migrated values are checked against what each preset PATH says, never
# against the catalog's own claims: a pre-existing preset is one whose id has
# no `musl` SEGMENT, and its toolchain is llvm exactly when its id has an
# `llvm` SEGMENT. Segments, not substrings: no id may be judged by a word it
# merely contains.

load lib

@test "R1.1 --static exits 0 on this tree" {
  run "$SCRIPT" --static
  status_is 0
}

@test "R1.3 catalog.toml declares schema = 2 (an integer)" {
  catalog_py 'assert type(cat.get("schema")) is int and cat["schema"] == 2, repr(cat.get("schema"))'
}

@test "R1.3/R1.4 [attributes] holds exactly the seven axes, toolchain = [gcc, llvm], libc = [glibc, musl]" {
  catalog_py '
a = cat.get("attributes", {})
want = {"init", "multilib", "desktop", "hardened", "selinux", "toolchain", "libc"}
assert set(a) == want, ("extra", sorted(set(a) - want), "missing", sorted(want - set(a)))
assert a["toolchain"] == ["gcc", "llvm"], a["toolchain"]
assert a["libc"] == ["glibc", "musl"], a["libc"]
'
}

@test "R1.4 no preset and no layer base still carries the key llvm" {
  catalog_py '
bad = [p["id"] for p in cat.get("preset", []) if "llvm" in p]
bad += ["base of " + l["id"] for l in cat.get("layer", []) if "llvm" in l.get("base", {})]
assert not bad, bad
'
}

@test "R1.6 the 20 pre-existing presets: toolchain llvm exactly on an llvm segment, else gcc; libc glibc" {
  catalog_py '
errors, n, n_llvm = [], 0, 0
for p in cat.get("preset", []):
    seg = p["id"].split("/")[4:]           # after default/linux/amd64/23.0
    if "musl" in seg:
        continue
    n += 1
    want_tc = "llvm" if "llvm" in seg else "gcc"
    n_llvm += want_tc == "llvm"
    for k, v in (("toolchain", want_tc), ("libc", "glibc")):
        got = p.get(k, "<absent>")
        if type(got) is not str or got != v:
            errors.append("%s: %s = %r, path says %r" % (p["id"], k, got, v))
assert not errors, "\n".join(errors)
assert n == 20, "pre-existing presets: %d" % n
assert n_llvm == 2, "llvm presets: %d" % n_llvm
'
}

@test "R7.1 the catalog header describes schema 2, toolchain, libc, musl, the vectors file and binhost coverage" {
  local f=$TREE/profiles/catalog.toml header w
  header=$(awk '/^[[:space:]]*(#|$)/ { print; next } { exit }' "$f")
  [ -n "$header" ]
  grep -Eqi 'schema[^0-9]*2' <<<"$header" || {
    echo "the header does not describe schema 2" >&2
    false
  }
  ! grep -Eqi 'schema[^0-9]*1([^0-9]|$)' <<<"$header" || {
    echo "the header still describes schema 1" >&2
    false
  }
  for w in toolchain libc musl catalog-vectors.toml binhost; do
    grep -qi -- "$w" <<<"$header" || {
      echo "the header does not mention $w" >&2
      false
    }
  done
}
