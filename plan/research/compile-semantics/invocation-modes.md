# How the wrapper gets invoked, and what that forces it to handle

Sources: ccache `src/ccache/{main,ccache,execute,signalhandler}.cpp` and
`src/ccache/core/atomicfile.cpp` (**GPL-3.0**, behaviour only); buildcache
`src/main.cpp`, `src/base/file_utils.cpp`, `doc/usage.md` (**zlib**); sccache
`src/util.rs` `resolve_compiler_avoiding_wrapper`; measured probe
`probes/out/06-rustc-wrapper.txt`.

## 1. The four invocation modes

### 1a. Prefix (launcher)

```
$ api-cache gcc -c -O2 foo.c -o foo.o
```

argv[1] is the tool. The simplest mode: nothing to resolve, nothing to disambiguate. This
is what `CMAKE_<LANG>_COMPILER_LAUNCHER`, `RUSTC_WRAPPER`, and Bazel's
`--action_env`-based wrappers all produce.

### 1b. Masquerade (symlink on PATH)

```
$ ln -s /usr/bin/api-cache ~/bin/gcc      # ~/bin early in PATH
$ gcc -c -O2 foo.c -o foo.o
```

argv[0] is `gcc` and there is **no** tool in argv. The wrapper must find the real `gcc`
itself. This is the mode that creates every hard problem in this file.

### 1c. Impersonation (an env var names the tool)

buildcache's `BUILDCACHE_IMPERSONATE=cl.exe` makes the binary behave as a wrapper for that
tool even when invoked under its own name — "this allows pointing build systems directly at
the BuildCache executable instead of using symbolic links". The documented cost: when it is
set, **the wrapper's own command-line options become unavailable**, because every argument
is forwarded.

### 1d. In-process / protocol (no wrapper at all)

Go's `GOCACHEPROG` (see `go-and-others.md` §1) and Swift's `-cache-compile-job`. The tool
asks the cache; the cache never parses argv.

## 2. Finding the real tool, and not finding yourself

### ccache's algorithm (`find_compiler`, ccache.cpp ~2715)

1. If the user configured `compiler`, use that.
2. Else, if masquerading, use **only the basename** of argv[0] (`gcc`), so that a
   `~/bin/gcc` symlink resolves to a different `gcc`. If not masquerading, use argv[0] whole.
3. If that is a full path, take it. Otherwise walk `PATH` (or the configured `path`),
   trying `<dir>/<name>` (and `<dir>/<name>.exe` on Windows), and accept the first candidate
   that passes **two** filters:
   - it is not the **`exclude_path`** — ccache passes argv[0], **canonicalised**, so the
     symlink you were invoked through is skipped even when it resolves elsewhere;
   - `!is_ccache_executable(path)` — a name check that also rejects *another* ccache
     installation further down PATH.
4. If the resolved compiler is itself ccache → `throw Fatal("Recursive invocation of ccache")`.

### buildcache's algorithm (`file::find_executable(program, exclude)`)

Different and arguably better on one axis: the filter is on the **resolved real path's
basename** — `lower_case(get_file_part(true_path)) != "buildcache"`. So a `cc` symlink
pointing at buildcache is rejected regardless of the name it was reached under. It keeps
both paths:

- `real_path()` — used to decide *which wrapper* handles the command and to compute the
  program identity;
- `virtual_path()` — substituted into argv[0] before anything else runs, "important to
  avoid recursions when we are invoked from a symlink".

The `virtual_path`/`real_path` split is exactly what makes `clang-cl` dispatch correct
(see `msvc.md` §12): `clang-cl` is often a symlink to `clang`, so the *virtual* path says
`clang-cl` (route to the MSVC wrapper) while the *real* path says `clang`.

### The environment recursion guard

Name-based PATH filtering is not enough. The failure it misses: the "real compiler" you
find is a **shell script** that itself calls `ccache $compiler …`. Then you recurse through
a program whose name is not yours.

ccache's answer (ccache.cpp ~2985), verbatim in intent:

> Set `CCACHE_DISABLE` so no process ccache executes from now on will risk calling ccache
> a second time. For instance, if the real compiler is a wrapper script that calls
> `ccache $compiler ...` we want that inner ccache call to be disabled.

So: **`setenv("CCACHE_DISABLE","1")` before spawning anything**, and check that variable at
startup (`if (ctx.config.disable()) return`, ccache.cpp ~2975). The guard is inherited by
every descendant, which is exactly the scope you want. buildcache has the same switch,
`BUILDCACHE_DISABLE`, though it is documented as a user control rather than as a guard.

sccache names its version of this problem explicitly:
`resolve_compiler_avoiding_wrapper` (used by the nvcc path, where nvcc must find a *host*
compiler and must not find sccache).

**Three guards, all needed:**
1. skip the canonicalised argv[0] while walking PATH (handles the symlink you came in
   through);
2. reject any candidate that is the wrapper binary (handles a second installation);
3. set a disable-flag env var for the whole subtree (handles a script that re-invokes you).

## 3. How build systems are configured to use it

| System | Mechanism | Notes |
|---|---|---|
| CMake | `CMAKE_<LANG>_COMPILER_LAUNCHER` (`C`, `CXX`, `CUDA`, …), set as a variable or on the command line | The clean mechanism: the launcher is prepended to each compile rule, and CMake keeps the compiler identity it probed at configure time. Also `CMAKE_<LANG>_LINKER_LAUNCHER`. With MSVC, also set `CMAKE_MSVC_DEBUG_INFORMATION_FORMAT` to `Embedded` (`/Z7`) — see `msvc.md` §3. |
| CMake (crude) | `CC="api-cache gcc"` / `CXX="api-cache g++"` | Works, but CMake stores the whole string as the compiler and some checks then misbehave; and a `CC` with a space breaks tools that `exec` it directly. |
| Make | `CC = api-cache gcc` in the makefile, or `make CC="api-cache gcc"` | Same caveat. |
| Ninja | Whatever generated the `.ninja` file decided. Editing rules by hand is not a supported workflow. | |
| Cargo | `RUSTC_WRAPPER`, `RUSTC_WORKSPACE_WRAPPER` — see `rustc.md` §1. **Both set → nested**, measured. | The wrapper is also called for cargo's `-vV` and `--print=file-names` probes and must pass them through. |
| Bazel | Not a launcher: Bazel has its own action cache and remote cache. To interpose you would write a `cc_toolchain` whose `tool_path` points at the wrapper, and mark it in `--action_env`. Generally the wrong thing to do — see `go-and-others.md` §6. | |
| Go | `GOCACHEPROG` — a protocol, not a wrapper. | |
| Symlinks | `ln -s api-cache ~/bin/{gcc,g++,cc,c++}` with `~/bin` first on PATH. | The only mode that catches compiles a build system launches without consulting any variable. |
| Distributed | buildcache's `BUILDCACHE_PREFIX=/usr/bin/icecc` inserts a *second* prefix in front of the real compiler on a miss (`sys::run_with_prefix`). ccache has `prefix_command` and `prefix_command_cpp` (a separate one for the preprocessor run). | A cache and a distributor compose: cache first, distribute the miss. |

**`--` separators.** A launcher's own flags must be separable from the tool's. ccache's
`main` distinguishes "invoked as ccache with ccache options" from "invoked as a compiler
wrapper" by looking at argv[0] first; buildcache does the same and *disables* its own
options entirely under `BUILDCACHE_IMPERSONATE`. The lesson: if the wrapper has flags of
its own, they can only be safely accepted in prefix mode, and a `--` terminator is the
only unambiguous separator. Note MSVC also uses `--` (before the source file), so a rule
must not consume the tool's own `--`.

## 4. Process semantics on a miss

### Exit code

Pass the child's exit code through **unchanged**. Both ccache and buildcache do, and
buildcache's comment is the one to internalise: *even when the compile failed, the wrapper
has "done the expected job — running the program again would just take twice the time and
give the same errors"*. So on a failure: replay nothing, store nothing, return the child's
code.

Do **not** cache a non-zero exit by default (buildcache's `cache_on_failure` is an opt-in;
ccache simply never stores a failed result). The stated reason is intermittent faults — a
disk-full, an OOM-killed cc1, a flaky network filesystem — which would otherwise be served
as a "successful" failure forever.

### Signals

ccache installs handlers for **SIGINT, SIGTERM, SIGHUP, SIGQUIT**, and ignores SIGPIPE.
On a signal (`SignalHandler::on_signal`):

1. Restore the default disposition for that signal (so the final re-raise terminates).
2. **If the signal is SIGTERM and a compiler child is running, `kill(compiler_pid, signum)`**
   — "if ccache was killed explicitly, then bring the compiler subprocess with us as well".
   Note it does this only for SIGTERM: a SIGINT from a terminal already reaches the whole
   foreground process group, so forwarding it would double-signal.
3. `unlink_pending_tmp_files_signal_safe()` — remove every temp file, using only
   async-signal-safe calls.
4. `waitpid(compiler_pid, 0)` — **wait for the child to actually exit** before dying, so
   the child does not outlive the wrapper and keep writing to the object path.
5. `kill(getpid(), signum)` — re-raise, so the parent shell sees a signal death rather
   than an exit code.

It also exposes `block_signals()`/`unblock_signals()` (`sigprocmask`) with an RAII blocker,
used around the critical sections where a half-written cache entry would be left behind.

**The invariant: a killed compile must cache nothing.** The child may have written a
partial object; the wrapper must not store it, and must not leave a temp file behind.

### stdin

A compiler reading source from stdin (`gcc -x c -`) is a bypass (`c-cxx-gcc-clang.md` §1.3)
— there is no source identity to key on. But the wrapper must still **pass stdin through**
for the bypass path, and for tools that legitimately read stdin (cargo's
`rustc - --print=file-names` probe). A wrapper that closes or /dev/null's stdin breaks
those.

## 5. Filesystem mechanics

### Temp files and atomic replacement

The rule is unchanging: **write to a temp file in the same directory as the destination,
fsync if durability matters, then `rename(2)`.** `rename` is atomic only *within a
filesystem*, so a temp file in `/tmp` cannot be renamed onto a destination on another mount
— it silently degrades to a copy, or fails with `EXDEV`. ccache's `AtomicFile` creates its
temp next to the target and renames (`core/atomicfile.cpp`).

Two destinations, two temp directories:
- restoring an output → temp next to the **output path**;
- storing a cache entry → temp inside the **cache directory**.

### Concurrency: two identical compiles racing

Two `make -j` jobs compiling the same file with the same flags will compute the same key
and both miss. Both will compile, and both will try to store. This is **safe by
construction** with temp+rename: the loser's rename replaces the winner's file with
byte-identical (or at least equally valid) content. No lock is required for correctness of
the *store*.

What does need care:
- **Restoring** two outputs of one entry must not be observable half-done. Restore each to
  a temp and rename each; a reader that catches the intermediate state sees the old file,
  not a truncated one.
- **Hard links.** buildcache and ccache both offer hard-linking cache entries into place
  (off by default in ccache; a per-wrapper `hard_links` capability in buildcache). The
  hazard is stated in buildcache's own code: it advertises `hard_links` "since GCC will
  never overwrite already existing files" — i.e. hard links are only safe when **every
  consumer of the output replaces it rather than writing into it**. If any later step opens
  the object `O_WRONLY` and writes in place (a `strip -o same-file`, an `objcopy` in place,
  a build step that appends), **the cache entry is corrupted for every other user of that
  key.** This is the single most dangerous optimisation in the space. ccache's manual
  documents the same restriction; both default it off.
- **The compiler modifying its own input.** Rare but real (some code generators rewrite
  their input). ccache guards this with the *too-new* check (`hashing-and-normalization.md`
  §5): after the compile, if the source or any include has an mtime/ctime at or after the
  invocation time, the result is discarded with `modified_input_file`.

### umask and permissions

ccache carries `ctx.original_umask` and re-applies it with an RAII `UmaskScope` around the
places it creates files, because the *cache*'s umask (a config value, `umask`) and the
*build output*'s umask differ: a shared cache directory wants group-writable entries, a
build output wants the user's own umask. Two rules:

1. A restored output must have the permissions the compiler would have given it (i.e. the
   caller's umask), **not** the cache's.
2. A cache entry in a directory shared between users must be readable, and in a
   multi-user cache, writable by the group — otherwise the second user cannot evict or
   overwrite it. `umask` is listed in ccache's config as `DCP::unsafe`, meaning it may not
   be set from a directory-level config file, because a hostile repo could otherwise widen
   the permissions of a shared cache.
3. The **executable bit** matters for outputs that are programs (rustc `--crate-type bin`).
   A restore that loses it produces a build that "succeeds" and then cannot run.

## 6. Checklist for the engine

| Concern | Requirement |
|---|---|
| tool resolution | basename-only when masquerading; skip canonicalised argv[0]; reject any candidate that is the wrapper; keep `virtual_path` **and** `real_path` |
| recursion | set a disable env var for the whole descendant subtree before spawning |
| self-identification | a name check (`is_wrapper_executable`) that survives symlinks and renames |
| own flags | only in prefix mode, terminated by `--`; never consume the tool's own `--` |
| exit code | pass through verbatim; never re-run on failure; never cache non-zero by default |
| signals | handle INT/TERM/HUP/QUIT; forward TERM to the child; unlink temps signal-safely; `waitpid` before re-raising; re-raise rather than `exit()` |
| stdin | pass through; bypass when it *is* the source |
| temp files | same filesystem as the destination, always |
| atomicity | temp + rename for every restored output and every stored entry |
| races | rename makes identical-key races safe with no lock |
| hard links | off by default; only legal when no consumer writes the output in place |
| permissions | restored outputs take the caller's umask, not the cache's; preserve the executable bit |
| input mutation | re-check input mtime/ctime after the compile; discard if it moved |
