# Evaluated and not packageable

Upstreams that were assessed for the overlay and **rejected on technical
grounds**, with the evidence that led to the decision.

## Why this file and not the other two

The register splits by *what fails*:

- `packages.toml` — an overlay package whose upstream answers a probe.
- `dead-upstreams.md` — a package whose upstream **cannot be probed**.
- this file — an upstream that probes fine and ships a real product, but whose
  artifact **cannot become an ebuild** without rewriting the vendor's software.

Without it, a rejected upstream looks identical to one nobody has looked at yet,
and the same investigation gets repeated on the next sweep.

---

## `com.nvidia.geforcenow` — GeForce NOW Linux client

**Assessed:** 2026-08-14 · **Upstream version then:** `2.0.87.130` (commit dated
2026-07-22) · **Verdict:** not packageable as a native ebuild.

NVIDIA took the Linux client out of beta in August 2026 and publishes it from
its own Flatpak repository. The `.bin` offered on the download page is not an
alternative format: it installs Flatpak, adds that remote and pulls the same
ref. There is no tarball, `.deb`, `.rpm` or AppImage.

The blocker is not the container format — it is that the application **calls
Flatpak at runtime, from inside itself**:

| Coupling | Where |
|---|---|
| Self-update on every launch: `flatpak-spawn --host flatpak update -y com.nvidia.geforcenow`, then relaunches itself (exit code 10) | `/app/bin/GeForceNOW` |
| Adds the Flathub remote to the host to obtain the gamescope Vulkan layer | `/app/bin/GeForceNOW_Downloader` |
| NVIDIA driver detection through `flatpak --gl-drivers` | `/app/bin/GeForceNOW` |
| Absolute `/app` paths — the client runs under `cd /app/cef` | `/app/bin/GeForceNOW` |
| `VK_ICD_FILENAMES` / `VK_LAYER_PATH` hardcoded to `/usr/lib/x86_64-linux-gnu/GL/vulkan/...`, a Debian-shaped runtime layout | `metadata`, `[Environment]` |
| Requires `org.freedesktop.Platform/x86_64/24.08` plus the `VulkanLayer.gamescope` extension | `metadata`, `[Application]` |

A native ebuild would therefore have to patch all three shell scripts, recreate
the `/app` prefix, synthesise the Vulkan ICD/layer paths, supply the gamescope
extension and disable the self-updater — on a proprietary payload (520 MB
installed) that NVIDIA revises every few weeks, and whose own header forbids
redistribution. Each release would break that patch set anew.

`x86_64` only, so the overlay's `~arm64` rule does not apply either: NVIDIA
publishes no aarch64 ref.

Users are served by `sys-apps/flatpak`, already in the tree:

```bash
flatpak remote-add --user --if-not-exists GeForceNOW \
  https://international.download.nvidia.com/GFNLinux/flatpak/geforcenow.flatpakrepo
flatpak install --user GeForceNOW com.nvidia.geforcenow
```

### How to re-verify

Read-only: this creates a throwaway OSTree repo and pulls ~60 KB, no install.

```bash
R=$(mktemp -d)/repo
ostree --repo="$R" init --mode=archive-z2
ostree --repo="$R" remote add --no-gpg-verify gfn \
  https://international.download.nvidia.com/GFNLinux/flatpak/geforcenow_repo

# Version, and the runtime the app is built against.
ostree --repo="$R" pull --subpath=/metadata gfn app/com.nvidia.geforcenow/x86_64/master
ostree --repo="$R" show app/com.nvidia.geforcenow/x86_64/master | grep Version:
ostree --repo="$R" cat app/com.nvidia.geforcenow/x86_64/master /metadata

# The launcher itself — this is where the Flatpak calls are.
ostree --repo="$R" pull --subpath=/files/bin gfn app/com.nvidia.geforcenow/x86_64/master
ostree --repo="$R" cat app/com.nvidia.geforcenow/x86_64/master /files/bin/GeForceNOW \
  | grep -n 'flatpak-spawn\|/app/cef'
```

Re-open the decision only if NVIDIA ships a non-Flatpak artifact, or drops the
in-app `flatpak update` call. The version alone moving is not a reason to.

---

## `www-apps/anythingllm` — AnythingLLM

**Assessed:** 2026-07-19 (story 004 Task 6) · **Re-verified:** 2026-08-16 ·
**Upstream version then:** `v1.16.0`, published 2026-08-13 · **Verdict:** not
packageable as a from-source ebuild.

Upstream is alive and its releases probe fine — this is not a dead upstream, and
it is not abandonware. What fails is the artifact. Upstream publishes desktop
installers and a container image; it publishes no source release, and it states
that the deployment an ebuild would produce is unsupported.

| Blocker | Evidence |
|---|---|
| Non-container deployment is unsupported **as policy**, not as an oversight: "Any issues experienced from bare-metal or non-containerized deployments will be **not** answered or supported" | `BARE_METAL.md`, re-read 2026-08-16 — wording unchanged |
| No source tarball in any release. `v1.16.0` ships 6 assets, all desktop installers: `.AppImage` ×2, `.exe` ×2, `.dmg` ×2 | releases API, 2026-08-16 |
| Release assets are inconsistent across versions, so no asset name can be relied on | `v1.14.0` shipped 1 asset, `v1.14.1` 6, `v1.14.2` 8, `v1.15.0` 7, `v1.16.0` 6 |
| ~2437 npm resolutions across three lockfiles | counted 2026-07-19; **not** re-counted on 2026-08-16 |
| Four prebuilt-binary fetches at install time — prisma engines, puppeteer Chromium, sharp libvips, node-canvas | counted 2026-07-19; **not** re-verified |
| Declined by nixpkgs, Flathub, Snap, Debian, Fedora and openSUSE — no distribution carries it | survey 2026-07-19 |

### How to re-verify

Read-only, three API calls, no clone:

```bash
# Is there a source release yet? Any asset that is not a desktop installer.
curl -sS -H 'User-Agent: bentoo-overlay-probe' \
  https://api.github.com/repos/Mintplex-Labs/anything-llm/releases/latest \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['tag_name']);[print(' ',a['name']) for a in d['assets']]"

# Is the asset set stable across releases, or still drifting?
curl -sS -H 'User-Agent: bentoo-overlay-probe' \
  "https://api.github.com/repos/Mintplex-Labs/anything-llm/releases?per_page=5" \
  | python3 -c "import sys,json;[print(r['tag_name'],len(r['assets'])) for r in json.load(sys.stdin)]"

# Has upstream's own stance on non-Docker deployment changed?
curl -sSL https://raw.githubusercontent.com/Mintplex-Labs/anything-llm/master/BARE_METAL.md | head -8
```

Re-open **the from-source decision** only if upstream publishes a source release
*and* drops the unsupported-deployment warning. Either one alone is not enough:
a tarball whose only supported runtime is a container still cannot become an
ebuild anybody should install.

### A separate door, deliberately left open

The rejection above is about building from source. A `-bin` package repacking
`AnythingLLMDesktop.AppImage` is a **different question**, and the evidence no
longer blocks it: the AppImage has shipped in every release since `v1.14.1`, for
both `x86_64` and `Arm64`, at a URL that is versioned by the release tag.

That is not a packaging problem — it is the policy question of whether bentoo
carries prebuilt-only desktop apps, which the overlay has already answered once
in the affirmative with `app-misc/claude-desktop-bin`. It is the same decision
story 004 Task 5 holds open for `app-misc/jan-bin`. Recorded here so the two are
settled together rather than one at a time, and so nobody reads "not packageable"
as covering a route that was never assessed.

**Note on where this record lives.** Story 004 Task 6 instructed that this go in
`packages.toml` as `enabled = false`. That instruction predates the register
split and contradicts it: `anythingllm` is not an overlay package, and
`enabled = false` is for a record that *once* worked, not for one that never
can. Filed here instead, which is the destination CLAUDE.md now prescribes for
an upstream assessed and rejected.

---

## `openhands` — OpenHands CLI (terminal agent)

**Assessed:** 2026-09-10 · **Upstream version then:** PyPI `openhands` `1.16.0`
(MIT) · **Verdict:** deferred, not rejected — the blocker is dependency volume,
not the artifact.

Three separate things carry the OpenHands name, and conflating them is the
first trap:

| Artifact | What it actually is | Language |
|---|---|---|
| `OpenHands/OpenHands` (87k stars) | Agent Canvas / webapp | **TypeScript** |
| `OpenHands/software-agent-sdk` | `openhands-sdk`, `openhands-agent-server` | Python |
| PyPI `openhands` | the terminal CLI — **this is the packageable one** | Python |

Note the org rename: `All-Hands-AI/OpenHands` now answers as
`OpenHands/OpenHands`, the same kind of move `block/goose` made to
`aaif-goose/goose`. The GitHub release assets are the Canvas desktop app
(`.deb`/`.AppImage`), **not** the agent, so packaging those would ship a
different product under the expected name.

The CLI itself is small and well-formed: MIT, an sdist on PyPI, `requires-python
== 3.12.*`. The blocker is underneath it. Resolving its dependency tree against
`::gentoo`, cutting off at **three levels and ignoring all extras**, already
leaves **65 packages missing**, and the walk was truncated there — the real
number is higher. The tree is not padding either; it includes

- `litellm`, `anthropic`, `openai`, `google-genai`, `groq`, `ollama` — a
  provider fan-out, each with its own subtree,
- `browser-use` + `browser-use-core` + `browser-use-sdk` + `cdp-use`,
- `tokenizers` (Rust, its own `CRATES` block),
- **15** `tree-sitter-*` grammar packages,
- `pyobjc`, which is macOS-only and should never be reachable on a Linux profile.

**Condition that reopens this:** any of — (a) `::gentoo` gains `litellm` and
`textual`, which together cut the largest branches; (b) upstream publishes a
self-contained binary for the CLI, the way `opencode` and `crush` do, making a
`-bin` possible; or (c) the overlay decides to take the ~65-package Python AI
stack as a project in its own right, in which case this CLI is its natural
endpoint rather than its entry point.

It is worth saying plainly that this is a volume problem, not a quality one.
Nothing here is unpackageable in principle; it is simply not one ebuild.

---

## `cline` and `kilocode` from source — the TypeScript monorepos

**Assessed:** 2026-09-10 · **Upstream versions then:** `@cline/cli` `3.0.61`
(repo tag `v4.1.17`) and `kilocode` `7.6.2` · **Verdict:** deferred. Both ship
as `-bin` in this overlay; a from-source ebuild is possible but carries a
maintenance cost out of proportion to what it buys.

Version numbering first, because it misleads: the `cline/cline` repository tags
the **VS Code extension** (`v4.1.x`), while the CLI carries its own numbering
(`3.0.61`). They live in one repo and move independently. The mapping is
recoverable — `apps/cli/package.json` at tag `v4.1.17` reads exactly `3.0.61` —
but nothing in the tag name tells you that, and a bump has to re-derive it.
Same family as the `github/copilot-cli` and `QwenLM/qwen-code` traps recorded
in `packages.toml`.

The actual blocker is the dependency graph. Both are bun workspaces:

| | build tool | lockfile | distinct npm packages |
|---|---|---|---|
| `cline` | `bun` | `bun.lock`, 932 KB | **3298** |
| `kilocode` | `bun@1.3.14` | `bun.lock`, 680 KB | **2721** |

`net-libs/bun-bin` is already in this overlay, so the toolchain is not the
problem — `bun install` reaching the network inside Portage's sandbox is. The
two ways out are both bad at this scale: enumerating some three thousand npm
tarballs in `SRC_URI` (the `dev-lang/rapydscript-ng` approach, which is fine
at its eleven), or building a consolidated `node_modules` tarball and hosting
it ourselves (the `sci-ml/lemonade` approach), which means regenerating and
re-uploading a multi-hundred-megabyte artifact on **every** bump of a package
that releases several times a week — kilocode shipped v7.6.1 and v7.6.2 hours
apart.

Set against that: `dev-util/cline-bin` and `dev-util/kilocode-bin` already
install the official upstream binaries, verified to run. A from-source build
would reproduce the same artifact at a far higher cost.

**Condition that reopens this:** upstream publishing a `bun.lock`-derived
vendor tarball as a release asset (which would remove the hosting burden
entirely), or the overlay deciding it wants a from-source path badly enough to
accept the R2 regeneration cycle — in which case the recipe is known and
written above, not research that has to be redone.
