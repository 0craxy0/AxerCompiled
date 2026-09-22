# Security Policy

## Supported Versions

Use this section to tell people about which versions of your project are currently being supported with security updates.

| Version | Supported |
| --- | --- |
| 1.0.x | ✅ |
| < 1.0 | ❌ |

Only the latest `1.0.x` release receives security updates. The loader pins
downloads to the current commit of the distribution repo, so running the
standard loadstring always fetches the newest supported build.

## Trust model — read this first

Axer is a loadstring framework: everything it loads executes with the full
privileges of the scripting utility that ran it. That shapes what "secure"
means here:

- **The distribution repo is the trust root.** Commit pinning and the cache
  watermark (`--axer-cache`) make caching and updates resilient, but they are
  *not* a defense against a compromised repo — code fetched from it is
  trusted code by definition. Changes to this repo are effectively releases.
- **Pin to a commit for integrity-sensitive use.** Set `BRANCH` in
  `NewMainScript.lua` to a full 40-character commit SHA instead of `'main'`
  to load exactly that build and nothing newer.
- **Executor filesystem is not yours alone.** Other scripts running in the
  same utility can read/modify the `axer/` cache and saved config profiles.
  Treat stored profiles as user preferences, not secrets.
- **Third-party game modules are privileged code.** Anything passed to
  `Axer.CreateModule` runs with the same permissions as Axer itself. Only
  register modules you have read.

## Reporting a Vulnerability

Use this section to tell people how to report a vulnerability.

**Where:** Use GitHub's private vulnerability reporting (the
**Security → Report a vulnerability** button on this repository). Please do
not open a public issue for anything security-related.

**What's in scope:**

- `NewMainScript.lua` — bootstrap, download and cache-wipe logic
- `axer/main.lua` and everything under `axer/libraries/`
- The cache watermark / update mechanism and its failure modes
- Config profile handling under `axer/profiles/`

**Out of scope:**

- Bugs in scripting utilities or executors themselves
- Roblox platform or anti-cheat behavior
- Third-party game modules not included in this repository
- Reports whose only impact requires a modified/compromised distribution repo
  (see trust model above)

**What to expect:**

- **Acknowledgment:** within 7 days of your report.
- **Status updates:** every 14 days until a decision is reached.
- **Resolution:** accepted issues get a fix (or a mitigation note) within 90
  days; declined issues get a short written rationale. Fixes ship as a new
  `1.0.x` release with the vulnerable cache entries invalidated.

Please include: affected file(s), the executor/utility you tested with, a
minimal reproduction, and your assessment of impact. If the issue only
reproduces on a specific utility, say so explicitly.
