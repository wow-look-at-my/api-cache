# Lessons for a generalized, configurable successor

What each tool got right, what it got wrong, and the concrete gotchas a
configurable "api-cache" must have an explicit, named answer for — because
every one of these bit at least one real project.

## What each tool got right

- **ccache**: named, individually-toggleable sloppiness flags rather than one
  blanket "unsafe mode." A three-tier hashing strategy (direct/preprocessor/
  depend) that trades precision for speed, chosen automatically with graceful
  fallback rather than forcing the user to pick per-file. An explicit,
  documented bypass list for "this invocation cannot be cached" rather than
  best-effort guessing. Statistics broken out by category (hit, miss-by-reason)
  rather than one aggregate number.
- **sccache**: the daemon model amortizes remote-connection and in-memory-state
  cost across a whole build's worth of invocations instead of paying it per
  compile — a real architectural win when a build issues thousands of
  compiler calls. "Cache is best-effort" as an explicit, named config
  (`SCCACHE_IGNORE_SERVER_IO_ERROR`) rather than an implicit hope. Broadest
  storage-backend menu of any tool here, because backends are compiled-in
  Rust modules behind one trait, not one hand-rolled protocol string.
- **buildcache**: the *only* wrapper tool with true no-recompile
  extensibility (Lua contract) — this is the single strongest piece of prior
  art for api-cache's own declarative-config ambitions, because it proves a
  scripted/declarative wrapper contract can cover a dozen+ real compilers
  (gcc, clang-cl, msvc, ghs, ti-arm-cgt/arp32/c6x/c7x, qcc, rust, cppcheck,
  ccc-analyzer) without ever touching the engine. `finalize_after_hit()` — the
  recognition that a cache hit sometimes still needs *some* real work done
  (regenerating a `.d` file so downstream tools aren't confused) — is a subtle,
  important idea nothing else in this survey names explicitly. Preset accuracy
  tiers (`STRICT`/`DEFAULT`/`SLOPPY`) are easier to explain to a user than
  ccache's ~14-flag sloppiness list, at the cost of granularity.
- **REAPI**: the Merkle-tree input model and the explicit `Digest`
  content-address for every blob, including stdout/stderr, giving one uniform
  answer to "cache a big output, a small output, or console text" instead of
  three different mechanisms. `do_not_cache` and `salt` as first-class protocol
  fields instead of environment-variable conventions. Requiring the `Action`
  itself to be uploaded before its `ActionResult` is accepted, closing a
  cache-poisoning gap none of the wrapper tools even discuss.
- **Turborepo**: HMAC-signed artifacts is the one genuinely novel answer in
  this survey to "how does a client know a remote cache entry wasn't
  tampered with," and it costs almost nothing to implement.
- **GOCACHEPROG**: separating ActionID (lookup key) from OutputID (content
  hash) as two distinct, explicitly named protocol fields, rather than one
  opaque hash doing double duty. A protocol simple enough (JSON Lines, three
  verbs) that a from-scratch third-party implementation (this org's own
  go-s3-server + cacheclient) is a reasonable undertaking rather than a
  multi-month integration.
- **Gradle**: proof that a remote-cache wire protocol can be almost nothing
  (GET/PUT by opaque key) when all the hard problems are pushed to the
  client's own key-derivation logic — a legitimate simplicity choice, not a
  missing feature, as long as the client side is trusted to get key derivation
  right.
- **go-s3-server** (this org's own): a precomputed binary key index
  (`/_index`, GBCI v1) instead of per-key existence probing, and tar-bundled
  batch transfer (`/_batch/get`/`/_batch/put`) instead of one HTTP request per
  object, are direct, working answers to the exact scaling wall buildcache's
  own HTTP backend hits (one request per stored file — see buildcache.md).
  Self-healing repair of a recoverable corruption (missing `outputid` xattr)
  in place, rather than treating it as a silent permanent miss, is a pattern
  worth generalizing: **a broken cache entry with a knowable fix should be
  repaired, not just evicted** — none of ccache/sccache/buildcache do this;
  they simply miss and recompute.

## What each tool got wrong (concretely, with evidence)

- **ccache**'s masquerade model creates PATH-ordering fragility, and its
  three-tier hashing fallback is a single global mode, not a per-action-kind
  choice, even though "does this compiler emit depend info" is genuinely a
  per-tool fact. `hard_link` is documented as flatly unsafe yet still exists
  as a config option a user can enable without any additional guard.
- **sccache**'s daemon auto-spawns and auto-terminates on a fixed 10-minute
  idle timer — a build that pauses (a human steps away mid-investigation) for
  11 minutes silently pays a full respawn on the next compile, and nothing in
  the docs surfaces that timer as a build-observable event. Rust's own
  incremental-compilation and dylib/cdylib/proc-macro outputs are simply
  unsupported, not gracefully degraded to "cached but conservatively" — a hard
  scope wall a user only discovers by noticing certain crates never speed up.
- **buildcache**'s per-wrapper extensibility is also its biggest weakness in
  practice: the GitLab issue tracker (fetched directly, `buildcache.md`) shows
  real correctness bugs *specific to individual wrappers* (a false cache hit
  from cppcheck's inline-suppression comments not affecting the hash; a Rust
  `get_program_id()` that wasn't stable; direct mode failing outright on a
  Linux-kernel-scale build; the GCC wrapper mishandling `-save-temps` and
  compact `-Ipath`-joined arguments) that a hard-coded, single-implementation
  tool would have caught in one shared test suite. Pluggability moves the
  surface area for bugs out to N independently-maintained wrapper
  implementations instead of concentrating it in one. **The lesson isn't "don't
  do pluggable wrappers," it's "a pluggable wrapper contract needs a shared,
  wrapper-agnostic conformance test suite the engine runs against every
  wrapper" — something buildcache's own docs never mention having.**
- **REAPI/bazel-remote** solves the hard input-modeling problem well but
  offers almost no config-time correctness-relaxation vocabulary (nothing like
  `sloppiness=`) — an implementer wanting "ignore include mtimes" has to build
  that into their own client's Action-construction logic from scratch, because
  the protocol itself has no opinion.
- **Gradle's protocol** pushes *all* correctness risk to the client silently;
  the wire protocol cannot express "this entry might be stale for reason X" at
  all, so a build-cache correctness bug shows up as a wrong build with zero
  protocol-level diagnostic trail.
- **Nx/Turborepo** both assume a JS/Node-shaped monorepo task model
  (declared task inputs, one task = one cacheable unit) baked deeply into how
  the client computes its hash; neither protocol is reusable by a
  fundamentally different build shape (a single compiler invocation, say)
  without reimplementing that whole task-hashing layer client-side first.

## Concrete gotchas a configurable successor must have a named answer for

Each of these broke a real tool for a real user; api-cache's spec language
needs an explicit story for each, not "the user will figure it out."

- **`-fprofile-use` / `-fprofile-generate` (PGO)**: output depends on runtime
  profile data written as a side effect of *running* the produced binary, not
  on any input the compiler invocation itself exposes. ccache disables caching
  outright for `-fprofile-generate`; a generalized cache needs the same
  "provably uncacheable, refuse rather than guess" posture, expressed as a
  declarative predicate over the command line (see ccache.md's bypass list).
- **`-fdebug-prefix-map=<old>=<new>` (and `-ffile-prefix-map`,
  `-fmacro-prefix-map`, `-fprofile-prefix-map`)**: rewrites embedded paths in
  debug info / macros / profile data at compile time — the *correct*, portable
  fix for the `hash_dir`/`base_dir` problem (share a cache across build
  directories without lying about `cwd` via a hard link or a `hash_dir=false`
  opt-out). ccache's own gotcha: it only special-cases the CWD-not-in-hash
  behavior when the **last** `-fdebug-prefix-map` argument (of possibly
  several) matches the current directory — order-sensitive, undocumented to a
  casual user, and a real source of "why did this not hit" bug reports.
  **Lesson: a path-rewrite flag with multiple occurrences needs a
  clearly-specified "which one wins" rule, stated in the spec, not inferred
  from source.**
- **`-MD -MF <path>` (and `-MMD`)**: dependency-file generation as a
  side-channel output the compiler produces *in addition to* the object file —
  exactly the "multi-output" problem (comparison.md) every tool needs a named
  answer for (ccache hashes/tracks it for depend mode; buildcache's
  `get_build_files()` map is the cleanest generalized answer; REAPI's
  `output_paths` list is the protocol-level version).
- **`-Wp,<opt>` / `-Xpreprocessor <opt>`**: hands raw, arbitrary flags straight
  to the preprocessor, bypassing the compiler driver's normal flag parsing.
  ccache can't interpret most of these safely and refuses to cache such
  invocations at all (excepting a small allowlist: `-Wp,-MD,<path>`,
  `-Wp,-MMD,<path>`, `-Wp,-D<define>`, which it does understand). **Lesson: an
  "arbitrary opaque passthrough" flag category needs to be either a named,
  finite allowlist the spec understands, or an automatic bypass — never a
  best-effort parse.**
- **`@response-file` arguments**: an invocation's real argument list lives in
  an external file, not argv itself — MSVC and increasingly GCC/Clang support
  this for command-line-length limits. ccache had (and fixed) real bugs
  specifically around response-file path handling on Windows (space-containing
  paths) and needed a dedicated `response_file_format` config once fixed.
  **Lesson: response-file expansion must happen before hashing, must be
  platform-path-aware, and needs its own test coverage — it is not "just
  another argument."**
- **`-x <language>`**: overrides the language ccache/buildcache would
  otherwise infer from the file extension (compiling a `.c` file as C++, or
  stdin as a named language). Any wrapper contract that infers "which wrapper
  handles this" from file extension or program name (as buildcache's
  first-line regex match does) needs `-x`-style explicit-override handling as
  a first-class case, not an edge case discovered later.
- **`-arch <arch>` appearing multiple times** (Apple's multi-architecture
  "fat binary" compiles, `-arch x86_64 -arch arm64` in one invocation):
  produces multiple outputs from one command line, which breaks the
  "one invocation, one cacheable output" assumption ccache's own "multiple
  source files disables caching" bypass rule is built on. **Lesson: a
  multi-output-from-one-flag pattern (not just multi-output-from-multiple-
  source-files) needs its own named handling, or an explicit bypass.**
- **MSVC `/Zi`** (separate PDB debug info): embeds the **full absolute path**
  to the PDB file into the compiled object, which is exactly the
  `hash_dir`/`base_dir` problem again but MSVC-specific and, per ccache's own
  open issue history, still only partially solved even after dedicated work —
  `/Z7` (debug info inline in the .obj, no separate PDB) sidesteps the
  problem entirely and is the usual recommended workaround. **Lesson:
  "recommend a compiler flag that avoids the problem" is sometimes the honest
  answer, and the spec should be able to document/require that per-tool rather
  than pretend every compiler flag combination is cacheable.**
- **MSVC `/showIncludes`**: MSVC's dependency-tracking equivalent of
  `-MD`/`-MMD`, auto-added by ccache when not already present so it can build a
  direct-mode manifest without a separate preprocessor pass — but only
  reliable when ccache's own base-dir path matching does case-insensitive
  comparison against the paths `/showIncludes` prints (Windows paths are
  case-insensitive; a naive case-sensitive compare silently breaks matching).
  **Lesson: any include-path comparison logic must be platform-case-
  awareness-explicit, not assumed case-sensitive everywhere.**
- **Color diagnostics / TTY auto-detection** (`-fdiagnostics-color`,
  `-fcolor-diagnostics`, GCC/Clang's own "am I attached to a TTY" probe): a
  wrapper sitting *between* the real compiler and the terminal breaks that
  probe (the compiler now sees a pipe, not a TTY, because the wrapper is the
  actual TTY-attached process) — ccache's own issue tracker shows repeated,
  recurring bugs here (probing not working, an unrecognized compiler silently
  losing color it would otherwise have produced, a cached result improperly
  reusing a color-flag-mismatched entry). **Lesson: any wrapper-model cache
  needs an explicit, tested TTY-passthrough or TTY-emulation story, not an
  assumption that "just exec the real tool" preserves terminal detection.**
- **Locale** (`sloppiness=locale`): compiler diagnostic text itself can vary by
  `LANG`/`LC_ALL`, meaning identical inputs under a different locale produce
  different (translated) stderr — a real, if narrow, way "the same inputs"
  produce different cacheable bytes. Needs an explicit opt-in sloppiness, not
  a silent assumption that stderr is locale-invariant.
- **`umask`**: a shared cache directory's file permissions depend on whichever
  process last wrote an entry; ccache had a real, since-fixed bug where a
  *remote*-cache-sourced entry, when copied into the *local* cache, used the
  original umask rather than the current process's — a subtle
  multi-tier-cache-specific permission bug. **Lesson: a multi-tier cache
  (local + remote) needs one explicit, tested rule for which umask governs a
  promoted/demoted entry, stated in the spec.**
- **Hard-link vs. copy, and mtime**: (ccache.md, buildcache.md both surface
  this) a hard-linked cache entry shares its inode — and therefore its mtime —
  with the build output. Any build system or downstream tool that gates work
  on mtime (classic `make`, and the buildcache-tracker "Ninja recompiling a
  `.cpp` unit even when already compiled" bug) can be fooled by a hit that
  never touched the compiler at all. **Lesson: a hard-link/reflink fast path
  must either guarantee a fresh mtime on the visible file (a `touch` after
  linking) or be gated behind an explicit "this build system doesn't care
  about mtime" declaration — never assumed safe by default.**
- **`-fmodules` / C++20 modules**: every tool in this survey either doesn't
  support it, sloppily approximates it (ccache's `sloppiness=modules`, which
  is explicitly a relaxation, not real module-dependency-aware hashing), or
  partially supports it for exactly one compiler (sccache: Clang only).
  **Lesson: module-aware caching (a compiled module interface file the
  compiler produces and later reads as an *input* to a different compile) is
  the frontier every existing tool has punted on — api-cache's spec language
  should treat "does this action consume another action's output as an input,
  beyond a flat file list" as an open design question, not something to
  silently ignore the way sloppiness flags do.**

## The one meta-lesson

Every tool in this survey eventually reinvents the same handful of primitives
independently: bounded/approximate LRU eviction, two-level hex directory
sharding, a "cache is optional, never load-bearing" failure posture, and a
size-cap-plus-per-entry-cap pair of config knobs. None of that is
per-language vocabulary — it is exactly the kind of shared, tool-agnostic
**engine mechanism** api-dsl's own CLAUDE.md insists belongs below any
consumer-specific vocabulary line. The prior art here strongly supports
api-cache's own likely shape: one engine owning hashing-mode selection,
storage, eviction, and remote protocol, with per-compiler/per-tool
*vocabulary* — which flags matter, which flags force a bypass, what the
output-file set looks like — expressed declaratively (buildcache's Lua
contract is the existence proof that this is sufficient), never hard-coded
into the engine itself.

## Sources

Per-flag citations: ccache manual and issue tracker (linked in ccache.md and
inline above), buildcache's own GitLab issues (buildcache.md), sccache's
README/docs (sccache.md), REAPI proto (other-wrappers.md).
