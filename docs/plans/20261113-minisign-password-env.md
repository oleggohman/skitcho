# Unattended minisign signing (MINISIGN_PASSWORD)

## Overview
- Today `scripts/release.sh` signs the DMG with minisign, which asks for the key password on stdin twice, and a
  real release refuses to run without a terminal. That forces a manual step: the maintainer must type the
  password, so neither an agent nor an unattended run can release.
- Fix: an optional `MINISIGN_PASSWORD` environment variable. When set, `release.sh` feeds it to every
  `minisign -S` call through a pipe from the `printf` builtin (never argv, never disk, never printed), drops the
  terminal requirement, and signs with one attempt (a wrong password already fails the preflight). When unset,
  behaviour stays exactly as today (interactive).
- The key does NOT change: same encrypted `~/.minisign/skitcho.key`, same published `minisign.pub`, so the
  v0.2.0 signature and the documented verify command stay valid. Verified locally: a password-encrypted
  minisign key signs non-interactively with `printf '%s\n' "$PW" | minisign -S ...`, repeatedly, and a wrong
  password exits 2.
- Recommended storage: the maintainer's login Keychain (like the Sparkle key), read at release time with
  `security find-generic-password -w`; never a dotfile, never the repo.

## Context (from discovery)
- `scripts/release.sh`: minisign preflight at lines ~96-117 (tty check line ~110, nonce test signature
  lines ~112-117), final signature lines ~236-260 (`attempts` 3 on a tty, else 1), `export -n` of secrets near
  the top (line ~41). Secrets are only read from env and never printed; no xtrace.
- `scripts/test-bundle.sh --release-dry-run`: throwaway `-G -W` (unencrypted) `good`/`other` pairs in `$WORK`,
  `run_release` with `</dev/null` and `${VAR-default}` overrides, `expect_reject` (must fail before
  `bundle ok`), `.minisig` asserts, `minisign.pub` unchanged check, unsets inherited `MINISIGN_*`.
- `docs/RELEASING.md`: env table, two-prompt paragraph, preflight/sign bullets, recovery, Local dry run.
- `.gitignore` covers `*.key`; minisign 0.12 installed.

## Development Approach
- **testing approach**: Regular (code first, then dry-run assertions). Shell only; no Swift change.
- complete each task fully before the next; all tests pass before the next task; tests run serially
- **CRITICAL: every task MUST include new/updated tests**; update this plan if scope changes

## Testing Strategy
- `scripts/test-bundle.sh --release-dry-run` (sandbox disabled), `scripts/test-bundle.sh`,
  `scripts/test-workflows.sh`; `swift build/test/format lint` for regression.

## Progress Tracking
- mark `[x]` immediately; ➕ for new tasks; ⚠️ for blockers

## Solution Overview
- `MINISIGN_PASSWORD` is added to the `export -n` list so no child process (swift, codesign, notarytool,
  generate_appcast, minisign) inherits it.
- One helper, e.g. `minisign_sign <minisign -S args...>`: with `MINISIGN_PASSWORD` set it runs
  `printf '%s\n' "$MINISIGN_PASSWORD" | minisign -S "$@"`; otherwise `minisign -S "$@"` with stdin attached.
  Both the preflight nonce signature and the final DMG signature use it.
- Preflight for a real release: the `[[ -t 0 ]]` check applies only when `MINISIGN_PASSWORD` is unset; its
  message mentions `MINISIGN_PASSWORD` as the unattended alternative. The mismatch message becomes
  "... does not match <pubfile> (or wrong password / MINISIGN_PASSWORD)" while keeping the stable prefix
  `MINISIGN_SECRET_KEY does not match` that the test asserts.
- Final signature: 1 attempt when `MINISIGN_PASSWORD` is set, else today's tty rule (3 on a tty, else 1).
  The recovery message is unchanged.
- An empty `MINISIGN_PASSWORD` counts as unset (`${MINISIGN_PASSWORD:-}`).
- Docs: one-time `security add-generic-password -a skitcho -s skitcho-minisign -w` (prompts for the
  password; nothing on argv); the release subshell exports
  `MINISIGN_PASSWORD="$(security find-generic-password -a skitcho -s skitcho-minisign -w)"`. The first read may
  show a Keychain access dialog; "Always Allow" makes later runs unattended.

## Implementation Steps

### Task 1: MINISIGN_PASSWORD in release.sh, covered by the dry run

**Files:**
- Modify: `scripts/release.sh`
- Modify: `scripts/test-bundle.sh`

- [x] release.sh: header env docs gain `MINISIGN_PASSWORD` (optional; unattended signing); add it to the
      `export -n` list
- [x] release.sh: helper that pipes `MINISIGN_PASSWORD` via `printf` into `minisign -S` when set, else keeps
      stdin attached; use it for the preflight nonce signature and the final DMG signature
- [x] release.sh: real-release tty check only when the password is unset (message names `MINISIGN_PASSWORD`);
      final signature attempts = 1 when the password is set; mismatch message mentions the variable but keeps
      the prefix `MINISIGN_SECRET_KEY does not match`
- [x] test-bundle.sh: also generate an encrypted throwaway pair in `$WORK`
      (`printf 'pw\npw\n' | minisign -G -p "$WORK/enc.pub" -s "$WORK/enc.key"`, test-only password), and let
      `run_release` pass `MINISIGN_PASSWORD` through its `${VAR-default}` override pattern (default unset);
      unset any inherited `MINISIGN_PASSWORD` at the start
- [x] test-bundle.sh: new `expect_reject` case — encrypted key with a wrong `MINISIGN_PASSWORD` is rejected
      with `MINISIGN_SECRET_KEY does not match` before `bundle ok`
- [x] test-bundle.sh: the full successful dry run uses the encrypted key + correct `MINISIGN_PASSWORD` and
      `enc.pub` (the unattended path), with the existing `.minisig` asserts against `enc.pub` (trusted comment
      exact, other key rejected); assert the test password string never appears in `$WORK/release.log`
- [x] run `scripts/test-bundle.sh --release-dry-run`, then `scripts/test-bundle.sh` — must pass

Implementation notes (from plan review, approved):
- use a distinctive test password, e.g. `skitcho-dryrun-$RANDOM-secret` (not `pw`); assert with `grep -qF` that
  neither the correct password (full run) nor the wrong one (reject case) appears in that run's log
- update every stale release.sh comment: header lines ~11-13 ("requires stdin to be a terminal"), ~97, ~109
  (piped password note), ~237 ("up to 3 attempts on a terminal")
- one-line comment at the helper: `MINISIGN_PASSWORD` is meant for the encrypted key (with an unencrypted key
  minisign never reads stdin and `printf` can hit SIGPIPE under pipefail); no extra code
- the unset (interactive) path keeps coverage only through the preflight reject case; that is accepted (the
  branch is just `minisign -S "$@"`); do not add a second full build
- the real-release tty gate cannot run in the dry run (no SIGN_IDENTITY); verified by review and by the next
  real release (0.2.1)
- do not add a `set +x` guard; the header's "Do not add xtrace" convention covers it

### Task 2: Document unattended signing

**Files:**
- Modify: `docs/RELEASING.md`

- [ ] one-time setup step 4: store the minisign password in the login Keychain
      (`security add-generic-password -a skitcho -s skitcho-minisign -w`; add `-U` to update it after a password
      change); "if macOS asks for Keychain access, choose Always Allow" (usually no dialog: `security` created
      the item)
- [ ] step 3 subshell: set the password LAST, right before `scripts/release.sh`, so earlier commands do not
      inherit it, and fail on a missing item:
      `MINISIGN_PASSWORD="$(security find-generic-password -a skitcho -s skitcho-minisign -w)" || exit 1;
      export MINISIGN_PASSWORD`
- [ ] step 3: env table gains `MINISIGN_PASSWORD`; the subshell example exports it from the Keychain; the
      two-prompt paragraph says prompts happen only when `MINISIGN_PASSWORD` is unset; preflight bullet and
      "stdin is not a terminal" text updated; final-signature bullet notes one attempt with the variable
- [ ] "Local dry run" mentions the encrypted throwaway key, the wrong-password reject case and the
      no-leak assertion
- [ ] check every name/command in the docs against the scripts; `scripts/test-workflows.sh` passes

### Task 3: Verify acceptance criteria
- [ ] `scripts/test-bundle.sh --release-dry-run`, `scripts/test-bundle.sh`, `scripts/test-workflows.sh` pass
- [ ] `swift build --arch arm64`, `swift test --arch arm64 --no-parallel`,
      `swift format lint --strict --recursive Sources Tests` pass (regression only)
- [ ] no password, key contents or Keychain secret anywhere in the diff or test logs

### Task 4: [Final] Update documentation
- [ ] CLAUDE.md only if a new rule emerged
- [ ] move this plan to `docs/plans/completed/`

## Post-Completion
- the maintainer stores the password in the Keychain once (interactive, Task 2 command)
- after merge to main and push: Trivy (`trivy fs --scanners vuln,secret,misconfig .`)
- next real release (0.2.1) can then run end to end without typing the password
