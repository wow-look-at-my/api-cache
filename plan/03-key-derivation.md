# 03 — Key derivation

How an invocation becomes a key, what the key covers, the three lookup modes, the manifest, normalization, the closed verdict vocabulary, and the correctness hazards the engine guards. The evidence is `plan/research/compile-semantics/`, and the msvc-probes corrections that supersede parts of it.

## The hash

**BLAKE3, 32 bytes, for every action key and manifest key.** SHA-256 appears only where a protocol fixes it: the GOCACHEPROG `OutputID` is `sha256(body)` by definition. The reasons, measured in `plan/research/storage-protocol/local-layout.md`:

- SHA-256 throughput swings 6x across the four machines measured (365 MB/s on an x86 without `sha_ni`, 2,177 MB/s on an M1). A direct-mode lookup hashes the source and every header, so this is on the hit path. BLAKE3 is uniformly fast and does not depend on a crypto instruction.
- The key is a collision-security boundary on a shared remote. XXH3 (buildcache's choice) is out for that reason; a hostile writer could construct a collision.
- Go library: `lukechampine.com/blake3` (MIT) or `zeebo/blake3` (CC0 / BSD-2). Both are acceptable licences; pick on measured throughput on the CI matrix.

**Framing and tagging** are mandatory, not optional. Every logical item is written as `tag, length, bytes`, ccache's `hash_delimiter` discipline (`hashing-and-normalization.md` §1): `-I -O2` and `-I-O2` hash differently, and a conditionally hashed item (the cwd under debug info) cannot make two different conditions produce the same stream.

**Format version salt.** The stream begins with the engine's hash-format version and the rule's `version=`. A change to either invalidates by construction. There is no hand-bumped cache-version constant elsewhere; everything else is derived, which is api-mirror's fingerprint rule.

**Fork, never reuse.** The direct key and the preprocessed key are forks of the common prefix with a tag injected, so the two key spaces cannot collide.

## What the common key covers

In order, with the tag each item carries:

1. `format` — engine hash-format version, rule version.
2. `tool` — the identity per the rule's policy (`mtime`, `content`, `command`, `string`), memoised by `path:size:mtime`.
3. `name` — the basename the tool was invoked under. gcc behaves differently as `gcc`, `g++` and `cc`.
4. `env` — each variable in the rule's allowlist, sorted, with unset distinct from empty.
5. `arg` — each classified argument whose role is not `ignore`, `primary-output`, `dep-output`, `path-write-untracked` or a `cpp-only` role (in preprocessor mode). Paths under `hash-normalized-path` go through the prefix maps and base-dir first. `path-read` contributes the file's content, not its path.
6. `expand` — the tool's own expansion of `-march=native` and friends, from the rule's `<expand>` query.
7. `cwd` — only when the rule's mode flags say the cwd leaks: `debug-info` without a prefix map that covers it, `coverage` without `gcno_cwd`, MSVC always (objects embed their directory, measured in `plan/research/msvc-probes/results/p11-determinism.md`), and rustc always.
8. `output-path` — only under `hash-output-path` roles (`-gsplit-dwarf`: the object links to the `.dwo` by name).

The `-o` value is never hashed otherwise; two compiles that differ only in `-o` produce identical objects (measured).

## Three modes

| Mode | Cost of a hit | Cost of a miss | Completeness |
|---|---|---|---|
| Preprocessor | run the preprocessor, hash its output | preprocess + compile | complete: whatever the preprocessor read is in the text |
| Direct | stat and hash the manifest's recorded includes | preprocess (to learn the include set) + compile | as complete as the include report |
| Depend | none on the lookup side; the tool runs first | one compile | as complete as the dep output |

The rule declares which modes exist; the store decides which one to try first (direct, then preprocessor). Depend mode is opt-in per tool and per store setting, because gcc's `#pragma once` content de-duplication makes a dep-derived include set incomplete (`c-cxx-gcc-clang.md` §3, measured: two byte-identical headers, only the first is reported).

### Preprocessor mode

Key = common key (minus `cpp-only` rows) + the preprocessed text + the preprocessor's stderr. The rule's `<preprocess>` builds the argv: drop `-c`, `-o`, `-M*` and `comp-only` rows, add `-E`, add `-P` unless debug info or coverage needs the linemarkers, add the include-report flag. `-Werror` is `comp-only` so a `#warning` cannot fail the preprocess. `-x` and `-finput-charset=` are re-passed.

On a miss the real tool runs on the original source, not on the preprocessed text (ccache's `run_second_cpp=true` default). Feeding the `.i` back changes diagnostics and `__FILE__`.

### Direct mode

Direct key = common key + `cpp-only` rows + the `mode="direct"` env group + the source path + the source content. The source path is in the key on purpose: `a/x.c` and `b/x.c` with identical content resolve `#include "r.h"` differently (`c-cxx-gcc-clang.md` §3).

The direct key maps to a **manifest**, which holds several candidates:

```
manifest
  paths      : interned include paths
  file-infos : (path-index, digest, size, mtime, ctime)
  candidates : [ (file-info indexes, result key) ... ]     in insertion order
```

Lookup walks candidates in order and takes the first whose every file still matches. Validation per file: stat, then size, then (under `file_stat_matches`) mtime and ctime, else content hash. Bounds are ccache's: 100 candidates, 10,000 file infos, then the manifest resets. The manifest is a cache entry like any other (`04-local-store.md`), and a candidate whose result key is missing is an ordinary miss, never an error.

Direct mode is disabled for an invocation when the source or any include contains `__TIME__`, `#embed` or `.incbin`. `__DATE__` replaces the file's digest with one salted by the calendar day and `SOURCE_DATE_EPOCH`; `__TIMESTAMP__` with the file's mtime. `time_macros` sloppiness turns all of that off. The scanner is word-boundary aware and shared by every C-like rule.

**The `#pragma once` hazard** has no fix in any prior art. The plan's answer: when the tool identity is gcc and two files in the include set have the same size, the engine hashes both and, if their content is identical, records the manifest candidate with a `ambiguous_include_set` note and falls back to preprocessor mode for this invocation. It is cheap (a size comparison per pair is free; the content comparison only fires on a size match) and it closes the false-hit case. It is a named sloppiness (`pragma_once_dedup`) so a user can turn it off.

### Depend mode

Runs the tool first, then derives the result key from the dep output it produced (`-MD` file, `/showIncludes`, `/sourceDependencies`, rustc dep-info). One compile per miss instead of a preprocess plus a compile. Opt-in, for the completeness reason above, and it is the only mode that sees clang's `module.modulemap` files.

## Input discovery

The engine ships the parsers; the rule names which report to read:

| Report | Source | Notes |
|---|---|---|
| `linemarkers` | `-E` stdout | `# N "path"` lines. Absent under `-P`. |
| `-H` | preprocessor stderr | dots for depth. Omits implicit includes such as `stdc-predef.h`; the engine unions it with the depfile when both exist. |
| `depfile` | `-MD`/`-MF` or `--dependency_out` | Makefile tokenisation: ` \` continuation, `\ ` space, `$$`, `\#`, drive-letter disambiguation on Windows. gcc leaves `\` and `:` unescaped, clang rewrites `\` to `/` (measured). Any line the parser does not fully understand fails the parse, never a shorter list. |
| `showincludes` | cl stdout during a compile, stderr under `/E` | English prefix only. Depth is one space per level. Paths keep the separator the `#include` used. Duplicates are reported twice. |
| `sourcedependencies` | `/sourceDependencies` JSON | cl only; clang-cl ignores the flag silently at exit 0 (measured), so the clang-cl rule uses `/clang:-MD /clang:-MF` instead. |
| `depinfo` | rustc `--emit=dep-info` | First line plus phony lines plus `# env-dep:NAME[=VALUE]`, where a missing `=` means unset. |

## Outputs

Captured for every cacheable invocation: the primary output (or none under `syntax-only` roles), each `dep-output`, each `derived-output` sibling present on disk, stdout, stderr, and the exit code. A missing required output is `compiler_produced_no_output`; a zero-byte one is `compiler_produced_empty_output`; neither is stored. A non-zero exit is never stored by default; the child's code is returned without a rerun.

**Dependency file rewriting.** On a miss, before storing, absolute prerequisites under the base dir are relativised and the target is left alone. On a hit, if the invocation's `dep-target` differs from the stored one, everything up to the first `": "` is replaced. The stored dep file is otherwise verbatim: the engine never re-escapes a dep file it did not write.

**Diagnostics.** Colour is forced on for the child (`-fdiagnostics-color=always`, `-fcolor-diagnostics`, and `-fansi-escape-codes` for clang-cl), the coloured text is stored, and escapes are stripped on replay when the caller's stderr is not a terminal or the argv said `never`. cl and clang-cl emit no colour to a pipe, so the MSVC rule stores stdout verbatim (measured). Locale variables are in the env allowlist so replayed text matches the language of the invocation.

**MSVC's streams** are split three ways (`plan/research/msvc-probes/corrections.md` §6): banner on stderr, source-name line and compile diagnostics on stdout, command-line diagnostics on stderr. Both streams are stored and replayed. `/showIncludes` lines are stripped from stored stdout and regenerated with depth on a hit.

## Normalization

- **Prefix maps** (`-fdebug-prefix-map`, `-ffile-prefix-map`, `-fmacro-prefix-map`, `-fcoverage-prefix-map`, rustc `--remap-path-prefix`) apply in reverse argv order to the cwd and to `hash-normalized-path` values. `-fdebug-compilation-dir` replaces the cwd outright.
- **Base dir** is a prefix window, off by default, with ccache's documented brittleness carried into the docs: too wide rewrites system headers, too narrow leaves other roots absolute, and absolute paths are not reproduced in dep files. The docs steer users to `-ffile-prefix-map` in the build, which is the correct fix (`hashing-and-normalization.md` §4).
- **CRLF** is never normalised in sources. Dep-file tokenisation accepts both endings.
- **The tool's path** is never hashed; its identity, invoked name, `COMPILER_PATH` and `GCC_EXEC_PREFIX` are.

## Verdicts: the closed vocabulary

The engine's enum is ccache's list plus five additions (`key-derivation-model.md` §4). A rule cannot add to it; a rule chooses from it. Every verdict carries the triggering argument or variable.

Uncacheable: `autoconf_test`, `bad_compiler_arguments`, `called_for_link`, `called_for_preprocessing`, `compile_failed`, `compiler_produced_no_output`, `compiler_produced_empty_output`, `could_not_use_modules`, `could_not_use_precompiled_header`, `disabled`, `multiple_source_files`, `no_input_file`, `output_to_stdout`, `preprocessor_error`, `recache`, `unsupported_code_directive`, `unsupported_compiler_option`, `unsupported_environment_variable`, `unsupported_source_encoding`, `unsupported_source_language`, `unclassified_argument` (the `unknown="bypass"` outcome, the one `explain` turns into a proposed row), `unsupported_output_kind` (MSVC `/Zi`, with the `/Z7` remedy in the message), `unresolvable_input` (rustc `-l static=` with no archive on `-L`), `incremental_state` (rustc `-C incremental`), `unsupported_dep_output_combination` (`-Wp,-MD` with `-MF`), `ambiguous_include_set`, `unrecognized_include_report`.

Errors: `bad_input_file`, `bad_output_file`, `compiler_check_failed`, `could_not_find_compiler`, `error_hashing_extra_file`, `internal_error`, `missing_cache_file`, `modified_input_file`.

The distinction matters for the loud-and-fixable contract: an uncacheable verdict counts and aggregates; an error is printed every time.

## Correctness hazards the engine guards

| Hazard | Guard |
|---|---|
| A header rewritten within the timestamp granularity of the compile | The too-new check: after the run, any input with mtime or ctime at or after invocation time plus 100 ms → `modified_input_file`, nothing stored. Also covers a tool that rewrites its input. |
| A restored file shares an inode with the cache entry and is later written in place | Hard links only when the rule says `hard-link="safe"` and the store setting allows it; cached files are read-only; clone (CoW) preferred wherever the filesystem supports it (`04-local-store.md`). |
| A stale `.pch` that cl uses silently at exit 0 (measured) | The `.pch` content is in the key under `/Yu`, memoised by `path:size:mtime`. |
| `/Zi` PDB accumulating across compiles (measured: an unrelated second compile changes its bytes) | `unsupported_output_kind` for real cl; clang-cl's `/Zi` writes no PDB and is cacheable. |
| `VS_UNICODE_OUTPUT` present, even empty, silencing cl entirely | `<unset>` deletes the variable. |
| A killed compile leaving a partial object | Signal handling per `invocation-modes.md` §4: forward TERM, unlink temps signal-safely, wait for the child, re-raise. Nothing is stored. |
| Two identical compiles racing | Temp-and-rename makes the store safe without a lock; the content-equal check on the remote is the diagnostic. |
| An under-specified key | The remote's `write_once` with `notification=content_differs`, `action=allow`: every log line is a real hole in the key. Local stores get the same check as an opt-in diagnostic. |
| LTO objects not byte-reproducible | Not a hazard; the object is valid. Documented so the content-equal diagnostic is not read as a key bug for `-flto`. |
| MSVC objects never byte-reproducible, even with `/Brepro` (measured) | Same: the stored object is authoritative output, never re-derived or compared to a recompile. |

## Sloppiness registry

ccache's fourteen, plus `pragma_once_dedup`. Each is named, off by default, individually loggable, and attached to a stated risk in the docs. A rule lists which apply; a store setting or a command-line flag turns them on. There is no preset tier (buildcache's `accuracy`), because a preset loses the resolution a user needs when one relaxation is wanted and another is not.
