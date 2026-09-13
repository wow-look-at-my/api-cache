# 12 — Decisions

Every choice the reviewer has to make, with the options, the evidence, and the plan's recommendation. Recording a decision here is what turns a **Recommended** in another file into the plan. Nothing below is decided yet.

## 1. Language and process model

Options: (a) Go wrapper, no daemon; (b) Go daemon plus Go client; (c) Go daemon plus static C client; (d) native rewrite in C, Rust or Zig.

Evidence: `06-hot-path.md`. Go floor 1,041 µs versus C 451 µs on Linux; config load was 2,269 µs and is 279 µs after cooking and the shared root; (b) measured at 1,290 µs against (a)'s ~1,337 µs; (c) at ~608 µs plus a second language and a two-implementation protocol; (d) attacks the smaller term and forfeits api-dsl; on macOS and Windows the process floor dominates the language.

**Recommended: (a)**, with the pipeline written as a function a daemon could host later.

## 2. The rule surface

Options: (a) a declarative table with steps as the escape hatch (the hybrid); (b) api-cli's passthrough-and-templates shape; (c) a pure table.

Evidence: `02-language.md`, the three written rules in `09-tool-rules.md`, `plan/research/dsl-survey/gaps.md` addendum A on what `passthroughParse` cannot express, `key-derivation-model.md` §5 on the three irregular cases.

**Recommended: (a)**, conditional on the reviewer judging the gcc, cl and rustc rules readable. If not, reopen with a concrete alternative rendering of the same three rules.

## 3. Key hash

Options: BLAKE3, SHA-256, XXH3-128.

Evidence: `03-key-derivation.md`. SHA-256 varies 6x across measured machines; XXH3 is not collision-resistant against a hostile writer on a shared remote; BLAKE3 is uniform and cryptographic. SHA-256 is unavoidable for the GOCACHEPROG output id.

**Recommended: BLAKE3 for keys, SHA-256 only for the Go output id, CRC-32C for integrity.** Library choice (`lukechampine.com/blake3` MIT or `zeebo/blake3` CC0/BSD-2) by measured throughput on the CI matrix.

## 4. Entry container

Options: binpazer; a fixed-width framed format; tar; zip.

Evidence: `04-local-store.md`, `plan/research/storage-protocol/container-format.md`. binpazer costs 1.5x to 3x a fixed table's single-member read and 60x its allocations, under 15% of the restore that follows; it brings per-block codecs, per-block CRC, a spec, and C readers. tar has no index and 6x the framing. The streaming-writer gap and the codec-instance trap are known and handled.

**Recommended: binpazer**, with pooled codecs, sized reads, and a raw-file escape for clone and link restore.

## 5. Daemon and C client, later

Options: never; when a measured condition holds.

Evidence: decision 1. The C client's ~730 µs per exec is about 7 s on a 10,000-file Linux build.

**Recommended: reopen only when** a deployment measures, with `stats --timing`, that the Go floor is the largest term of its hit path after everything else is at budget, and is Linux-heavy enough that 7 s per 10,000 files matters. binpazer's C reader would make the cooked config readable from that client.

## 6. The wrapper's HTTP layer

Options: (a) net/http in the wrapper; (b) a hand-rolled HTTP/1.1 client over `net`; (c) remote I/O only in the spool drain, performed by a companion process the wrapper spawns and detaches.

Evidence: net/http + encoding/xml + text/template init is 2.2 ms on Windows and 2.7 ms on macOS per exec, 0.22 ms on Linux. The `net` package's own init cost is not yet measured.

**Recommended: measure `net` alone first** (a phase-0 probe on the CI matrix). If `net` is cheap, (b): the protocol is GET, PUT, HEAD and two POSTs, and a minimal client is small. If `net` is also heavy, (c) for uploads and a synchronous (b)-style read path only when a remote is configured, so a local-only user never pays it.

## 7. Serialised template parse trees in the cooked form

Options: store compiled template sources and parse under the shared root at run time (~3 µs per template with the cache); store gob-encoded parse trees (saves 6 µs per template, 14x the bytes).

**Recommended: sources**, revisit only for a config an order of magnitude larger than the 30 KB sample.

## 8. Sidecar or trailer as the default

Options: sidecar cache automatically, trailer on demand; trailer only.

Evidence: `07-cook.md`. Read costs are equal; the trailer cannot go stale but forces a re-cook per config edit.

**Recommended: both, sidecar by default, `cook --into` for images and CI.**

## 9. Remote entry model

Options: (a) one container per entry with an existence probe and batch endpoints; (b) AC/CAS with per-output blobs.

Evidence: `05-remote-tier.md`, `plan/research/storage-protocol/remote-protocols.md` AC/CAS table. (b) buys dedupe of small members and partial fetch at two round trips per hit and a dangling-reference eviction problem.

**Recommended: (a).**

## 10. Known-key index

Options: go-s3-server's GBCI blob generalised; an existence probe; a Bloom filter.

Evidence: `plan/research/cache-server/index-and-prefetch.md` §5. A C++ build has no dependency-ordered critical path through the cache; a probe of 128 keys costs kilobytes.

**Recommended: the probe first; Bloom filter deferred.**

## 11. Reuse of go-s3-server

Options: (a) as-is with a key prefix; (b) extend with namespaces; (c) new server lifting the generic files.

Evidence: `plan/research/cache-server/generalization.md`. (a) silently fails on the index and pays an unscoped PUT guard; (b) is a few hundred lines but adopts the repo's history; (c) is the cleanest and lifts ~2,000 lines of infrastructure.

**Recommended: (c).**

## 12. Upload policy

Options: synchronous PUT on miss; a daemon; a spool with opportunistic drain plus `flush`.

**Recommended: the spool.** It is daemon-free, keeps the compile's latency untouched, and `write="ci-only"` makes it a no-op for read-only developers.

## 13. Default `unknown=` policy per rule

Options: `bypass` everywhere; `hash` for gcc and cl, `bypass` for rustc.

Evidence: `02-language.md`; buildcache's rationale for rustc; ccache's behaviour for gcc.

**Recommended: `hash` for gcc, clang, cl and clang-cl with lower-severity logging; `bypass` for rustc and the generic rules.** Strict mode escalates either.

## 14. Fixed sharding depth

Options: fixed two-level; ccache's dynamic 2 to 4.

Evidence: dynamic costs three stats per miss, 35 µs on NTFS.

**Recommended: fixed two-level.**

## 15. Restore method and compression per platform

Options: one global setting; per-platform negotiation.

Evidence: `04-local-store.md`. Clone is 34x faster than copy on APFS and forbids compression; compression costs +48% to +143% on the hit path by platform.

**Recommended: compress by default on every platform (zstd-1), restore by copy by default, clone and link as explicit opt-ins that disable compression.** The 34x clone on APFS is real but a Mac is where storage is scarcest and CPUs fastest, so capacity wins the default. Filesystem-specific paths follow the four rules in `04-local-store.md` (functional probe, opt-in when the format changes, fallback-and-log, CI on that filesystem), for the set actually in use: ext3/4, XFS, ZFS, APFS, NTFS, overlayfs. Follow-up measurement that would change the APFS answer: APFS transparent per-file compression (decmpfs), which reads as plain bytes and clones as compressed extents; if a Go writer can produce it, APFS gets both.

## 16. Sloppiness presets

Options: ccache's named knobs; buildcache's three tiers.

**Recommended: named knobs only**, no preset.

## 17. api-dsl proposals

Three additive changes to the shared module, none a prerequisite: `Renderer.Prepare`/`RenderPrepared` (or an internal parse cache), `apidsl.PureFuncMap()`, `Node.Pos()`. Each has a consumer-local fallback the plan uses.

**Recommended: propose all three upstream after phase 0, adopt when they land.**

## 18. Localization

**Decided by the user: out of scope.** The MSVC include-report parser matches the English prefix only, and a non-matching report declines loudly with `unrecognized_include_report`. Locale variables stay in the env allowlist because that is cheap and correct, not because localized diagnostics are supported.

## 19. Things the reviewer may want that the plan does not include

An MCP server, a GUI, nvcc, Swift, javac, link caching in shipped rules, distributed compilation, C++20 modules. Each is in `11-roadmap.md`'s deferred table with the condition that reopens it.
