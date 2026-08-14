# Dead and unreachable upstreams

Packages whose official upstream source cannot be probed, or no longer exists at
all. Recorded so that an **unverifiable** package is never mistaken for a
**verified** one, and so that a future sweep does not raise a package as
"behind" when there is nothing left to be behind of.

## Why this file and not `packages.toml`

`packages.toml` maps **overlay** packages, and every record there is a promise
that some endpoint answers — `url` plus a working `parser`. Neither holds here:

- **None of the nine is a `bentoo` package.** All are installed from `::gentoo`,
  so the overlay has no record to disable and no maintenance duty over them.
- **An unreachable host cannot back a probe.** Authoring a record whose fetch is
  guaranteed to fail would break that file's own contract, and `enabled = false`
  is for a record that *once* worked, not for one that never can.

So the register lives here: a plain tracked file, next to the thing it
complements, visible to a fresh clone and to a second maintainer.

Its sibling `not-packageable.md` records the opposite failure: an upstream that
probes perfectly well, but whose artifact cannot be turned into an ebuild.

## A. Unreachable — the current upstream version cannot be confirmed

The package may or may not be behind. Nobody can tell, and that is the point:
these must **not** be counted as up to date.

| Package | Installed | Source | Why it cannot be probed |
|---|---|---|---|
| `app-dicts/aspell-pt` | `20251001` | `natura.di.uminho.pt` | DNS resolves, TCP 80/443 never answers (timeout). No alternative source found. |
| `app-dicts/myspell-pt` | `20120420` | `darkstar.ist.utl.pt` | No DNS record. The fallback, `natura.di.uminho.pt`, is the host above. Upstream files carry no version anyway. |
| `net-print/epson-inkjet-printer-escpr` | `1.8.8` | `download.ebz.epson.net` | HTTP 403 to every request — an Akamai IP-level block, browser User-Agent included. Debian's own watch file declares upstream untrackable; sid is also on 1.8.8. |

## B. Dead but complete — the installed version is the last ever published

Upstream is gone and will publish nothing further. These are **not** bump
candidates and must never be raised as such.

| Package | Installed | Source | Evidence that it is the last |
|---|---|---|---|
| `app-cdr/cdrtools` | `3.02_alpha09` | SourceForge `cdrtools` | Last file in `/alpha` and `/ALPHA`; a10 and a11 are 404. Jörg Schilling died in 2021 and the project stopped with him. |
| `x11-misc/wmctrl` | `1.07` | `github.com/Conservatory/wmctrl` | Upstream's last release was January 2005. The repo is only the Conservatory's archive copy — no tags, last push 2018-09-10. |
| `app-containers/docker-swarm` | `1.2.9` | `github.com/docker/classicswarm` | Redirects to `docker-archive/classicswarm`, `archived=true`, last push 2020-06-11. Its newest release is `v1.2.9` (2018-06-05) — the installed version. Succeeded by `docker/swarmkit`. |
| `app-dicts/myspell-nn` | `2.0.10` | `alioth.debian.org` + SF `spell-norwegian` | alioth.debian.org was retired and no longer resolves; the SourceForge project returns 404; freshmeat is shut down. |
| `sys-firmware/sgabios` | `0.1_pre10` | `gitlab.com/qemu-project/sgabios` | **No confirmable last version.** code.google.com is extinct; the QEMU repo has **zero tags** (GitLab tags API returns an empty array), HEAD `72f39d4` from 2018-07-15. The ebuild pins commit `23d4749` from 2010. |
| `app-dicts/myspell-mi` | `20190630` | `github.com/scardracs/gentoo-packages` | **No confirmable last version.** The source repo was deleted (API: `Not Found`), the distfile is absent from the Gentoo mirrors, and there is no upstream feed left. |

## How to re-verify

Nothing here is taken on trust — every line above was re-probed on **2026-08-03**
and each claim is reproducible:

```bash
# A: the four dead hosts. DNS state and HTTP status, separately —
# a host can resolve and still refuse every connection.
for h in natura.di.uminho.pt darkstar.ist.utl.pt \
         download.ebz.epson.net alioth.debian.org; do
  printf '%-28s dns=' "$h"
  getent hosts "$h" >/dev/null 2>&1 && printf 'OK  ' || printf 'NXDOMAIN  '
  curl -sS -m 15 -o /dev/null -w 'http=%{http_code}\n' "https://$h/"
done
# observed: natura 000 (timeout) · darkstar NXDOMAIN
#           epson 403 (Akamai) · alioth NXDOMAIN

# B: the archived repositories. -L matters — classicswarm moved.
curl -sSL -H 'User-Agent: bentoo-autoupdate' \
  https://api.github.com/repos/docker/classicswarm \
  | jq -r '"\(.full_name) archived=\(.archived) pushed=\(.pushed_at)"'

# sgabios: an empty array is the finding, not an error.
curl -sS 'https://gitlab.com/api/v4/projects/qemu-project%2Fsgabios/repository/tags' \
  | jq 'length'
```

**Beware the inverted User-Agent** (the same trap `packages.toml` documents):
SourceForge answers 403 and `gitlab.freedesktop.org` serves an Anubis challenge
when the UA looks like a *browser*; a CLI UA passes. Anubis replies **HTTP 200**
with an HTML body, so a status code alone never proves an artifact is real.

---

Source: story 006 (full-system upstream sweep, 2026-08-01), requirements R3.1
and R3.3. The per-package sweep evidence lives in that story's `sweep-data.tsv`
and `sweep-report.md`.
