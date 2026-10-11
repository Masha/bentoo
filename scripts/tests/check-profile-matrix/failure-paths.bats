#!/usr/bin/env bats
# Unit -- Task 9.2: the failure paths of the resolution modes, on stubs.
# Requirements: R6.6, R6.7, R6.9, R6.14 (gate Q4: every R4-R6 failure path has
# a passing --self-test fixture).
#
# Contract (story.md R6, design.md C6 "Resolution check per combination" and
# "Forbidden combinations (R6.7)"):
#   R6.6  an allowed combination that fails to resolve exits 1 naming the
#         preset, the layer pair and the FIRST error block from emerge (the
#         last 20 lines of its output when there is no `!!!` block).
#   R6.7  the forbidden verdict is computed from the catalog data, not from
#         --compose; --compose accepting a forbidden selection or rejecting an
#         allowed one exits 1; a --compose crash (any exit other than 0 or a
#         named rule rejection) exits 2 and is never counted as forbidden.
#   R6.9  a loaded profile other than the temporary composed one exits 2
#         naming the profile found.
#   R6.14 a combination that resolves only with a USE, keyword or licence
#         change emerge proposes (autounmask) counts as failed. Its converse
#         (design.md): a report whose only error is a bootstrap circular
#         dependency is a pass.
#
# NOTHING HERE RUNS PORTAGE. `--full` runs on a fixture catalog with three
# stubs first on PATH:
#   bwrap     consumes bwrap's options, exports every --setenv, runs the rest.
#             A python probe of `portage.settings.profile_path` is answered by
#             the stub -- $PORTAGE_CONFIGROOT$STUB_PROFILE_REL (default
#             /etc/portage/make.profile), or $STUB_PROFILE when set -- and
#             never imports Portage.
#   emerge    the body each case gives it. `sel_has ID` is true when a line of
#             $PORTAGE_CONFIGROOT/etc/portage/make.profile/parent ends in ID as
#             a whole id, so a case fails exactly the selection it names.
#   portageq  fails loudly: a resolution that reaches for it in a self-test
#             would be reading the host's Portage.
# Layer ids are fixture-only (features/alpha, ...): none is a v1 layer, so no
# R2/R3 content check -- which reads Portage settings -- applies to them.
# The only host dependency is the EXISTENCE of /var/db/repos/gentoo, a --full
# prerequisite; without it every case is SKIPPED (lost coverage, said so),
# never failed. The stubs never read it.
#
# THE SEAM R6.7 NEEDS -- the implementer adds exactly this:
#   judge() and --compose live in one program and agree by construction, so a
#   disagreement cannot be produced from catalog data. The script honours
#     CHECK_PROFILE_MATRIX_COMPOSE=<executable>
#   ONLY when CHECK_PROFILE_MATRIX_SELF_TEST=1, and then runs it in place of
#   its own composition step, once per selection, as
#     <executable> <preset-id> <layer-id>...
#   with BENTOO_TREE in the environment and the public --compose contract:
#     exit 0, parent lines on stdout          accepted
#     exit 1, `compose: <rule>: ...` lines    rejected, naming a rule
#     any other exit                          a crash: exit 2, never forbidden
#   The cases export CHECK_PROFILE_MATRIX_SELF_TEST=1 themselves, so this file
#   also runs under plain bats; --self-test need not export it. Without the
#   marker the variable is ignored (case "R6.7 ... ignored outside").

load lib/fixture

setup() {
  [ -d /var/db/repos/gentoo ] ||
    skip "--full requires /var/db/repos/gentoo to exist (prerequisite check); the stubs never read it"
  STUBS=$BATS_TEST_TMPDIR/stubs
  CALLS=$BATS_TEST_TMPDIR/compose.calls
  mkdir -p "$STUBS"
  stub_bwrap
  stub_portageq
  stub_emerge <<<'exit 0'
  export PATH=$STUBS:$PATH
  unset CHECK_PROFILE_MATRIX_COMPOSE CHECK_PROFILE_MATRIX_SELF_TEST STUB_PROFILE STUB_PROFILE_REL
}

### stubs ##############################################################

stub_bwrap() {
  cat >"$STUBS/bwrap" <<'EOF'
#!/usr/bin/env bash
# stub bwrap: no namespace, no mount -- options consumed, --setenv honoured.
while (($#)); do
  case $1 in
  --setenv) export "$2=$3"; shift 3 ;;
  --unsetenv) unset "$2"; shift 2 ;;
  --bind | --bind-try | --dev-bind | --dev-bind-try | --ro-bind | --ro-bind-try | \
    --symlink | --file | --bind-data | --ro-bind-data | --chmod) shift 3 ;;
  --tmpfs | --proc | --dev | --dir | --remount-ro | --chdir | --mqueue | --perms | \
    --size | --uid | --gid | --hostname | --lock-file | --sync-fd | --info-fd | \
    --json-status-fd | --block-fd | --userns-block-fd | --seccomp | --add-seccomp-fd | \
    --exec-label | --file-label | --cap-add | --cap-drop | --argv0 | --userns | \
    --userns2 | --pidns) shift 2 ;;
  --) shift; break ;;
  --*) shift ;;
  *) break ;;
  esac
done
case "$*" in
*profile_path*)
  printf '%s\n' "${STUB_PROFILE:-${PORTAGE_CONFIGROOT:?stub bwrap: PORTAGE_CONFIGROOT unset}${STUB_PROFILE_REL:-/etc/portage/make.profile}}"
  exit 0
  ;;
esac
exec "$@"
EOF
  chmod +x "$STUBS/bwrap"
}

stub_portageq() {
  printf '%s\n' '#!/usr/bin/env bash' \
    'echo "stub portageq: called during a self-test ($*): that reads the host Portage" >&2' \
    'exit 2' >"$STUBS/portageq"
  chmod +x "$STUBS/portageq"
}

# stub_emerge -- the emerge stub: a prelude (sel_has, $P_PLAIN, $P_PURE), then
# the body read from stdin.
stub_emerge() {
  {
    printf '#!/usr/bin/env bash\nP_PLAIN=%q\nP_PURE=%q\n' "$P_PLAIN" "$P_PURE"
    cat <<'EOF'
parent=${PORTAGE_CONFIGROOT:?stub emerge: PORTAGE_CONFIGROOT unset}/etc/portage/make.profile/parent
# sel_has ID -- a parent line is ID, or ends in :ID or /ID (whole id: the
# line for .../23.0/pure64 does not hold .../23.0).
sel_has() {
  local l
  while IFS= read -r l; do
    [[ $l == "$1" || $l == *":$1" || $l == *"/$1" ]] && return 0
  done <"$parent"
  return 1
}
EOF
    cat
  } >"$STUBS/emerge"
  chmod +x "$STUBS/emerge"
}

# stub_compose -- a --compose stand-in through the R6.7 seam: a prelude
# (logs its argv to $CALLS; $preset; is_sel ID... true when the layers are
# exactly ID...; real_compose = the script's own --compose), then the body
# read from stdin. Exports the seam variables.
stub_compose() {
  local stub=$BATS_TEST_TMPDIR/compose-stub
  {
    printf '#!/usr/bin/env bash\nreal=%q\ncalls=%q\n' "$SCRIPT" "$CALLS"
    cat <<'EOF'
printf '%s\n' "$*" >>"$calls"
preset=$1
shift
SEL=("$@")
is_sel() {
  local want l found
  (($# == ${#SEL[@]})) || return 1
  for want; do
    found=0
    for l in "${SEL[@]}"; do [ "$l" = "$want" ] && found=1; done
    ((found)) || return 1
  done
}
real_compose() { exec env -u CHECK_PROFILE_MATRIX_COMPOSE "$real" --compose "$preset" "${SEL[@]}"; }
accept() { printf 'bentoo:%s\n' "$preset" "${SEL[@]}"; exit 0; }
EOF
    cat
  } >"$stub"
  chmod +x "$stub"
  export CHECK_PROFILE_MATRIX_COMPOSE=$stub CHECK_PROFILE_MATRIX_SELF_TEST=1
}

### fixtures ###########################################################

# fx_pair -- two presets where one id is a prefix of the other, two mix-ins
# allowed together: 6 selections, all allowed.
fx_pair() {
  fx_init
  fx_header
  fx_preset "$P_PLAIN" openrc true none
  fx_preset "$P_PURE" openrc false none
  fx_layer features/alpha mix-in
  fx_layer features/beta mix-in
}

# fx_rules -- one preset (desktop none) and one forbidden selection per rule:
#   exclusive  targets/one + targets/two
#   conflict   features/alpha + features/gamma
#   requires   features/needy without features/alpha (allowed WITH it)
#   base       features/kde-only (needs desktop plasma)
fx_rules() {
  fx_init
  fx_header
  fx_preset "$P_PLAIN" openrc true none
  fx_layer targets/one flavor
  fx_layer targets/two flavor
  fx_layer features/alpha mix-in 'conflicts = ["features/gamma"]'
  fx_layer features/gamma mix-in 'conflicts = ["features/alpha"]'
  fx_layer features/needy mix-in 'requires = ["features/alpha"]'
  fx_layer features/kde-only mix-in 'base = { desktop = ["plasma"] }'
}

no_output_has() {
  [[ $output != *"$1"* ]] && return 0
  _dump "output must not hold: $1"
  return 1
}

output_has() {
  [[ $output == *"$1"* ]] && return 0
  _dump "output must hold: $1"
  return 1
}

# --- R6.6: an allowed combination that fails to resolve ----------------------

@test "R6.6 a failing pair exits 1 naming the preset, the pair and only the first !!! block" {
  fx_pair
  # The failing preset is the PREFIX one: a line naming only .../23.0/pure64
  # does not name it (whole-token match).
  stub_emerge <<'EOF'
if sel_has "$P_PLAIN" && sel_has features/alpha && sel_has features/beta; then
  cat <<'OUT'
Calculating dependencies... done!
!!! fixture-first-block: Multiple package instances within a single package slot have been pulled
!!! fixture-first-block: into the dependency graph, resulting in a slot conflict:

media-libs/fixture:0

  (media-libs/fixture-2.0:0/0::gentoo, ebuild scheduled for merge) pulled in by

!!! fixture-second-block: must not be printed
OUT
  exit 1
fi
exit 0
EOF
  run "$SCRIPT" --full
  status_is 1
  line_names "$P_PLAIN" features/alpha features/beta
  output_has '!!! fixture-first-block: Multiple package instances'
  output_has '!!! fixture-first-block: into the dependency graph'
  no_output_has fixture-second-block
}

@test "R6.6 with no !!! block the report carries the last 20 lines of emerge's output" {
  fx_pair
  stub_emerge <<'EOF'
if sel_has "$P_PURE" && sel_has features/alpha && sel_has features/beta; then
  for n in $(seq -w 1 30); do echo "fixture-tail-line-$n"; done
  exit 1
fi
exit 0
EOF
  run "$SCRIPT" --full
  status_is 1
  line_names "$P_PURE" features/alpha features/beta
  local n
  for n in $(seq -w 11 30); do output_has "fixture-tail-line-$n"; done
  for n in $(seq -w 1 10); do no_output_has "fixture-tail-line-$n"; done
}

# --- R6.14: autounmask is a failure; a bootstrap cycle alone is not ------------

# autounmask KIND FILE ENTRY -- an emerge body proposing a KIND change for
# features/alpha on $P_PLAIN, then completing the graph and reporting the
# bootstrap cycle a pass would show. No `!!!` anywhere.
autounmask() {
  stub_emerge <<EOF
if sel_has "\$P_PLAIN" && sel_has features/alpha; then
  cat <<'OUT'
Calculating dependencies... done!

The following $1 changes are necessary to proceed:
 (see "$2" in the portage(5) man page for more details)
# required by @profile
$3

 * Error: circular dependencies:

(app-arch/xz-utils-5.8.1-r1:0/0::gentoo, ebuild scheduled for merge) depends on
 (dev-build/libtool-2.5.4:2/2::gentoo, ebuild scheduled for merge) (buildtime)
OUT
  exit 1
fi
exit 0
EOF
}

@test "R6.14 a USE change emerge proposes counts the combination as failed" {
  fx_pair
  autounmask USE package.use '>=media-libs/fixture-1.0 abi_x86_32'
  run "$SCRIPT" --full
  status_is 1
  line_names "$P_PLAIN" features/alpha
}

@test "R6.14 a keyword change emerge proposes counts the combination as failed" {
  fx_pair
  autounmask keyword package.accept_keywords '=media-libs/fixture-1.0 ~amd64'
  run "$SCRIPT" --full
  status_is 1
  line_names "$P_PLAIN" features/alpha
}

@test "R6.14 a licence change emerge proposes counts the combination as failed" {
  fx_pair
  autounmask license package.license '=sys-kernel/fixture-firmware-1.0 fixture-EULA'
  run "$SCRIPT" --full
  status_is 1
  line_names "$P_PLAIN" features/alpha
}

@test "R6.14 converse: a report whose only error is a bootstrap cycle is a pass" {
  fx_pair
  stub_emerge <<'EOF'
cat <<'OUT'
Calculating dependencies... done!

 * Error: circular dependencies:

(app-arch/xz-utils-5.8.1-r1:0/0::gentoo, ebuild scheduled for merge) depends on
 (dev-build/libtool-2.5.4:2/2::gentoo, ebuild scheduled for merge) (buildtime)
OUT
exit 1
EOF
  run "$SCRIPT" --full
  status_is 0
}

# --- R6.9: Portage must load the temporary composed profile ------------------

@test "R6.9 a host profile loaded instead of the composed one exits 2 naming it" {
  fx_pair
  local host=$BATS_TEST_TMPDIR/host/etc/portage/make.profile
  mkdir -p "$host"
  printf 'gentoo:default/linux/amd64/23.0\n' >"$host/parent"
  run env STUB_PROFILE="$host" "$SCRIPT" --full
  status_is 2
  line_names_file "$host"
}

@test "R6.9 a sibling whose path merely starts with the composed one exits 2 naming it" {
  fx_pair
  run env STUB_PROFILE_REL=/etc/portage/make.profile.host "$SCRIPT" --full
  status_is 2
  line_names_file etc/portage/make.profile.host
}

@test "R6.9 converse: the composed profile spelled differently is the composed profile" {
  fx_pair
  run env STUB_PROFILE_REL=/etc/portage/./make.profile/ "$SCRIPT" --full
  status_is 0
}

# --- R6.7: --compose judged against the catalog data, both directions ---------

@test "R6.7 --compose accepting two flavors (exclusive type) exits 1 naming them" {
  fx_rules
  stub_compose <<'EOF'
if is_sel targets/one targets/two || is_sel targets/two targets/one; then accept; fi
real_compose
EOF
  run "$SCRIPT" --full
  status_is 1
  line_names targets/one targets/two
}

@test "R6.7 --compose accepting a declared conflict exits 1 naming the pair" {
  fx_rules
  stub_compose <<'EOF'
if is_sel features/alpha features/gamma; then accept; fi
real_compose
EOF
  run "$SCRIPT" --full
  status_is 1
  line_names features/alpha features/gamma
}

@test "R6.7 --compose accepting an unmet requires exits 1 naming the layer" {
  fx_rules
  stub_compose <<'EOF'
if is_sel features/needy; then accept; fi
real_compose
EOF
  run "$SCRIPT" --full
  status_is 1
  line_names features/needy
}

@test "R6.7 --compose accepting a base the preset does not meet exits 1 naming the layer" {
  fx_rules
  stub_compose <<'EOF'
if is_sel features/kde-only; then accept; fi
real_compose
EOF
  run "$SCRIPT" --full
  status_is 1
  line_names features/kde-only
}

@test "R6.7 --compose rejecting an allowed pair with a rule-shaped message exits 1 naming it" {
  fx_rules
  stub_compose <<'EOF'
if is_sel features/alpha targets/one; then
  echo 'compose: conflict: features/alpha conflicts with targets/one'
  exit 1
fi
real_compose
EOF
  run "$SCRIPT" --full
  status_is 1
  line_names features/alpha targets/one
}

@test "R6.7 --compose rejecting needy WITH its requirement exits 1 (needy is not always forbidden)" {
  fx_rules
  stub_compose <<'EOF'
if is_sel features/needy features/alpha; then
  echo 'compose: requires: features/needy requires features/alpha, which is not selected'
  exit 1
fi
real_compose
EOF
  run "$SCRIPT" --full
  status_is 1
  line_names features/needy features/alpha
}

@test "R6.7 a --compose crash on a FORBIDDEN selection exits 2, never counted as forbidden" {
  fx_rules
  local code
  # 3 is the reader's internal "gap" code: from --compose it is still a crash.
  for code in 2 3 139; do
    stub_compose <<EOF
if is_sel features/alpha features/gamma; then
  echo 'Traceback (most recent call last): fixture crash' >&2
  exit $code
fi
real_compose
EOF
    run "$SCRIPT" --full
    status_is 2 || {
      echo "--compose exit $code on a forbidden selection" >&2
      return 1
    }
  done
}

@test "R6.7 a --compose crash on an ALLOWED selection exits 2, not 1" {
  fx_rules
  stub_compose <<'EOF'
if is_sel features/alpha targets/one; then
  echo 'Traceback (most recent call last): fixture crash' >&2
  exit 2
fi
real_compose
EOF
  run "$SCRIPT" --full
  status_is 2
}

@test "R6.7 an agreeing --compose through the seam passes and is called for the selections" {
  fx_rules
  stub_compose <<<'real_compose'
  run "$SCRIPT" --full
  status_is 0
  [ -s "$CALLS" ] || {
    _dump "the --compose override was never called: the seam is not read"
    false
  }
  # the forbidden selections went through it too, not only the allowed ones
  grep -qxF -- "$P_PLAIN features/alpha features/gamma" "$CALLS" ||
    grep -qxF -- "$P_PLAIN features/gamma features/alpha" "$CALLS" || {
    _dump "the forbidden alpha+gamma selection never reached --compose"
    cat "$CALLS" >&2
    false
  }
}

@test "R6.7 the override is ignored outside the self-test (production path)" {
  fx_rules
  stub_compose <<<'accept'
  unset CHECK_PROFILE_MATRIX_SELF_TEST
  run "$SCRIPT" --full
  status_is 0
  [ ! -e "$CALLS" ] || {
    _dump "the --compose override ran without CHECK_PROFILE_MATRIX_SELF_TEST=1"
    false
  }
}
