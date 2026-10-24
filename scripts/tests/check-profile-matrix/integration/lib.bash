# shellcheck shell=bash
# Helpers for the INTEGRATION suite: tests against the real overlay tree and
# the host's Portage + /var/db/repos/gentoo.
#
# NOT run by `check-profile-matrix.sh --self-test` (which runs the unit suite
# one directory up, without -r): these read the tree and call Portage, and
# the resolution tests take minutes. Run them with
#   bats scripts/tests/check-profile-matrix/integration/
#   bats --filter-tags '!slow' scripts/tests/check-profile-matrix/integration/
#
# Portage is used as the ORACLE: what a layer does is read back from
# Portage itself (sets, effective USE, VIDEO_CARDS, masks, the profile stack)
# in a throwaway PORTAGE_CONFIGROOT, never from the script's own report. ROOT
# is never set (design.md GOTCHA: ROOT=<tmp> made Portage read the host's
# make.profile).

bats_require_minimum_version 1.5.0

load ../lib/assert

# The checkout under test: BENTOO_TREE overrides, default is the repository
# this suite lives in (scripts/tests/check-profile-matrix/integration -> ../../../..).
TREE=${BENTOO_TREE:-$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd -P)}
SCRIPT=${CHECK_PROFILE_MATRIX:-$TREE/scripts/check-profile-matrix.sh}
GENTOO_REPO=/var/db/repos/gentoo

# The 6 reference presets of --staged (design.md C6, plus the desktop axis:
# without a desktop preset the desktop-only layers are never resolved, and the
# musl one of story 002, where a libc-sensitive layer fails first).
REF_PRESETS=(
  default/linux/amd64/23.0
  default/linux/amd64/23.0/systemd
  default/linux/amd64/23.0/no-multilib
  default/linux/amd64/23.0/hardened
  default/linux/amd64/23.0/desktop/plasma/systemd
  default/linux/amd64/23.0/musl
)

need_portage() {
  command -v emerge >/dev/null || skip "emerge is not installed"
  [ -d "$GENTOO_REPO/profiles" ] || skip "no ::gentoo tree at $GENTOO_REPO"
  python3 -c 'import portage' 2>/dev/null || skip "python3 cannot import portage"
}

# mk_croot DIR BENTOO-LOCATION -- an empty throwaway config root: repos.conf
# (gentoo + bentoo), make.conf and an empty make.profile/ directory.
# ACCEPT_LICENSE="*" stands for the user's licence acceptance, which is not
# what any test here measures (nvidia-drivers is otherwise invisible).
mk_croot() {
  mkdir -p "$1/etc/portage/repos.conf" "$1/etc/portage/make.profile"
  printf '[DEFAULT]\nmain-repo = gentoo\n\n[gentoo]\nlocation = %s\n\n[bentoo]\nlocation = %s\n' \
    "$GENTOO_REPO" "$2" >"$1/etc/portage/repos.conf/repos.conf"
  printf 'ACCEPT_LICENSE="*"\n' >"$1/etc/portage/make.conf"
}

# compose_croot DIR PRESET [LAYER...] -- config root whose make.profile/parent
# is exactly what `--compose` prints for the selection (the contract path the
# sibling tool uses). Fails, with the script's output, if --compose rejects it.
compose_croot() {
  local cr=$1 parent
  shift
  parent=$("$SCRIPT" --compose "$@" 2>&1) || {
    printf -- '--compose %s failed:\n%s\n' "$*" "$parent" >&2
    return 1
  }
  mk_croot "$cr" "$TREE"
  printf '%s\n' "$parent" >"$cr/etc/portage/make.profile/parent"
}

# isolated_emerge CROOT ARGS... -- `emerge ARGS` under CROOT with this host's
# installed packages and world file hidden (task 5.1): bwrap mounts a tmpfs
# over /var/db (re-binding /var/db/repos read-only) and over /var/lib/portage.
# Without it, PORTAGE_CONFIGROOT alone still reads the host's package database,
# and a systemd host makes every openrc preset "fail" with slot conflicts that
# have nothing to do with the profile. Portage's own user and group are mapped
# to the caller's, because the portage group does not exist in the namespace.
isolated_emerge() {
  local cr=$1 dep
  shift
  command -v bwrap >/dev/null || skip "bwrap is not installed"
  dep=$(mktemp -d -p "$BATS_TEST_TMPDIR")
  bwrap --dev-bind / / --tmpfs /var/db --ro-bind /var/db/repos /var/db/repos \
    --tmpfs /var/lib/portage \
    --setenv PORTAGE_CONFIGROOT "$cr" --setenv PORTAGE_DEPCACHEDIR "$dep" \
    --setenv PORTAGE_USERNAME "$(id -un)" --setenv PORTAGE_GRPNAME "$(id -gn)" \
    emerge "$@"
}

# resolves_ok -- the last `run isolated_emerge -p ...` resolved: exit 0, or the
# only error is a circular dependency. From an empty root, @system always hits
# bootstrap cycles (xz-utils <-> elt-patches); they are about merge ORDER, found
# after the graph is complete, and a real install starts from a stage3. Every
# profile error (mask, slot conflict, unsatisfiable USE) prints `!!!` first.
resolves_ok() {
  [ "$status" -eq 0 ] && return 0
  # "no ebuilds to satisfy" is a graph error reported as an `emerge:` line
  # "changes are necessary" is autounmask completing the graph anyway
  if [[ $output == *"circular dependencies"* && $output != *'!!!'* &&
    $output != *"changes are necessary"* &&
    $'\n'$output != *$'\n'"emerge: "* ]]; then
    return 0
  fi
  _dump "the selection does not resolve"
  return 1
}

# pq CROOT QUERY [ARG] -- ask Portage, under CROOT, one of:
#   set NAME      cp of every atom in package set NAME, sorted
#   var NAME      a global configuration variable (USE, VIDEO_CARDS, ...)
#   use ATOM      effective USE of ATOM's best visible (else newest) version
#   iuse ATOM     IUSE of that same version
#   best ATOM     bestmatch-visible cpv
#   visible ATOM  every visible cpv
#   all ATOM      every cpv, visible or not
#   masks ATOM    "<cpv> <reason,reason>" for every cpv
#   stack         the profile directory stack, one path per line
pq() {
  PORTAGE_CONFIGROOT=$1 python3 -c "$_PQ_PY" "${@:2}"
}

_PQ_PY='
import sys, portage
from portage._sets import load_default_config
q, args = sys.argv[1], sys.argv[2:]
s = portage.settings
eroot = s["EROOT"]
pd = portage.db[eroot]["porttree"].dbapi
def pick(atom):
    cpv = pd.xmatch("bestmatch-visible", atom)
    if not cpv:
        allv = pd.xmatch("match-all", atom)
        cpv = portage.best(allv) if allv else ""
    return cpv
if q == "set":
    sc = load_default_config(s, portage.db[eroot])
    for cp in sorted({a.cp for a in sc.getSetAtoms(args[0])}):
        print(cp)
elif q == "var":
    print(s.get(args[0], ""))
elif q == "use":
    cpv = pick(args[0])
    if not cpv:
        sys.exit("no version of " + args[0])
    c = portage.config(clone=s)
    c.setcpv(cpv, mydb=pd)
    print(c["PORTAGE_USE"])
elif q == "iuse":
    cpv = pick(args[0])
    print(pd.aux_get(cpv, ["IUSE"])[0] if cpv else "")
elif q == "best":
    print(pd.xmatch("bestmatch-visible", args[0]))
elif q == "visible":
    for cpv in pd.xmatch("match-visible", args[0]):
        print(cpv)
elif q == "all":
    for cpv in pd.xmatch("match-all", args[0]):
        print(cpv)
elif q == "masks":
    c = portage.config(clone=s)
    for cpv in pd.xmatch("match-all", args[0]):
        print(cpv, ",".join(portage.getmaskingstatus(cpv, settings=c, portdb=pd)))
elif q == "stack":
    for p in s.profiles:
        print(p)
else:
    sys.exit("unknown query " + q)
'

# words_has "WORDS" WORD -- WORD is one of the whitespace-separated WORDS.
words_has() {
  local w
  for w in $1; do [ "$w" = "$2" ] && return 0; done
  return 1
}

# first_with_default FLAG ATOM... -- the first ATOM whose IUSE (under CROOT0)
# turns FLAG on by default ("+X"). Used to find a package where a global
# `-FLAG` is observable: on a desktop = none preset the global USE already
# lacks X, so only an IUSE default proves a layer disables it.
first_with_default() {
  local flag=$1 atom
  shift
  for atom in "$@"; do
    if words_has "$(pq "$CROOT0" iuse "$atom")" "+$flag"; then
      printf '%s' "$atom"
      return 0
    fi
  done
  printf 'no candidate defaults +%s: %s\n' "$flag" "$*" >&2
  return 1
}

# catalog_py EXPR-PROGRAM -- run Python with `cat` bound to the parsed catalog.
catalog_py() {
  python3 -c "import sys, tomllib
cat = tomllib.load(open(sys.argv[1], 'rb'))
$1" "$TREE/profiles/catalog.toml" "${@:2}"
}

# scratch_repo -- a private git repository holding the working-tree state of
# TREE (tracked + untracked-not-ignored files, uncommitted edits included),
# with one baseline commit. Staged-mode tests mutate THIS copy, never TREE.
scratch_repo() {
  R=$BATS_TEST_TMPDIR/repo
  mkdir -p "$R"
  git -C "$TREE" ls-files -z -c -o --exclude-standard |
    tar --null --ignore-failed-read -C "$TREE" -cf - -T - 2>/dev/null |
    tar -C "$R" -xf -
  git -C "$R" init -q
  git -C "$R" add -A
  _git_commit -qm baseline
}

_git_commit() {
  git -C "$R" -c user.name=bats -c user.email=bats@localhost \
    -c commit.gpgsign=false -c core.hooksPath=/dev/null commit --no-verify "$@"
}

# run_staged -- the scratch copy's own script, --staged, from inside the
# scratch repo, with TMPDIR at an empty probe directory.
run_staged() {
  TMP_PROBE=$BATS_TEST_TMPDIR/tmp-probe
  rm -rf "$TMP_PROBE"
  mkdir -p "$TMP_PROBE"
  run env -u BENTOO_TREE TMPDIR="$TMP_PROBE" \
    bash -c 'cd "$1" && exec ./scripts/check-profile-matrix.sh --staged' _ "$R"
}

# assert_tmp_clean -- R6.12: the run removed every temporary file it made.
assert_tmp_clean() {
  local left
  left=$(find "$TMP_PROBE" -mindepth 1)
  [ -z "$left" ] || {
    _dump "temporary files left behind: $left"
    return 1
  }
}

# strip_ids TEXT ID... -- TEXT with every ID removed, so a check that the
# output "names multilib" cannot be met by the preset id .../no-multilib.
strip_ids() {
  local text=$1 id
  shift
  for id in "$@"; do text=${text//"$id"/}; done
  printf '%s' "$text"
}
