# Minisign-signed releases (OpenSSF Scorecard Signed-Releases)

## Overview
- OpenSSF Scorecard gives Skitcho 0/10 on **Signed-Releases**: the v0.1.1 release has only
  `Skitcho-0.1.1.dmg` and `appcast.xml`. Scorecard ignores Apple codesigning and notarization; it only looks
  at release asset names in the last 5 releases (`.asc`, `.minisig`, `.sig`, `.sign`, `.sigstore`,
  `.sigstore.json`; `.intoto.jsonl` for provenance). Signatures alone score 8/10; 10 also needs provenance
  (out of scope).
- Fix: every release from now on also ships `Skitcho-X.Y.Z.dmg.minisig`, a minisign signature made locally on
  the maintainer's Mac with a password-protected key. The public key is committed (`minisign.pub`) and
  published in SECURITY.md and README so users can verify downloads independently of GitHub.
- ⚠️ v0.1.1 cannot be back-filled: the repository has immutable releases enabled
  (`gh release view v0.1.1 --json isImmutable` → `true`; `immutable-releases` → `enabled: true`), so no asset
  can be added. The score rises only as signed releases are published (roughly 4/10 with v0.1.2 signed next to
  unsigned v0.1.1, 8/10 once all of the last 5 are signed, or earlier as the ratio grows). Do not delete or
  recreate v0.1.1 (tag ruleset and immutability forbid it).
- Out of scope: branch protection, CII badge, code review, fuzzing, SLSA provenance.

## Context (from discovery)
- `scripts/release.sh`: local-only release (preflight → bundle → DMG → codesign/notarize/staple → appcast);
  secrets only from env, `export -n` keeps them from child processes; `--dry-run` signs ad-hoc.
- `scripts/test-bundle.sh --release-dry-run`: hermetic dry run with throwaway Sparkle keys, fixture appcast,
  `expect_reject` helper asserting preflight failures happen before `bundle ok`, and a strict allowlist of
  files in `dist/` (`Skitcho-9.9.9.dmg`, `appcast.xml`). Its cwd is `$ROOT`.
- `docs/RELEASING.md`: one-time setup (Developer ID, ASC key, Sparkle key), release steps ending in
  `gh release create vX.Y.Z dist/Skitcho-X.Y.Z.dmg dist/appcast.xml ...`, "Verifying a release",
  "Local dry run".
- `SECURITY.md` "Update signing model"; `README.md` "Install" and "Security". `.gitignore` already has `*.key`.
- minisign 0.12 installed via Homebrew (`-W` needs ≥ 0.10). Verified locally: `-G -W -p X -s Y` writes an
  unencrypted pair; signing with it needs no password; `-V` with a different public key fails with a key id
  mismatch.

## Development Approach
- **testing approach**: Regular (code first, then tests). The "tests" for shell release code are the
  assertions in `scripts/test-bundle.sh --release-dry-run`; there is no Swift code change.
- complete each task fully before moving to the next; small, focused changes
- **CRITICAL: every task MUST include new/updated tests** for code changes in that task
- **CRITICAL: all tests must pass before starting next task**
- **CRITICAL: update this plan file when scope changes during implementation**
- run tests serially (never in parallel), one test command at a time

## Testing Strategy
- **dry-run tests**: `scripts/test-bundle.sh --release-dry-run` (needs sandbox disabled) generates throwaway
  unencrypted minisign keys in `$WORK` with explicit `-p`/`-s` paths, never touching the committed
  `minisign.pub` or `~/.minisign`, runs every minisign/release call with `</dev/null` so it can never block
  on a password prompt, and asserts preflight rejections plus a verifiable `.minisig` in `dist/`.
- **regression**: `scripts/test-bundle.sh`, `scripts/test-workflows.sh`, `swift build --arch arm64`,
  `swift test --arch arm64 --no-parallel`, `swift format lint --strict --recursive Sources Tests`,
  `shellcheck` on the changed scripts if installed.
- no UI change, no e2e tests.

## Progress Tracking
- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix; blockers with ⚠️ prefix
- keep plan in sync with actual work done

## Solution Overview
- **Tool**: minisign (Ed25519, tiny, Scorecard-recognized, no identity published to a transparency log).
- **Keys**: secret key at `~/.minisign/skitcho.key` (outside the repo, password-protected, mode 600, backed up
  privately like the Sparkle key); public key committed as `minisign.pub` at the repository root.
- **release.sh inputs** (new):
  - `MINISIGN_SECRET_KEY`: path of the secret key file (required, also in `--dry-run`).
  - `MINISIGN_PUBLIC_KEY_FILE`: path of the public key file, default `$ROOT/minisign.pub` (tests override).
- **Password model**: minisign prints the prompt on stderr and reads the password from **stdin** (echo off).
  release.sh must leave stdin attached to the minisign `-S` calls (no pipes, here-strings or `</dev/null`
  there) and must be run from an interactive terminal for a real release.
- **Preflight** (before the appcast fetch, build or Apple, so a wrong key or password never wastes a
  notarization): `minisign` on PATH (hint `brew install minisign`); `MINISIGN_SECRET_KEY` set and a readable
  file; public key file present; a test signature of a nonce file in `$WORK` verifies (`-V -q`) with the
  public key, else "MINISIGN_SECRET_KEY does not match <pubfile> (or wrong password)". The secret key's key id
  is encrypted, so the test signature is the only pre-build check. First password prompt.
- **Signing**: last step, after `generate_appcast` (the DMG is final: stapled and in the appcast; the appcast
  tool never sees the `.minisig`). `minisign -S -s KEY -m DMG -x DMG.minisig -t "Skitcho X.Y.Z
  Skitcho-X.Y.Z.dmg"`, then `minisign -V -q -p PUB -m DMG -x SIG` must pass. Second password prompt, after
  notarization. Up to 3 attempts when stdin is a terminal (`[[ -t 0 ]]`), one otherwise. On final failure the
  error names the manual recovery: `dist/` already holds the final DMG and appcast; sign by hand with the
  printed `minisign -S ... -t ...` and `-V` commands, then publish — never re-run release.sh for the same
  version (it would rebuild and re-notarize a different DMG).
- **Publishing**: `gh release create` gets the extra asset `dist/Skitcho-X.Y.Z.dmg.minisig`. With immutable
  releases on, `gh release create` with assets still works (gh uploads to a draft, then publishes); all three
  assets must be passed in that one command because nothing can be added afterwards.

## Technical Details
- Trusted comment format: `Skitcho <version> Skitcho-<version>.dmg`. `minisign -V ... -Q` prints only it.
- User verification command (README, SECURITY, RELEASING — same form everywhere):
  `minisign -Vm Skitcho-X.Y.Z.dmg -P <public key string>` (minisign ≥ 0.8).
- The secret key path is not a secret value, but `release.sh` never prints key contents and keeps no xtrace.

## What Goes Where
- **Implementation Steps**: script, tests, docs, committed public key.
- **Post-Completion**: Trivy after merge, Scorecard re-check after the next signed release.

## Implementation Steps

### Task 1: Sign the DMG with minisign in release.sh, covered by the dry run

**Files:**
- Modify: `scripts/release.sh`
- Modify: `scripts/test-bundle.sh`

- [x] prerequisite: `brew install minisign` (0.12 installed, `minisign -v` → `minisign 0.12`)
- [x] release.sh: add `MINISIGN_SECRET_KEY` / `MINISIGN_PUBLIC_KEY_FILE` to the header env docs
- [x] release.sh preflight (before the appcast fetch): minisign present, secret key set and readable, public
      key file present, nonce test-sign + `-V -q` verify with the custom mismatch message
- [x] release.sh after `generate_appcast`: sign `$DMG` to `$DMG.minisig` with the trusted comment (stdin left
      attached; up to 3 attempts on a tty), verify with the public key, failure message with the manual
      recovery commands; final `release ok` line mentions the signature
- [x] keep existing guarantees: no secret printed, no xtrace, `set -euo pipefail`
- [x] test-bundle.sh `--release-dry-run`: require minisign (brew hint); generate
      `minisign -G -W -p "$WORK/good.pub" -s "$WORK/good.key" </dev/null` and the same for an `other` pair
- [x] test-bundle.sh: `run_release` passes `MINISIGN_SECRET_KEY` / `MINISIGN_PUBLIC_KEY_FILE` (defaults: the
      good pair; overridable per call via env prefix like `FIRST_RELEASE`) and runs with `</dev/null`
- [x] test-bundle.sh: `expect_reject` cases — unset `MINISIGN_SECRET_KEY`, missing key file, secret key not
      matching the public key — each rejected before `bundle ok`
- [x] test-bundle.sh: allow `Skitcho-9.9.9.dmg.minisig` in the `dist/` allowlist; assert `minisign -V` passes
      with the good public key, `-Q` output equals exactly `Skitcho 9.9.9 Skitcho-9.9.9.dmg`, and verification
      fails with the other public key; assert the committed `minisign.pub` (if present) is unchanged
- [x] run `scripts/test-bundle.sh --release-dry-run`, then `scripts/test-bundle.sh` — must pass

Implementation notes (from plan review):
- retry loop must survive `set -e`: `for i in 1 2 3; do if minisign -S ...; then ok=1; break; fi; done`
  (break after one attempt when stdin is not a tty); minisign rewrites a partial `$DMG.minisig` on retry
- `minisign.pub` unchanged check: checksum before the dry run, compare after; tolerate the file being absent
- preflight order: minisign checks after the Sparkle key checks, before `swift package resolve` / feed fetch
- `expect_reject` for the mismatch matches the stable text `does not match`

### Task 2: Commit the real public key

**Files:**
- Create: `minisign.pub`

- [x] the maintainer runs in the worktree root (interactive; asks for the password twice, writes the secret key
      with mode 0600):
      `! mkdir -p ~/.minisign && chmod 700 ~/.minisign && minisign -G -p minisign.pub -s ~/.minisign/skitcho.key`
- [x] check `minisign.pub` holds only the two public lines and the secret key is outside the repo, mode 600
      (`*.key` is already in `.gitignore`); `git status` shows only `minisign.pub`
- [x] maintainer signs a scratch file with the real key and it verifies with `minisign.pub` (pending maintainer:
      needs the key password; orchestrator confirms)

### Task 3: Document signing for maintainers and users

**Files:**
- Modify: `docs/RELEASING.md`
- Modify: `SECURITY.md`
- Modify: `README.md`

- [ ] RELEASING.md one-time setup step 4: install minisign, generate the key (exact command from Task 2),
      back up the secret key privately, `minisign.pub` is committed
- [ ] RELEASING.md step 3: env table gains `MINISIGN_SECRET_KEY`; bullets for the preflight test signature and
      the final signature; the two password prompts (stdin, interactive terminal, second one after
      notarization — stay at the terminal); "Writes ..." bullet lists the `.minisig`; recovery when the final
      signature fails (manual sign of `dist/`, never re-run for the same version)
- [ ] RELEASING.md step 5 and the first-release block: `gh release create` includes
      `dist/Skitcho-X.Y.Z.dmg.minisig`; note that immutable releases forbid adding assets later
- [ ] RELEASING.md "Verifying a release" adds the minisign check; "Local dry run" mentions the throwaway
      minisign keys, the `.minisig` checks, and that minisign is required
- [ ] SECURITY.md "Update signing model": release DMGs from 0.1.2 on carry a minisign signature; public key
      string and verify command; README "Install": optional verification step with the same command
- [ ] check every command in the docs against the scripts (env names, paths, file names)

### Task 4: Verify acceptance criteria
- [ ] `scripts/test-bundle.sh --release-dry-run` passes (shows the `.minisig` checks)
- [ ] `scripts/test-bundle.sh`, `scripts/test-workflows.sh` pass
- [ ] `swift build --arch arm64`, `swift test --arch arm64 --no-parallel`,
      `swift format lint --strict --recursive Sources Tests` pass (no Swift change expected; regression only)
- [ ] `shellcheck scripts/release.sh scripts/test-bundle.sh` if shellcheck is installed
- [ ] no secret key or key contents anywhere in the diff

### Task 5: [Final] Update documentation
- [ ] update CLAUDE.md only if a new rule emerged (e.g. minisign required for the release dry run)
- [ ] move this plan to `docs/plans/completed/`

## Post-Completion
*Items requiring manual intervention or external systems*

- after the merge to main and push: run Trivy (`trivy fs --scanners vuln,secret,misconfig .`)
- the Scorecard score only moves with the next published release (v0.1.2, signed); re-check
  `api.securityscorecards.dev` after the following weekly scan
- keep a private backup of `~/.minisign/skitcho.key`; losing it means rotating the published public key
