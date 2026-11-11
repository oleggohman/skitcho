## Summary

<!-- What does this change and why? -->

## Checklist

- [ ] Commits follow [Conventional Commits](https://www.conventionalcommits.org), one logical change each
- [ ] `swift test --arch arm64 --no-parallel` passes (run serially)
- [ ] `swift format lint --strict --recursive Sources Tests` is clean
- [ ] `scripts/test-bundle.sh` passes (for packaging, resources or `Package.swift` changes)
- [ ] No secrets, keys or tokens are committed
- [ ] Docs are updated (README, CONTRIBUTING, docs/) where behavior changed
