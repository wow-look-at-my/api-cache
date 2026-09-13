# Fixture: github.xml

Copied from `github.com/wow-look-at-my/api-cli`, `samples/github/github.xml`.
It is a 662-line, ~30 KB declarative XML config for the GitHub REST API, and it
is the stand-in for "a real config a wrapper would load on every exec".

It is committed here because the benchmark runs on a GitHub Actions runner that
checks out only this research directory, and because pinning the exact bytes
keeps the parse numbers comparable across runs.
