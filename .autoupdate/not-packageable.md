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
