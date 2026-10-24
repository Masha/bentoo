#!/usr/bin/env bats
# Unit -- Task 5.1: --full resolves every preset alone, before its layers.
# Requirements: R6.3 (and R2.5, the preset-alone resolution it reuses).
#
# Contract (story.md R6.3, design.md C4):
#   R6.3  WHEN --full runs, each preset is resolved alone (no layer,
#         `emerge -pq @system @profile` in an isolated root), and --full fails
#         naming every preset whose resolution fails. A preset that breaks with
#         no layer is a gap naming THAT PRESET AND NO LAYER.
#   The preset-alone selection is one more resolution job per preset: the
#   summary's `resolved=` count grows by the number of presets.
#
# NOTHING HERE RUNS PORTAGE. `--full` runs on a fixture catalog with the three
# stubs of failure-paths.bats first on PATH (copied, not shared: that file
# keeps its own):
#   bwrap     consumes bwrap's options, exports every --setenv, runs the rest;
#             answers the profile_path probe with the composed profile.
#   emerge    the body each case gives it. `sel_has ID` is true when a line of
#             $PORTAGE_CONFIGROOT/etc/portage/make.profile/parent names ID as a
#             whole id; `alone ID` is true when the parent names ID and none of
#             the fixture layers -- so a case fails exactly the preset-alone
#             selection of ID, which today's --full never builds.
#   portageq  fails loudly: a self-test must never read the host's Portage.
# The fixture presets are a prefix pair (P_PLAIN is a prefix of P_PURE), so a
# FAIL line that names the wrong one of the two cannot pass for the right one.
# The only host dependency is the EXISTENCE of /var/db/repos/gentoo, a --full
# prerequisite; without it every case is SKIPPED, never failed.

load lib/fixture

setup() {
  [ -d /var/db/repos/gentoo ] ||
    skip "--full requires /var/db/repos/gentoo to exist (prerequisite check); the stubs never read it"
  STUBS=$BATS_TEST_TMPDIR/stubs
  mkdir -p "$STUBS"
  stub_bwrap
  stub_portageq
  stub_emerge <<<'exit 0'
  export PATH=$STUBS:$PATH
  unset CHECK_PROFILE_MATRIX_COMPOSE CHECK_PROFILE_MATRIX_SELF_TEST STUB_PROFILE STUB_PROFILE_REL
}

### stubs (copied from failure-paths.bats) ##############################

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

# stub_emerge -- prelude (sel_has, alone, $P_PLAIN, $P_PURE), then the body
# read from stdin.
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
# alone ID -- the selection is preset ID with no fixture layer.
alone() { sel_has "$1" && ! sel_has features/alpha && ! sel_has features/beta; }
EOF
    cat
  } >"$STUBS/emerge"
  chmod +x "$STUBS/emerge"
}

### fixture ############################################################

# fx_pair -- the prefix preset pair, two mix-ins allowed together. Today
# --full builds 3 selections per preset (alpha, beta, alpha+beta): 6 jobs.
# With the preset-alone selection: 8.
fx_pair() {
  fx_init
  fx_header
  fx_preset "$P_PLAIN" openrc true none
  fx_preset "$P_PURE" openrc false none
  fx_layer features/alpha mix-in
  fx_layer features/beta mix-in
}

FX_LAYERS=(features/alpha features/beta)

# fail_alone_names PID -- some `resolve: FAIL` line names PID as a whole id
# and names no fixture layer.
fail_alone_names() {
  local line lid ok
  while IFS= read -r line; do
    [[ $line == "resolve: FAIL "* ]] || continue
    _line_has "$line" "$1" || continue
    ok=1
    for lid in "${FX_LAYERS[@]}"; do _line_has "$line" "$lid" && ok=0; done
    ((ok)) && return 0
  done <<<"$output"
  _dump "no 'resolve: FAIL' line names $1 alone (with no layer)"
  return 1
}

# no_fail_alone_names PID -- no `resolve: FAIL` line names PID without a layer.
no_fail_alone_names() {
  local line lid ok
  while IFS= read -r line; do
    [[ $line == "resolve: FAIL "* ]] || continue
    _line_has "$line" "$1" || continue
    ok=1
    for lid in "${FX_LAYERS[@]}"; do _line_has "$line" "$lid" && ok=0; done
    if ((ok)); then
      _dump "a 'resolve: FAIL' line names $1 alone: $line"
      return 1
    fi
  done <<<"$output"
  return 0
}

summary_is() {
  local line
  line=$(grep -E '^resolve: resolved=' <<<"$output" | tail -n1)
  [[ $line == "resolve: $1" ]] && return 0
  _dump "expected summary 'resolve: $1', got '${line:-none}'"
  return 1
}

# --- hostile halves first: the right preset, and only the preset ------------

@test "R6.3 hostile: the PREFIX preset failing alone is named, not the longer id" {
  fx_pair
  stub_emerge <<'EOF'
if alone "$P_PLAIN"; then
  echo '!!! fixture-preset-alone: @system does not resolve on this preset'
  exit 1
fi
exit 0
EOF
  run "$SCRIPT" --full
  status_is 1
  fail_alone_names "$P_PLAIN"
  no_fail_alone_names "$P_PURE"
  summary_is 'resolved=8 forbidden=0 failed=1'
}

@test "R6.3 hostile converse: the LONGER preset failing alone is named, not its prefix" {
  fx_pair
  stub_emerge <<'EOF'
if alone "$P_PURE"; then
  echo '!!! fixture-preset-alone: @system does not resolve on this preset'
  exit 1
fi
exit 0
EOF
  run "$SCRIPT" --full
  status_is 1
  fail_alone_names "$P_PURE"
  no_fail_alone_names "$P_PLAIN"
  summary_is 'resolved=8 forbidden=0 failed=1'
}

@test "R6.3 hostile: a failure only WITH a layer is not reported as the preset alone" {
  fx_pair
  stub_emerge <<'EOF'
if sel_has "$P_PLAIN" && sel_has features/alpha && ! sel_has features/beta; then
  echo '!!! fixture-layer-only: features/alpha breaks this preset'
  exit 1
fi
exit 0
EOF
  run "$SCRIPT" --full
  status_is 1
  line_names "resolve: FAIL" "$P_PLAIN" features/alpha
  no_fail_alone_names "$P_PLAIN"
  no_fail_alone_names "$P_PURE"
}

# --- benign: every failing preset named; a passing tree passes ---------------

@test "R6.3 every preset that fails alone is named, one FAIL line each" {
  fx_pair
  stub_emerge <<'EOF'
if alone "$P_PLAIN" || alone "$P_PURE"; then
  echo '!!! fixture-preset-alone: @system does not resolve on this preset'
  exit 1
fi
exit 0
EOF
  run "$SCRIPT" --full
  status_is 1
  fail_alone_names "$P_PLAIN"
  fail_alone_names "$P_PURE"
  summary_is 'resolved=8 forbidden=0 failed=2'
}

@test "R6.3 a passing tree exits 0 and resolves one more job per preset (6 + 2)" {
  fx_pair
  run "$SCRIPT" --full
  status_is 0
  summary_is 'resolved=8 forbidden=0 failed=0'
}
