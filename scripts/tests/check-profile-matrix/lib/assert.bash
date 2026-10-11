# shellcheck shell=bash
# Output assertions shared by the unit suite (../*.bats) and the integration
# suite (../integration/*.bats).
#
# "Output names X" is checked as a WHOLE TOKEN, never as a substring. The
# catalog deliberately holds ids where one is a prefix of another
#   features/hardware/nvidia      vs  features/hardware/nvidia-legacy
#   default/linux/amd64/23.0      vs  default/linux/amd64/23.0/systemd
# and a substring test would let the shorter id be "named" by a line that only
# names the longer one -- the assertion would go green for the wrong reason.
#
# Token boundary:
#   before: no [A-Za-z0-9_.-]  ('/' IS allowed, so "profiles/<id>" or
#           "layers/<id>" still names <id>)
#   after:  no [A-Za-z0-9_/-]  ('.', ':', ',', quotes, space, end are fine)
# A token may list alternatives separated by '|' ("multilib|1"): ids, keys and
# values never contain '|'.

# _line_has_one LINE TOKEN -- TOKEN (a single alternative) occurs delimited.
_line_has_one() {
  local line=$1 tok=$2 pre post
  [ -n "$tok" ] || return 1
  while [[ $line == *"$tok"* ]]; do
    pre=${line%%"$tok"*}
    line=${line#*"$tok"}
    post=${line:0:1}
    if [[ ! ${pre: -1} =~ [A-Za-z0-9_.-] && ! $post =~ [A-Za-z0-9_/-] ]]; then
      return 0
    fi
  done
  return 1
}

# _line_has LINE TOKEN -- any '|'-separated alternative of TOKEN occurs.
_line_has() {
  local alt
  local IFS='|'
  for alt in $2; do
    _line_has_one "$1" "$alt" && return 0
  done
  return 1
}

# _first_line_with PREFIX TOKEN... -- some line of $output that starts with
# PREFIX holds every TOKEN.
_first_line_with() {
  local prefix=$1 line tok ok
  shift
  while IFS= read -r line; do
    [[ $line == "$prefix"* ]] || continue
    ok=1
    for tok in "$@"; do
      _line_has "$line" "$tok" || {
        ok=0
        break
      }
    done
    ((ok)) && return 0
  done <<<"$output"
  return 1
}

_dump() {
  printf '%s\n--- exit status: %s\n--- output ---\n%s\n' "$1" "${status:-?}" "$output" >&2
  if [ -n "${stderr+x}" ]; then printf -- '--- stderr ---\n%s\n' "$stderr" >&2; fi
}

# line_names TOKEN... -- one output line names every TOKEN.
line_names() {
  _first_line_with "" "$@" && return 0
  _dump "no output line names all of: $*"
  return 1
}

# catalog_line_names TOKEN... -- one "catalog: " failure line names every TOKEN
# (contract: --static failure lines are `catalog: <rule>: <id/key>`).
catalog_line_names() {
  _first_line_with "catalog: " "$@" && return 0
  _dump "no 'catalog: ' line names all of: $*"
  return 1
}

# line_names_file SUFFIX -- one output line holds SUFFIX (a path tail such as
# "targets/server/etc/sysctl.d/50-server.conf"), not followed by an id char.
# Absolute and tree-relative spellings of the path both satisfy it.
line_names_file() {
  local line
  while IFS= read -r line; do
    while [[ $line == *"$1"* ]]; do
      line=${line#*"$1"}
      [[ ! ${line:0:1} =~ [A-Za-z0-9_/-] ]] && return 0
    done
  done <<<"$output"
  _dump "no output line names the file: $1"
  return 1
}

# status_is N -- exit status of the last `run` is N; dumps output otherwise.
status_is() {
  [ "$status" -eq "$1" ] && return 0
  _dump "expected exit $1"
  return 1
}

# output_is TEXT -- stdout of the last `run --separate-stderr` is exactly TEXT.
output_is() {
  [ "$output" = "$1" ] && return 0
  _dump "expected stdout:
$1"
  return 1
}
