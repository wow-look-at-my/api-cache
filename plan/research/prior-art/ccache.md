# ccache

**License: GPL-3.0-or-later.** Copyleft. The org avoids viral licenses, so ccache's
implementation cannot be copied or adapted line-for-line into api-cache — only its
documented *behavior* (this file) may inform a clean-room design.

Primary source: [ccache manual, latest](https://ccache.dev/manual/latest.html),
[ccache/ccache on GitHub](https://github.com/ccache/ccache).

## Hashing modes

- **Direct mode** (default). Hashes the source file and the compiler command line
  directly (no preprocessor run on a hit), then validates against a **manifest**: a
  record of every include file's path and content hash that a prior compile of this
  key read. A manifest hit means "these exact includes, unchanged, plus this exact
  command line, produced this object before." A manifest miss (an include changed,
  or one that didn't exist before now does) falls through to preprocessor mode.
- **Preprocessor mode.** Runs the real preprocessor (`-E`), then hashes: the
  preprocessed output, the relevant command-line options (options that only affect
  preprocessing, like include search paths, are dropped from the hash if they don't
  change output), and any preprocessor stderr. This is the fallback on a direct-mode
  miss, and the only mode when direct mode is disabled or unusable (`__TIME__` in
  source, for instance).
- **Depend mode** (`depend_mode`, default false). Skips both of the above: it hashes
  using only the dependency information the compiler already emits (`-MD`/`-MMD`, or
  MSVC `/showIncludes`), so a miss costs strictly less (no separate preprocessor
  invocation) at the cost of a coarser, less precise key. Off by default because it
  trusts the compiler's dep-file completeness rather than ccache's own manifest
  validation.
- **`run_second_cpp`** (default true == `CCACHE_CPP2`). On a *miss*, ccache still ran
  the preprocessor once to compute the hash; `run_second_cpp=true` then runs the real
  compiler on the *original* source a second time. `run_second_cpp=false` instead
  feeds the already-preprocessed output to the compiler on that miss, saving one
  preprocessor pass but changing what the compiler actually sees (macros already
  expanded), which can change warnings/diagnostics and is why it isn't the default.

**Design read-across:** ccache's three-tier mode selection is really a speed/precision
knob at one axis (how much of "did the inputs change" gets verified structurally vs.
by re-running a real tool) and a second axis (how much re-running of that tool the
miss path costs). A generalized cache with pluggable languages needs an equivalent
knob per action *kind*, not a single global mode, since "depend info" only exists for
tools that emit it.

## Manifest format

Conceptually: key → list of `{include-file-path, hash}` pairs plus the object result
reference. Multiple manifest *entries* can exist per key when the same command line,
run in different environments, reads different include sets (e.g. same source,
different `-I` search order resolving to different headers) — ccache keeps several
candidate manifests and tries each until one validates or all miss.

## Sloppiness (`sloppiness=`, comma-separated opt-ins to relaxed correctness)

`clang_index_store`, `file_stat_matches`, `file_stat_matches_ctime`, `gcno_cwd`,
`incbin`, `include_file_ctime`, `include_file_mtime`, `ivfsoverlay`, `locale`,
`modules`, `pch_defines`, `random_seed`, `system_headers`, `time_macros`.

Each is a named, auditable escape hatch from an otherwise-safe default: e.g.
`include_file_mtime`/`include_file_ctime` stop ccache from invalidating a hit just
because an include's mtime/ctime changed (useful when a VCS checkout or Docker layer
touches timestamps without touching content — content hash still gates correctness).
`time_macros` is the opt-in that makes `__DATE__`/`__TIME__` *not* disable direct
mode (see below). `system_headers` skips hashing headers ccache believes are
immutable system headers, trading a small correctness risk for large speedups on
`-I/usr/include`-heavy builds. **Design lesson:** sloppiness is a good pattern —
correctness relaxations are each individually named, individually loggable, and off
by default, rather than one global "fast mode" flag.

## Path handling: `base_dir` and absolute paths

`base_dir` (unset by default) names a directory prefix. Any absolute path under it
(source paths, include paths) is rewritten to a path *relative to the current working
directory* before hashing. This is what makes the cache shareable across two
checkouts of the same repo at different absolute locations (two CI workers, or a
worker vs. a developer machine) — without it, the absolute path leaks into the hash
(and often into embedded debug info) and defeats sharing. The tradeoff: relative
paths in debug info are only correct if every consuming tool also fixes up `cwd`, and
sccache/ccache both have a matching `hash_dir` control for whether the *build
directory itself* also gets hashed (see below).

## `hash_dir` (default true)

When true, the current working directory is included in the hash, specifically
because it ends up embedded in debug info (`-g`) for the object file; a cache hit
from a different build directory would otherwise silently produce an object whose
embedded debug paths point at the wrong tree. Setting it false is a deliberate
tradeoff: share the cache across build directories, accept debug info that lies about
cwd (usually fixed by `-fdebug-prefix-map` instead — see lessons.md).

## `__DATE__`/`__TIME__` handling

Presence of `__TIME__` (or `__DATE__`) in the *preprocessed* source disables direct
mode outright for that compile — the manifest short-circuit assumes "same inputs, same
output," which the volatile macro breaks by definition (same inputs, different output
each second). It still allows preprocessor mode to work correctly, since that mode
literally reruns the preprocessor and hashes its actual expanded output including the
current timestamp — so it correctly *never* hits (every compile gets a unique hash),
which is "correct but slow," not "wrong." `sloppiness=time_macros` opts back into
direct mode despite the macros, on the (unenforced) assumption the build doesn't care
that the embedded date/time is stale.

## Precompiled headers (PCH)

Needs explicit setup: `sloppiness=pch_defines,time_macros`, `-include header.h` (GCC)
or `-include-pch` (Clang) or `-fpch-preprocess` (GCC to keep working with
preprocessor mode), and on Clang additionally `-fno-pch-timestamp` (Clang otherwise
stamps the PCH file with a build timestamp that busts any hash). Without the right
combination, ccache either can't cache at all (falls back to "Preprocessing failed"
or just recompiling every time) or silently loses the PCH speedup. This is the
sharpest edge case in the whole tool: PCH support is bolted on, compiler-specific, and
requires the user to know which sloppiness flags a PCH implies.

## stdout/stderr caching

ccache caches captured stderr output alongside the object (so a cache hit replays the
exact same warnings the original compile produced) and captures it as part of the
preprocessor-mode hash. Output to `-o -` (stdout) is unsupported and disables
caching outright — the tool assumes exactly one well-defined output file it can
address by path.

## Compiler flags that force a bypass (no caching at all)

- Multiple source files in one invocation (ccache assumes one-output-per-invocation).
- `-o -` (object to stdout).
- `-E` (preprocess-only invocation — nothing to cache, there's no compiled object).
- `-fprofile-generate` (and friends): profile-guided instrumentation writes profile
  data as a *side effect of running the produced binary*, so the object's behavior
  depends on execution history no static hash can capture; ccache treats these as
  uncacheable rather than risk a stale profile.
- Unsupported preprocessor-passthrough flags: `-Xpreprocessor <opt>` or arbitrary
  `-Wp,<opt>` — these hand raw flags to the preprocessor that ccache can't
  interpret/hash reliably, so it refuses rather than guess.
- A `ccache:disable` comment inside the first 4096 bytes of the source file — an
  explicit per-file opt-out a codebase can embed.

**Design lesson:** the bypass list is exactly "anything where ccache cannot prove
input-determines-output," stated as a closed, documented list rather than silent
best-effort. A generalized cache needs the same posture per action kind: an explicit,
named list of "this shape of invocation cannot be cached, and here is why," not a
try-and-hope path.

## Secondary / remote storage (`remote_storage=`)

A single config string can chain multiple backends, tried in order, e.g.
`remote_storage = redis://cache.example.com|file:/mnt/nfs/ccache`.

- **`file:/directory`** or **`file://host/directory`** — a plain directory tree,
  parameters `@layout` (`flat`/`local`/`subdirs`), `@umask`, `@update-mtime`.
- **`http://host[:port][/path]`** — GET/PUT/DELETE per object; `@layout`
  (`bazel`/`flat`/`subdirs` — note the explicit Bazel-remote-cache-compatible
  layout option), `@bearer-token`, `@keep-alive`, `@header`. Marked deprecated in
  favor of the newer backends but still present.
- **`redis://[user:pass@]host[:port][/db]`** or **`redis+unix:path`** — object
  storage in Redis with LRU eviction configured Redis-side. Also marked deprecated.
- **`crsh:ipc_endpoint`** — hands off to an external helper process over IPC, an
  escape hatch for a backend ccache doesn't implement natively.

Common remote-storage properties: `read-only`, `idle-timeout`, `request-timeout`,
`data-timeout`, and `shards` (multiple endpoints, Rendezvous/HRW hashing across them
for horizontal scaling without a central index).

`remote_only=true` skips the local on-disk cache entirely and only consults remote
storage (statistics still recorded locally unless `stats=false`). `reshare=true`
means a *local* cache hit is also pushed up to remote storage — the default (false)
assumes whoever populated the local hit already pushed it remotely, so a plain
consumer doesn't re-upload on every hit.

## Compression

Default codec is **zstd** at level 1 (fast). `compression_level` ranges negative
(ultra-fast) through 0 (meaning "use the default," i.e. 1) up to 19 (max ratio, much
slower). Compression is unconditionally **disabled** when `file_clone` or `hard_link`
is enabled, since both of those short-circuit to a filesystem-level linked/cloned
copy of the *exact stored bytes* — compressing would defeat the point (the object
must be usable as-is without a decompress step, since it becomes the actual output
file via link/clone). `ccache --recompress LEVEL` rewrites an existing cache to a new
compression level after the fact.

## `file_clone` and `hard_link` (both default false)

- **`file_clone`**: uses copy-on-write reflinks (`ioctl(FICLONE)`/btrfs/APFS/ZFS
  semantics) where the filesystem supports them. Documented as completely safe,
  because a CoW clone is immutable-until-written, so mutating the "copy" (the build
  output) never corrupts the cached original.
- **`hard_link`**: links the cache file directly into the build tree. Explicitly
  documented as *not* safe — a hard link means the build output and the cached
  original are the literal same inode; if anything later modifies the output in
  place (a linker touching it, a build step chmod'ing or truncating it), the cached
  copy is silently corrupted for every future consumer. It also means the linked
  file's mtime is shared/changed, which is its own footgun for build systems that
  gate on mtime (make-style). This is one of the sharpest documented "here be
  dragons" flags in ccache and directly informs lessons.md.

## `inode_cache` (default true, Windows: false/experimental)

Caches a *source file's own hash* keyed by `(device, inode, size, mtime, ctime)`
tuple, entirely local and in front of ccache's own key computation — this avoids
re-reading and re-hashing an unchanged source file across repeated invocations in
the same build (e.g. incremental rebuilds touching the same headers many times).
Requires `temporary_dir` to be on a local filesystem (the cache structure is
filesystem-identity-dependent, so it can't span a network mount safely).

## `compiler_check` (default `mtime`)

Controls what identifies "the compiler" in the cache key, since a stale compiler
binary producing a hit for a newer compiler would be a correctness bug:
`mtime` (fast, default — but "rebuilds silently miss the fact a symlinked/relinked
compiler is actually different if mtime didn't change"), `content` (hash the
compiler binary — safe, slower), `none` (don't hash it at all — fast, unsafe across
compiler upgrades), `string:value` (developer-supplied fixed string, e.g. a version
tag from CI metadata), or an arbitrary command string whose *output* is hashed
(lets a wrapper script report a stable logical identity even though the underlying
binary path/mtime churns).

## umask

An explicit octal umask applied to files/directories ccache creates in the cache
dir — exists specifically for **shared caches** with multiple users/UIDs (e.g.
`umask=002` for a group-writable shared cache), otherwise the caching user's
default umask could make cache entries unreadable/unwritable by others.

## Cleanup / LRU with levels

The cache directory is sharded into a tree (`cache_dir_levels`, subdirectories named
by hex prefix of the key) so a single directory never holds millions of entries
directly — this is the same sharding rationale go-s3-server documents for its own
`prefix/v1/aa/bbccdd` layout. After storing a result, if `max_size` or `max_files` is
exceeded, ccache evicts in *approximate* LRU order by mtime — approximate because,
for cost reasons, only a bounded subset of candidates is examined per cleanup pass
rather than a global sort, so "oldest" is not guaranteed to be the very oldest, only
"old enough, cheaply found." This mirrors go-s3-server's own two-walk sweep design
(`docs/eviction.md`) far more than it looks like a coincidence — bounded-cost
approximate LRU shows up whenever a cache can't afford an O(n log n) global sort per
eviction.

## Config precedence (highest to lowest)

1. `KEY=VALUE` arguments on the ccache command line itself.
2. `CCACHE_*` environment variables.
3. A directory-local `ccache.conf`, discovered by searching upward from cwd (stopping
   at a ceiling directory, a `.git`/`.hg` marker, or `$HOME`).
4. `ccache.conf` inside `$CCACHE_DIR` (the cache-specific config).
5. System-wide `/etc/ccache.conf`.
6. Compiled-in defaults.

`CCACHE_CONFIGPATH` is the one override that bypasses the file-discovery search
entirely and names an exact config file.

## Invocation model: masquerade vs. prefix

- **Prefix invocation**: `ccache gcc -c file.c` — the build explicitly names ccache
  first. Simple, but requires every build rule to be edited (or `CC="ccache gcc"`
  threaded through).
- **Masquerade invocation**: a symlink (or copy) named `gcc`/`cc`/`g++`/etc. is placed
  earlier in `PATH` than the real compiler, and ccache detects which compiler it's
  standing in for from `argv[0]`. This lets an *unmodified* build system pick up
  caching with zero build-file changes, at the cost of PATH ordering being a hidden,
  fragile dependency (and the "other wrappers" conflict warning noted above — two
  masquerading wrappers stacked without cooperation break).

## Design lessons for api-cache (see also lessons.md)

- A three-tier hash-precision/cost tradeoff (direct/preprocessor/depend) generalizes
  as: "does this action kind expose a cheap, structurally-verifiable proof of
  unchanged inputs (a manifest), or must we canonicalize+rerun a real tool step to
  get a hash?" That needs to be a per-action-kind capability, not a global mode.
  api-cli/api-mirror's own DSL split (engine mechanism vs. spec vocabulary) is the
  right shape: the *sloppiness knobs* and *bypass conditions* are mechanism; *which
  flags trigger them for a given compiler* is vocabulary that belongs in a spec, the
  same way api-dsl refuses to know about a consumer's element names.
- Sloppiness-as-named-opt-ins (not one "fast mode" switch) is worth copying as a
  pattern wholesale.
- `hard_link`'s documented unsafety vs. `file_clone`'s documented safety is the
  clearest real-world evidence that "share bytes with the build output" needs
  filesystem-CoW semantics or nothing — a generalized cache offering a hard-link
  fast path should refuse it (or scream) on filesystems without CoW.
- Masquerade-vs-prefix-vs-daemon (compare sccache) is the recurring invocation-model
  choice every one of these tools reinvents; comparison.md tracks it across tools.
