# sccache

**License: Apache-2.0.** Permissive — safe to study and reimplement freely.
Maintained by Mozilla. Source: [mozilla/sccache](https://github.com/mozilla/sccache).

## Supported languages / compilers

C/C++ (gcc, clang, MSVC `cl.exe`), Rust (`rustc`), plain assembler, CUDA (`nvcc` and
clang-cuda), AMD ROCm `hipcc`, and Wind River's `diab` compiler. This is notably
broader than ccache's C/C++-only scope, and each frontend is its own "compiler"
implementation inside sccache's Rust codebase (a per-language argument parser that
knows how to strip the parts of a command line that don't affect the output before
hashing the rest, and how to name the actual output file(s)).

## Wrapping rustc

Two mechanisms, both standard Cargo hooks rather than anything sccache invented:

- **`RUSTC_WRAPPER=/path/to/sccache`** env var, read by cargo itself. Cargo prepends
  the wrapper to every rustc invocation it makes: `sccache rustc ...`. This is the
  common case (`cargo build` with the var set).
- **`build.rustc-wrapper`** in `~/.cargo/config.toml` — same effect, but only Cargo
  1.40+, and persistent per-project/global config instead of a shell env var.
- **`RUSTC_WORKSPACE_WRAPPER`** is the sibling knob (cargo-native, not sccache-added)
  that wraps only workspace-member crates, not their dependencies — sccache can sit
  behind either.

sccache's rustc hashing key includes: the full argument list (`-C` codegen flags,
`--emit`, `--crate-name`, etc.), relevant environment variables that rustc's own
dep-info records as inputs (dep-info's `env` field lists variable names the
compilation is known to read, each `Some(value)`/`None` — sccache folds these into
the hash so a build-script-injected env var changing invalidates the cache), and the
source files reachable from the crate root (verified via the dep-info emitted by
`--emit dep-info`, analogous to ccache's `-MD` dependency tracking). `--emit link` is
required for sccache to intercept a Rust build at all — it needs a well-defined
compiled artifact to cache.

## Known Rust-specific limitations

- Crates whose target requires the system linker directly — `bin`, `dylib`,
  `cdylib`, `proc-macro` — are **not cached**, since these produce
  environment/linker-dependent output sccache doesn't attempt to key on reliably;
  only intermediate `rlib`-style compiled units get cached.
- **Incrementally compiled crates cannot be cached** — Cargo's incremental
  compilation writes/reads its own private incremental state directory across
  invocations, which is exactly the kind of "output depends on prior local build
  state, not just declared inputs" situation ccache also refuses to cache
  (`-fprofile-generate` above is the C/C++ analogue).
- **C++20 modules**: partial support for Clang only; GCC and MSVC modules bypass the
  cache entirely, again because reliably capturing "which other module's BMI does
  this compile transitively depend on" is unsolved in sccache's model — directly
  mirrors ccache's `sloppiness=modules` being a *sloppy, not exact* escape hatch
  rather than genuine module-aware hashing.

## Client/server daemon model — and why

Unlike ccache's per-invocation model (each `ccache cc ...` call is self-contained),
sccache splits into a lightweight **client** (the process actually invoked as `cc`
via `RUSTC_WRAPPER` or a masquerade symlink) and a background **server daemon** that
holds cache state and does the real work:

- The client auto-spawns the server on first use if none is running; it can also be
  started explicitly (`sccache --start-server`) and stopped
  (`sccache --stop-server`).
- Default listen address `127.0.0.1:4226` (`SCCACHE_SERVER_PORT` to override).
- The server **auto-terminates after 10 minutes of inactivity** — it is not meant to
  be a permanent system service, just a warm process for the duration of one build
  session (or several back-to-back ones).
- **Why a daemon rather than per-invocation like ccache**: sccache's own
  justification is that a persistent server lets it keep state in memory across many
  short-lived client invocations within one build — a warm remote-storage connection
  pool, an in-memory manifest/metadata cache, in-flight request dedup across
  concurrently-compiling files — none of which a stateless per-process design can
  hold without paying reconnection/rehydration cost on every single compile
  (a build can invoke rustc/cc thousands of times). This is the single biggest
  architectural divergence from ccache and worth treating as a first-class option
  for api-cache: **daemon-with-lightweight-client** vs. **fully-stateless CLI**, each
  with different startup-overhead and statefulness tradeoffs (see comparison.md).

## Storage backends

Local disk (default, no daemon-external dependency) plus, over the network:
Amazon S3 (and S3-API-compatible services including Cloudflare R2), Google Cloud
Storage, Azure Blob Storage, Redis, Memcached, GitHub Actions cache (the GHA-specific
cache service, useful because it needs no credentials beyond what a GH Actions
runner already has), WebDAV (documented as interoperable with ccache/Bazel/Gradle
remote-cache-over-WebDAV setups), Alibaba Cloud OSS, and Tencent COS. Backends can
layer (local disk in front of a remote backend, "multi-level hierarchical caching
with automatic backfill" per Mozilla's own description) — conceptually the same
`remote_only`/`reshare` tradeoff ccache exposes, generalized to more than one
concrete backend implementation living in the same binary rather than one pluggable
protocol string.

## Distributed compilation (`sccache-dist`)

A separate opt-in mode/binary feature (`--features dist-client,dist-server`),
architecturally similar to `distcc`/`icecream` (icecc): a **scheduler** daemon
accepts compile requests from clients and hands out the address of an available
**build server**; the client then talks directly to that build server rather than
routing bytes through the scheduler (the scheduler is a rendezvous/load-balancer, not
a proxy for the actual payload). Compared to plain distcc, sccache's dist mode adds:
authentication, transport encryption, and sandboxed execution on the build server
(distcc classically just trusted the network). This is **caching plus distributed
execution** in one tool — a materially different feature from "cache the result of
a compile," and worth flagging in comparison.md/lessons.md as a scope question for
api-cache (is remote *execution*, not just remote *cache lookup*, in scope at all?).
Only Linux is supported as a build-server target; Linux/macOS/Windows are all
supported as *clients* (with macOS/Windows much less tested per Mozilla's own docs).

## "Preprocessor cache mode" (`use_preprocessor_cache_mode` / `SCCACHE_DIRECT`)

This is sccache's rough analogue of ccache's **direct mode**: instead of always
running the full preprocessor to compute the cache key (safe but slower), it can
hash based on include-file identity directly, controlled by the same
`file_stat_matches`-style knob ccache uses — when `file_stat_matches` is false
(more correct, default posture), headers are compared by hashing their contents;
when true, only the *paths* of included **system** headers are folded into the key
and their contents are trusted not to have changed (a targeted, named sloppiness
switch, not a blanket one — same design lesson as ccache's `sloppiness=` list).

## Other configuration

- `hash_working_directory` — adds cwd to the cache key, sccache's equivalent of
  ccache's `hash_dir`, same debug-info-correctness rationale.
- `SCCACHE_C_CUSTOM_CACHE_BUSTER` — an escape hatch letting a build inject an
  arbitrary extra string into every cache key, for cases sccache's own hashing can't
  observe (e.g. an external tool version not reflected in any argument).
- `SCCACHE_RECACHE` — force overwrite of a suspected-broken cached artifact instead
  of trusting the existing hit; a manual cache-poisoning escape hatch.
- `SCCACHE_IGNORE_SERVER_IO_ERROR` — falls back to running the real compiler locally,
  uncached, if the server/daemon is unreachable, rather than failing the build. This
  "cache is an optimization, never a hard dependency of build correctness" posture
  is worth carrying into api-cache's failure model explicitly.
- `SCCACHE_ERROR_LOG` / `SCCACHE_LOG` — diagnostic logging, separate from the actual
  build's stdout/stderr (parallels go-s3-server's own `Logger` install pattern for
  keeping a cache layer's diagnostics off a client's meaningful I/O streams).
- `SCCACHE_BASEDIRS` — sccache's `base_dir`-equivalent path-normalization knob for
  sharing a cache key across different absolute checkout locations.

## Sources

- [mozilla/sccache README](https://github.com/mozilla/sccache)
- [docs/Distributed.md](https://github.com/mozilla/sccache/blob/main/docs/Distributed.md),
  [docs/DistributedQuickstart.md](https://github.com/mozilla/sccache/blob/main/docs/DistributedQuickstart.md)
- [docs/Local.md](https://github.com/mozilla/sccache/blob/main/docs/Local.md)
- [Firefox build docs: sccache-dist](https://firefox-source-docs.mozilla.org/build/buildsystem/sccache-dist.html)
