# Security Policy

bentoo is a Gentoo overlay: it distributes *packaging* (ebuilds, patches,
init scripts, eclasses) and self-hosts some distfiles at
`distfiles.obentoo.org`. This policy covers security issues in that
packaging layer — not in the software being packaged.

## Scope

**In scope — report it here:**

- A compromised or malicious distfile, including anything served from
  `distfiles.obentoo.org`.
- A `Manifest` checksum that does not match what upstream actually
  published (possible tampering, not a routine re-roll).
- An ebuild that installs files with unsafe permissions or ownership,
  or leaks credentials/secrets into the installed image.
- An init script, systemd unit, or eclass that weakens security — e.g.
  a daemon running as root without need, predictable temp files, or
  code that executes untrusted input at build time.

**Out of scope — report it upstream:**

- Vulnerabilities in the packaged software itself belong to the
  upstream project. If upstream has already released a fix and the
  overlay still ships the vulnerable version, open a regular issue
  asking for a version bump — that request is not sensitive.

## Reporting

Use GitHub's private vulnerability reporting:
**[Security → Report a vulnerability](https://github.com/obentoo/bentoo/security/advisories/new)**.

Please do not open a public issue for anything exploitable before a fix
is available.

## Supported versions

The overlay is rolling: only the current state of the `master` branch is
supported. There are no maintained release branches.

## Response

This overlay is maintained on a best-effort basis by a single
maintainer. Expect an acknowledgment within 7 days; confirmed packaging
issues (a bad distfile, an unsafe install) are treated as the highest
priority and fixed or masked before anything else.
