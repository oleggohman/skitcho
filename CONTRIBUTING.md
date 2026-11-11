# Contributing

## Workflow

- Never commit to `main`. Work on a feature branch, ideally in its own git worktree
  (`git worktree add ../skitcho-<topic> -b <topic>`), and open a pull request.
- Use [Conventional Commits](https://www.conventionalcommits.org) (`feat:`, `fix:`, `docs:`, `test:`,
  `refactor:`, `chore:`), one logical change per commit.
- Code, comments and docs are in English.

## Build, test, lint

```bash
swift build --arch arm64
swift test --arch arm64 --no-parallel
swift format lint --strict --recursive Sources Tests
```

- Run tests serially (`--no-parallel`) and never run two test commands at the same time.
- Keep the build free of project warnings (Swift 6 strict concurrency).
- Add or update tests with every behavior change. `SkitchoCore` is AppKit-free and is the place for logic
  that can be tested without UI.

## Bundle, release and workflow checks

| Command | Purpose |
| --- | --- |
| `scripts/bundle.sh` | Assemble `build/Skitcho.app` (arm64 only, ad-hoc signed by default) |
| `scripts/test-bundle.sh` | Build the bundle and assert thin arm64 Mach-Os, plist keys, codesign, no font files, no stray hex colors |
| `scripts/test-bundle.sh --release-dry-run` | Exercise `scripts/release.sh --dry-run` with a throwaway key and a fixture feed: preflight rejections, the DMG contents (mounted read-only) and the appcast signature (no secrets, no notarization) |
| `scripts/test-workflows.sh` | Check the GitHub workflows and `scripts/*.sh` (YAML parses, no xtrace, no printed secrets, no zip packaging, pinned actions) |

Run `scripts/test-bundle.sh` before sending a change that touches packaging, resources or `Package.swift`.
Try the app by launching `build/Skitcho.app`, not the bare executable.

## Rules

- **arm64 only.** Always pass `--arch arm64`. Do not add an x86_64 or universal build, and do not add
  dependencies that force one.
- **CloudZone design tokens.** Interface colors come from `BrandColor`, annotation colors from
  `AnnotationColor`. Hex color literals are allowed only in those two token files (or on a line tagged
  `lint:allow-hex`); `scripts/test-bundle.sh` enforces this. Use system fonts only, through the
  `Typography` tokens, and never add font files.
- **No secrets in the repository.** Signing keys, certificates and API keys live in GitHub secrets only.
  See [SECURITY.md](SECURITY.md) and [docs/RELEASING.md](docs/RELEASING.md).
- Do not add a dependency without discussing it first. Sparkle is the only third-party package.

## Notes for automated agents

Sandboxed agents may need the sandbox disabled for SwiftPM builds and tests, for `scripts/bundle.sh` and
`scripts/test-bundle.sh`, and for `git commit`. Opening the app (`open`) does not work inside a sandbox, so
leave that manual check to the maintainer. Stop any process you start, and do not commit local tool
directories such as `.boost/`.
