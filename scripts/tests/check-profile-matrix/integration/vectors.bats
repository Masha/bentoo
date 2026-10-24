#!/usr/bin/env bats
# bats file_tags=integration
#
# Integration -- story 002, Task 3.3 (and 3.4): the shipped
# profiles/catalog-vectors.toml on the real tree.
# Requirements: R4.1, R4.2, R4.7, R4.8, R5.1, R7.2 (Q13: the vectors are the
# cross-language contract).
#
# Two oracles, so the vectors cannot pass by agreeing with a lenient
# validator: `--vectors` must exit 0, AND this suite re-runs every vector
# through the public `--compose` contract itself (parent exact and ordered,
# rules as a set). The file is also read the way a Go or Python consumer
# would, with nothing but tomllib: keys, rule names and coverage.

load lib

VECTORS=$TREE/profiles/catalog-vectors.toml
RULES='unknown-preset unknown-layer exclusive conflict requires base'

# vectors_py PROGRAM -- run Python with `cat` (catalog) and `vec` (vectors).
vectors_py() {
  [ -f "$VECTORS" ] || {
    echo "the vectors file $VECTORS does not exist" >&2
    return 1
  }
  python3 -c "import sys, tomllib
cat = tomllib.load(open(sys.argv[1], 'rb'))
vec = tomllib.load(open(sys.argv[2], 'rb'))
$1" "$TREE/profiles/catalog.toml" "$VECTORS" "${@:2}"
}

@test "R5.1/Q13 --vectors exits 0 on this tree" {
  run "$SCRIPT" --vectors
  status_is 0
}

@test "R4.1 the vectors file declares the catalog's schema, 2 (integers)" {
  vectors_py '
assert type(vec.get("schema")) is int and type(cat.get("schema")) is int, (vec.get("schema"), cat.get("schema"))
assert vec["schema"] == cat["schema"] == 2, (vec["schema"], cat["schema"])
'
}

@test "R4.2 every vector has exactly its keys, a unique name, and only the six rule names" {
  vectors_py '
rules = set(sys.argv[3].split())
errors, names = [], []
vectors = vec.get("vector", [])
assert vectors, "no [[vector]]"
for n, v in enumerate(vectors, 1):
    name = v.get("name", "#%d" % n)
    names.append(name)
    want = {"name", "preset", "layers", "expect"} | ({"parent"} if v.get("expect") == "valid" else {"rules"})
    if v.get("expect") not in ("valid", "invalid"):
        errors.append("%s: expect = %r" % (name, v.get("expect")))
    if set(v) != want:
        errors.append("%s: keys %s, want %s" % (name, sorted(v), sorted(want)))
    bad = set(v.get("rules", [])) - rules
    if bad:
        errors.append("%s: unknown rule names %s" % (name, sorted(bad)))
dupes = sorted({x for x in names if names.count(x) > 1})
if dupes:
    errors.append("duplicate names: %s" % dupes)
assert not errors, "\n".join(errors)
' "$RULES"
}

@test "R4.7 valid vectors cover libc glibc and musl, toolchain gcc and llvm (read from the catalog)" {
  vectors_py '
presets = {p["id"]: p for p in cat.get("preset", [])}
seen = set()
for v in vec.get("vector", []):
    if v.get("expect") == "valid" and v.get("preset") in presets:
        p = presets[v["preset"]]
        seen |= {("libc", p.get("libc")), ("toolchain", p.get("toolchain"))}
missing = {("libc", "glibc"), ("libc", "musl"), ("toolchain", "gcc"), ("toolchain", "llvm")} - seen
assert not missing, sorted(missing)
'
}

@test "R4.8 the file has a two-rule vector, a repeated-layer vector and an out-of-rank-order vector" {
  vectors_py '
types = cat["types"]
rank = {l["id"]: types[l["type"]]["rank"] for l in cat.get("layer", [])}
two = [v["name"] for v in vec.get("vector", []) if len(set(v.get("rules", []))) >= 2]
dup = [v["name"] for v in vec.get("vector", []) if len(v["layers"]) != len(set(v["layers"]))]
def out_of_order(layers):
    r = [rank[l] for l in layers if l in rank]
    return any(a > b for a, b in zip(r, r[1:]))
ooo = [v["name"] for v in vec.get("vector", []) if out_of_order(v["layers"])]
assert two, "no vector breaks two different rules at once"
assert dup, "no vector names the same layer twice"
assert ooo, "no vector lists its layers out of type-rank order"
'
}

@test "R5.1 oracle: every vector agrees with --compose run by this suite (parent exact, rules as a set)" {
  local errors="" name preset expect want layers got n=0
  [ -f "$VECTORS" ] || {
    echo "the vectors file $VECTORS does not exist" >&2
    false
  }
  # one record per vector: name TAB preset TAB expect TAB want TAB layers
  # (want = parent lines or sorted rule names, joined by spaces)
  while IFS=$'\t' read -r name preset expect want layers; do
    n=$((n + 1))
    # shellcheck disable=SC2086 # layers is a space-separated id list on purpose
    run --separate-stderr "$SCRIPT" --compose "$preset" $layers
    if [ "$expect" = valid ]; then
      got=$(tr '\n' ' ' <<<"$output" | sed 's/ $//')
      [ "$status" -eq 0 ] && [ "$got" = "$want" ] ||
        errors+="$name: want exit 0 + [$want], got exit $status + [$got]"$'\n'
    else
      got=$(sed -nE 's/^compose: ([a-z-]+): .*/\1/p' <<<"$output" | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//')
      [ "$status" -eq 1 ] && [ "$got" = "$want" ] ||
        errors+="$name: want exit 1 + {$want}, got exit $status + {$got}"$'\n'
    fi
  done < <(vectors_py '
for v in vec.get("vector", []):
    if v["expect"] == "valid":
        want = " ".join(v["parent"])
    else:
        want = " ".join(sorted(set(v["rules"])))
    print("\t".join([v["name"], v["preset"], v["expect"], want, " ".join(v["layers"])]))
')
  [ "$n" -gt 0 ] || {
    echo "no vector was read from $VECTORS" >&2
    false
  }
  [ -z "$errors" ] || {
    printf '%s' "$errors" >&2
    false
  }
}

@test "R7.2 the vectors file opens with a header naming its consumers, its keys and how to run a vector" {
  local header w
  [ -f "$VECTORS" ]
  header=$(awk '/^[[:space:]]*(#|$)/ { print; next } { exit }' "$VECTORS")
  [ -n "$header" ]
  for w in 'check-profile-matrix' 'bentoo profile' 'shidashi order' \
    name preset layers expect parent rules rules_without_instance compose; do
    grep -qi -- "$w" <<<"$header" || {
      echo "the vectors header does not mention $w" >&2
      false
    }
  done
}
