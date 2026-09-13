# Prior art — index

Research for api-cache: a generalized, declaratively-configured successor to
ccache/sccache/buildcache/go-s3-server/Bazel-remote-cache. Written by worker
"prior-art." Every claim below is sourced in the linked file; primary sources
(project manuals, source repos, protobuf specs) were preferred over
secondhand summaries throughout.

## Files

- **`ccache.md`** — hashing modes (direct/preprocessor/depend), manifest
  format, the full sloppiness list, `base_dir`/`hash_dir`, `__DATE__`/
  `__TIME__`, PCH, stderr caching, remote storage (`file:`/`http:`/`redis:`/
  `crsh:`), zstd compression, `compiler_check`, `file_clone`/`hard_link`,
  `inode_cache`, `umask`, LRU cleanup, 6-tier config precedence, masquerade
  vs. prefix, and the compiler-flag bypass list. **License: GPL-3.0-or-later**
  (copyleft — study, don't copy).
- **`sccache.md`** — supported languages, `RUSTC_WRAPPER`, the client/daemon
  model and why Mozilla chose it, every storage backend, dist compilation
  (icecream-style + auth/encryption/sandboxing), preprocessor cache mode, Rust
  limitations (no incremental, no bin/dylib/cdylib/proc-macro). **License:
  Apache-2.0** (permissive).
- **`buildcache.md`** — the user's flagged closest prior art, given its own
  deep-dive per the coordinator's follow-up instruction. The full Lua wrapper
  contract (every function, the call order, the globals), the built-in C++
  wrappers, the capabilities system, every `BUILDCACHE_*` env var, the local
  on-disk layout, the HTTP/Redis/S3 remote wire shape, and — sourced directly
  from the project's own GitLab issue tracker — a substantiated list of real
  correctness bugs (a false cppcheck cache hit, unstable Rust program IDs,
  direct mode failing on the Linux kernel, stale-PCH linker errors). Also
  fact-checks the "buildcache is a bit slower" framing against the project's
  own LLVM benchmark (it isn't, at warm-cache steady state) and corrects the
  license from the briefed "MIT" to the actual **zlib** (verified from the
  repo's own `LICENSE` file) — both permissive, no practical difference for
  this org's screening.
- **`other-wrappers.md`** — clcache (BSD-3-Clause), cachepot (Apache-2.0,
  sccache fork), distcc (GPL-2.0) and icecream (GPL-2.0/LGPL-2.1), Bazel/Buck2
  Remote Execution API v2 (Apache-2.0 spec: `Action`/`Command`/`Directory`
  Merkle tree, `ActionCache`), bazel-remote (Apache-2.0: `/ac/`+`/cas/`, disk
  layout, multi-backend proxying), Gradle's plain-HTTP build-cache protocol,
  Nx's and Turborepo's self-hosted remote-cache protocols (the latter's
  HMAC-signed artifacts are the standout idea), Cargo's deliberate lack of a
  native remote cache, and Go's `GOCACHEPROG` JSON-Lines protocol (the
  ActionID/OutputID split — the single cleanest idea in this whole survey).
  Also notes `nocache` is an unrelated page-cache tool, not build-cache prior
  art.
- **`comparison.md`** — one table across all of the above plus go-s3-server:
  invocation model, key derivation, local storage layout, remote protocol,
  compression, multi-output handling, platform support, startup overhead,
  per-language extensibility, and configuration mechanism.
- **`lessons.md`** — what each tool got right and wrong, plus a checklist of
  concrete compiler-flag gotchas (`-fprofile-use`, `-fdebug-prefix-map`
  ordering, `-MD -MF`, `-Wp,`/`-Xpreprocessor`, `@response-files`, `-x`,
  multiple `-arch`, MSVC `/Zi` and `/showIncludes`, TTY/color-diagnostics
  detection through a wrapper, locale, umask on a multi-tier cache, hard-link
  mtime hazards, `-fmodules`) that a configurable successor needs a named,
  spec-level answer for rather than silent best-effort.

## Top 20 findings

1. Only three surveyed projects are wrapper tools in the intended sense
   (ccache, sccache, buildcache); everything else is a server protocol behind
   a different client. api-cache needs both halves; no one project models
   both.
2. **buildcache is the only wrapper tool with true no-recompile
   extensibility** — a Lua script contract (`can_handle_command`,
   `resolve_args`, `get_capabilities`, `get_program_id`,
   `get_relevant_arguments`/`_env_vars`, `preprocess_source`/
   `get_input_files` for direct mode, `get_build_files`, `run_for_miss`,
   `finalize_after_hit`) that covers a dozen+ real compilers with zero core
   changes. This is the strongest existing validation of a declarative/
   scriptable wrapper approach.
3. buildcache's own license is **zlib**, not MIT as briefed — corrected with
   the repo's actual `LICENSE` file quoted; both permissive, no practical
   difference.
4. buildcache's own GitLab issues (fetched directly) show real,
   wrapper-specific correctness bugs (cppcheck false hits, unstable Rust
   program IDs, direct mode failing on the Linux kernel, stale PCH → linker
   errors) — pluggability moved the bug surface out to many independently
   maintained wrappers instead of concentrating it in one tested core. Lesson:
   a pluggable wrapper contract needs a shared conformance test suite.
5. buildcache's own published LLVM benchmark shows it **matching or beating**
   ccache 3.7.7 at warm-cache steady state (37.3x vs 33.1x speedup) using a
   quarter of the disk space — the "a bit slower" framing is not
   substantiated by the project's own numbers, though it's the project's own
   (non-neutral) benchmark.
6. ccache (GPL-3.0) and sccache (Apache-2.0) diverge sharply on invocation
   model: ccache is fully stateless per-call; sccache runs a background daemon
   specifically to amortize remote-connection/in-memory-state cost across a
   build's many invocations. This is a first-order architecture decision
   api-cache must make deliberately, not by default.
7. GOCACHEPROG's **ActionID vs. OutputID split** — lookup key vs. content
   hash, as two explicitly named, separately typed protocol fields — is the
   cleanest single idea in this survey and is not something ccache, sccache,
   or buildcache expose explicitly (they all conflate the two into one hash).
8. REAPI's Merkle-tree input model (canonical, sorted `Directory` messages,
   digest-addressed recursively) is the only structured input representation
   here; every wrapper tool instead reduces inputs to one flat hash. If
   api-cache's spec ever needs cross-action input-sharing, REAPI is the model.
9. REAPI requires uploading the `Action` before its `ActionResult` is
   accepted — a deliberate anti-poisoning design. Turborepo independently
   solves the same class of problem with HMAC-SHA256-signed artifacts. Neither
   idea appears in any wrapper tool.
10. Every tool converges independently on two-level hex-sharded on-disk
    layout and approximate/bounded-cost LRU eviction (ccache, buildcache,
    bazel-remote, go-s3-server all do this) — clearly the right default, not
    worth re-deriving.
11. Every tool treats "cache unavailable" as "fall back to real work, never
    fail the build" (sccache's `SCCACHE_IGNORE_SERVER_IO_ERROR`, GOCACHEPROG's
    error-then-continue, ccache/buildcache's implicit fallback). This posture
    should be load-bearing in api-cache's design, not optional.
12. Multi-output handling (.o + .d + .dwo + .gcno + stderr) has three
    answers: ccache's ad hoc per-flag special-casing, buildcache's
    `get_build_files()` named map (the cleanest wrapper-tier answer), and
    REAPI's fully general per-file digest list (the cleanest protocol-tier
    answer).
13. Path/`base_dir` handling for cache portability across build directories
    has a correct, general fix (`-fdebug-prefix-map` et al.) that every tool
    still gets subtly wrong in some corner (ccache's "last flag wins" rule
    when the flag repeats; MSVC's `/Zi` embedding an absolute PDB path with
    only partial mitigation even in ccache's own newest releases).
14. `hard_link`'s documented unsafety (shared inode → shared, possibly stale
    mtime → downstream tools like `make`/Ninja fooled into skipping real work)
    recurs as an actual bug even in buildcache's own issue tracker (Ninja
    recompiling despite a "hit"). A hard-link/reflink fast path needs either a
    forced mtime bump or an explicit opt-in gate.
15. TTY/color-diagnostics auto-detection is broken by definition whenever a
    wrapper sits between the compiler and the terminal; ccache's own issue
    tracker shows this recurring across years and compiler versions. api-cache
    needs an explicit, tested TTY-passthrough story, not an assumption.
16. Config precedence models range from ccache's rigorous 6-tier stack (CLI >
    env > directory config > cache-dir config > system config > compiled
    default) to sccache/buildcache's much flatter (env > file) model — worth
    picking deliberately rather than defaulting to the simplest.
17. Compression: zstd is the converging default across ccache, REAPI/
    bazel-remote, and (as an option) buildcache; go-s3-server instead never
    compresses server-side because its client (go-toolchain) already ships
    lz4-compressed bodies — i.e. "who compresses" is itself a design choice,
    not a given.
18. Gradle's build-cache wire protocol is intentionally almost nothing (plain
    GET/PUT by opaque key) because all cache-key complexity lives client-side
    in Gradle's own task model — proof that a minimal wire protocol is a
    legitimate design point, not an unfinished one, provided the client is
    trusted with key derivation.
19. Cargo deliberately has no native remote build cache at all — every
    Rust remote-cache story (sccache, cachepot) lives entirely outside Cargo,
    wired in via `RUSTC_WRAPPER`. This mirrors api-dsl's own engine/vocabulary
    split and supports keeping api-cache's engine free of any one build
    system's opinions.
20. `nocache` (flagged in the brief) is an unrelated Linux page-cache
    (`posix_fadvise`) tool, not a build-cache — noted so nobody chases it
    further.
