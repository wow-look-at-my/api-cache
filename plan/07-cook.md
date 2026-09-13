# 07 — Cook

The `cook` action turns a set of rule files into the binary form the wrapper reads, and the two ways that form reaches the wrapper: a sidecar cache that is automatic, and a trailer appended to the binary that is explicit. Both carry the identical bytes. Evidence: `plan/research/startup-perf/results/config-load.md`, `results/trailer.md`, `options.md`.

## Why a cooked form

The wrapper must not parse XML or build template function maps per exec (`06-hot-path.md`). The cook does that work once and emits a container the wrapper decodes in microseconds: decoding the compiled-template form of the 30 KB sample measured 1.7 µs, reading a 3 KiB trailer through binpazer 17 µs, and a 10 MiB trailer does not slow `execve` because bytes past the last ELF segment are never paged in.

## What the cook produces

A binpazer container (`refs/bin-file-fmt`, MIT) with these blocks:

| Block | Content |
|---|---|
| `Meta` | engine version, hash-format version, cook time, the hash of every source document and of the engine binary |
| `Strings` | one string table, so every rule refers to strings by index |
| `Rules` | the merged `<tool>` structs after overlays: match regexes (compiled at load, stored as source), syntax and dialect ids, the args table as `(match-index, value-id, role-set, mode-set, gate-id, when-template-index)` rows, the env lists, the identity policy, the discover and outputs declarations, the sloppiness set, the verdict conditions |
| `Templates` | every template's compiled source (the api-dsl compiled form, a string) in one array, de-duplicated; only templates that contain `{{` are stored, literal strings are inlined into `Rules` |
| `Store`, `Remotes` | the resolved settings |
| `Provenance` | for `explain`: which document each row and setting came from, with the document's position path |

The cook validates everything `02-language.md` lists before writing, so a cooked file is by construction a valid config. Templates that produce identity or key fragments are rendered once against a fixture context during cook and rejected on `<no value>`.

Binpazer over a hand-rolled footer costs ~2 µs and 1.1% size, and buys the block index (the wrapper on a hit reads `Meta`, `Rules` and the templates it needs, not the whole container), a spec, a C reader for a possible native client, and skippable unknown blocks for forward compatibility. `encoding/gob` is ruled out: 344 µs against 22 µs for a flat format.

**Template parse at run time.** The cooked form removes the XML but not `text/template.Parse`. Two engine rules make that cheap: one shared root template carries the func map, and associated templates are parsed under it (76 templates: 3,417 µs → 276 µs); and a prepared-template cache keyed by source means a rule's handful of run-time templates cost ~3 µs each. Serialising parse trees (verified workable via gob and `AddParseTree`) saves the 6 µs parse at 14x the bytes and is not worth it; decision 7 in `12-decisions.md` keeps it open only for a config an order of magnitude larger than the sample.

## The sidecar: automatic

On every exec the wrapper computes the config set it would load (`08-cli-and-ops.md`, "Config discovery"): the shipped rules directory, the user overlay, the project overlay, the environment overrides. It reads a small index file in the cache dir, `cooked/index`, that maps a hash of (the document paths, their sizes and mtimes, the engine version) to a cooked file. On a match it opens that cooked file directly; the check is a handful of stats. On a mismatch it cooks, writes the container to a temp file, renames it into `cooked/<hash>.bp`, and updates the index. A stale sidecar can never be read: its name is its key.

Cost on the hot path: the stats plus a 17 µs read. The cook itself runs once per config edit, taking the ~2.3 ms naive load plus validation, which nobody notices.

## The trailer: explicit

`api-cache cook --into <binary>` appends the same container to a copy of the wrapper binary, followed by an 8-byte container length and the binpazer footer, so the wrapper finds it by reading its own last 16 bytes (`os.Executable`, one open, two `ReadAt`s). A trailer-bearing binary ignores the search order and the sidecar entirely: its config is its binary, which is what a CI image, a toolchain package or a masquerade directory wants. `--config` and environment overrides are rejected at startup with a message naming the trailer's source documents, so a cooked binary cannot be silently reconfigured. `api-cache cook --strip` produces a plain binary again; `api-cache docs config` prints the trailer's source.

The trailer and the sidecar are the same bytes, so the sidecar path is the trailer path with one indirection, and there is one reader.

## What the cook does not do

- It does not prove the config is correct against the tools it names. `api-cache check` (`08-cli-and-ops.md`) does that: it resolves every `<tool>`, runs each identity query, and reports.
- It does not precompute keys or tool identities; those depend on the machine.
- It does not embed the rule XML for pretty-printing. `Provenance` carries positions and document hashes; the documents themselves stay where they are, and the trailer form stores them in a `Sources` block so `docs config` can print them.

## Rule directory layout

```
<install>/rules/          shipped: gcc.xml clang.xml cl.xml clang-cl.xml rustc.xml generic.xml
~/.config/api-cache/      user: cache.xml plus any *.xml overlay
<project>/.api-cache.xml  project overlay, found by upward search
```

The shipped rules are also embedded in the binary with `go:embed` as the fallback when no rules directory exists, so a bare binary works. A cooked binary needs no rules directory at all.
