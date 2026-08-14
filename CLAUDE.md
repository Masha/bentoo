# bentoo

A Gentoo overlay that serves as the base of an **operating system project**.
`masters = gentoo`; ~330 packages.

## Guiding principle

**bentoo is a distribution, not a machine.** The maintainer (`lucascouts`) is
only the person who packages it — not the target audience.

Practical consequences, binding on every packaging decision:

- **Never size a package by the maintainer's hardware.** That hardware is
  irrelevant to the decision to port, to the USE flags exposed, and to the
  defaults chosen.
- **Cover third-party hardware by default:** NVIDIA (legacy generations
  included), AMD (ROCm/Vulkan), Intel (SYCL/oneAPI), NPUs (XDNA2 and the like),
  CPU-only, and ARM64 — not just x86_64 with a discrete GPU.
- **Cover third-party use cases:** desktop, workstation, server, headless,
  container, edge.
- Acceleration backends ship as **optional USE flags**, never hardcoded. Nobody
  should be forced to pull in CUDA to use a package on CPU.
- `KEYWORDS` must include `~arm64` whenever upstream supports it; restricting to
  `~amd64` is a decision that needs a justification, not a default.
- "It is not useful to me" is **not** an exclusion criterion. "Upstream
  abandoned", "does not build", "no clear license" are.

## Overlay conventions

- `thin-manifests = true` — a `Manifest` records only `DIST` entries. Ebuilds,
  patches and metadata are covered by git, not by the Manifest.
- Autoupdate is configured in `.autoupdate/packages.toml`. Every record is a
  promise that some endpoint answers: `url` plus a working `parser`.
- A package removed from the overlay becomes `enabled = false` in
  `packages.toml`; the entry is never deleted, which preserves the probe that
  was already verified.
- An upstream that cannot be probed at all gets **no** record. Those are listed
  in `.autoupdate/dead-upstreams.md`, so an unverifiable package is never
  mistaken for a verified one.
- An upstream that was assessed and **rejected** goes in
  `.autoupdate/not-packageable.md`, with the evidence and the condition that
  would reopen the decision — otherwise the same investigation is redone on
  every sweep.

### Every daemon must be startable without systemd

Any package that installs a systemd unit also installs an OpenRC init script of
the **same scope** — system in `/etc/init.d`, user in `/etc/user/init.d`.

The asymmetry is deliberate: the unit is gated behind `USE=systemd`, the init
script **never** is. It costs a systemd user nothing, and it is the only way to
run the daemon for someone who does not use systemd. This follows from "cover
third-party use cases" above: a systemd-only service is the maintainer's init
system mistaken for the audience's.

## Repository layout

`metadata/layout.conf` sets `profile-formats = portage-2 profile-repo-deps`, and
`profiles/eapi` is `5` (slot deps in profile files). This changes how atoms in
`profiles/package.{mask,unmask}` must be written, in opposite directions:

- Portage stamps **every** repo-level atom with the repository being processed,
  i.e. rewrites it as `<atom>::bentoo`.
- To mask something in a **master**, qualify it explicitly:
  `net-libs/nodejs:0::gentoo`. A bare atom would only ever reach this overlay's
  own ebuilds — masks flow down the masters chain, never up.
- To unmask this overlay's own ebuild against a mask inherited from a master,
  use a **bare** atom. The inherited mask lands twice (`::gentoo` and
  `::bentoo`); only the `::bentoo` copy masks our ebuild, and only a bare atom
  cancels it.

Both entries currently in the tree carry that reasoning in their comment. Read
it before editing either file.

## Verification scripts

Each one exits `1` on a gap and names what diverged. They exist because the
failure they catch is silent — it passes `pkgcheck`, merges cleanly, and only
surfaces on a user's machine.

| Script | Asserts |
|---|---|
| `check-openrc-coverage.sh [cat[/pkg]]` | every systemd unit has an OpenRC counterpart at the same scope |
| `gentoo-parity.sh [cat[/pkg]]` | names every axis on which a package diverges from its `::gentoo` counterpart; strictly read-only, writes reports under `.epic/` |
| `check-slot-naming-contract.sh` | `net-libs/nodejs` and `app-eselect/eselect-nodejs` agree on where a slot lives |
| `check-foldingathome-image.sh <ebuild>` | properties of the installed *image*, not of the ebuild text (loader fix + `RDEPEND` reconciliation) |
| `test-eselect-nodejs.sh` | slot ordering (`node9` vs `node10`) and directory replacement in the eselect module |

`check-openrc-coverage.sh` and `gentoo-parity.sh` also take `--self-test`, which
runs their assertions without touching the tree.

## Working rules

- **The checkout is not what Portage reads.** Portage reads
  `/var/db/repos/bentoo`. A fix only takes effect after commit + push +
  `emaint sync -r bentoo`.
- **This host has no `sudo`.** Validate with `emerge -pv`, or run build phases
  with a `PORTAGE_TMPDIR` of your own. A "PASS" that never merged anything is a
  false pass — say so explicitly.
- **Always pass an explicit target to `pkgdev manifest`.** Without one it
  rewrites the Manifest of the entire overlay.
- **`md5-cache` for the checkout needs `egencache
  --repositories-configuration`.** `PORTAGE_CONFIGROOT` and
  `PORTAGE_REPOSITORIES` are ignored, and it will try to delete the cache under
  `/var/db/repos/bentoo`.
- **One git worktree per concurrent session.** `bentoo overlay add` with no
  paths is `git add .`, so anything sitting in the tree when it runs gets
  committed and pushed — including another session's work in progress. Explicit
  paths are not enough; this has been observed repeatedly.
