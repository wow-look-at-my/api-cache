# Go, CUDA, and the generic-action model

## 1. Go: `GOCACHEPROG`

Go does **not** need a compiler wrapper. Since Go 1.24 (stable; it was
`GOEXPERIMENT=gocacheprog` in 1.23) the `go` command delegates its *entire* build cache to
an external process named by the `GOCACHEPROG` environment variable. The go command already
knows what its cache keys are; the helper only stores and retrieves blobs.

Source: `/usr/local/go/src/cmd/go/internal/cacheprog/cacheprog.go` (BSD-3-Clause) and
`cmd/go/internal/cache/{cache,hash,prog}.go`, read on this machine (go1.24.7).

### The protocol

- `GOCACHEPROG` is a command with optional space-separated flags. The go command starts it
  **as a subprocess**, once, and speaks JSON over stdin/stdout. The child's **stderr is
  connected to the go command's stderr** — so anything the helper writes to stderr lands in
  the user's build log. (This is exactly the constraint the go-s3-server `cacheclient`
  module documents: "A caller whose stdout is a protocol channel must not have stderr
  written for it"; its default logger is silence.)
- **JSON lines**: one JSON object per line, both directions.
- **Handshake**: the child must *immediately* write one `Response` with `ID == 0` and
  `KnownCommands` listing the commands it supports. This is both a capability negotiation
  (the go command may add `get2` later) and a sanity check that the program intended to be
  a cache helper.
- Then a stream of `Request`s, each answered by a `Response`. **Responses may be sent out
  of order**; `Response.ID` must echo `Request.ID`.

Commands: `get`, `put`, `close`.

```go
type Request struct {
    ID       int64
    Command  Cmd       // "get" | "put" | "close"
    ActionID []byte    // cache key, for get and put
    OutputID []byte    // stored alongside the body, for put
    Body     io.Reader // NOT a JSON field
    BodySize int64
    ObjectID []byte    // deprecated pre-1.24 spelling of OutputID
}

type Response struct {
    ID            int64
    Err           string
    KnownCommands []Cmd      // only in the ID==0 handshake
    Miss          bool       // get
    OutputID      []byte     // get
    Size          int64      // get
    Time          *time.Time // get; when it was put, for expiry
    DiskPath      string     // get (on hit) and put
}
```

**The body is a separate line.** For a `put` with `BodySize > 0`, the go command writes the
JSON object, a newline, and then **a base64-encoded JSON string literal** of the body on
the following line. The comment gives the reason: it is a separate JSON value rather than a
struct field "so large values can be streamed in both directions".

**`DiskPath` is the load-bearing field.** For both `get` (on a hit) and `put`, the helper
must materialise the body **as a real file in the local filesystem** and return its
absolute path. The go command then opens that path directly — it does not read the bytes
back over the pipe. The file must survive **until the `close` request**. So a `GOCACHEPROG`
helper is necessarily also a local disk cache; a pure network client cannot satisfy the
contract without spooling.

`close` asks the helper to reply and then exit (closing its stdout).

### ActionID and OutputID

```go
// An ActionID is a cache action key, the hash of a complete description of a
// repeatable computation (command line, environment variables, input file
// contents, executable contents).
type ActionID [32]byte
// An OutputID is a cache output key, the hash of an output of a computation.
type OutputID [32]byte
```

Both are 32 bytes (`HashSize = 32`; SHA-256). **`OutputID` is by definition the hash of the
body**, which is what lets a client verify a download without trusting the server — and is
precisely what go-s3-server's self-heal exists to reconstruct when the metadata is missing
(see its `selfheal.go`: "`outputID` is by definition the `sha256` of the decompressed
body").

The go command builds an ActionID itself (`cmd/go/internal/work/exec.go`
`buildActionID`), by writing a description into a `cache.NewHash`:

```
build <importpath>            <- hash name
<hashSalt = runtime.Version()>
compile
module <path>@<version>
dir <p.Dir>                   <- only when the package is not reproducible-by-content
goos <GOOS> goarch <GOARCH>
import "<importpath>"
omitdebug … standard … local … prefix …
cgo "<toolID(cgo)>"
CC="<ccExe>" "<cppflags>" "<cflags>" "<ldflags>"
CC ID="<ccID>"                <- the C compiler's identity, when cgo is in play
compile <toolID(compile)> "<gcflags>" …
<KEY>=<VALUE>                 <- selected env vars
GOEXPERIMENT="…"
magic <ENV>=<value>
file <name> <content-hash>    <- one line per source file
import <importpath> <contentID-of-that-dep's-buildID>   <- transitive closure
```

Two structural notes worth carrying into api-cache's design:

- The salt is `runtime.Version()` — **the toolchain version invalidates the whole cache**,
  by construction, with no per-entry versioning.
- `import <path> <contentID>` means the key is **recursive over the dependency graph**, so
  one package's ActionID already covers every transitive input. That is why Go needs no
  include manifest and no preprocessor pass: the build system knows the graph.

### Read-across to go-s3-server

`go-s3-server/cacheclient` is exactly the client side of a remote store fronted by this
protocol, and its CLAUDE.md records the operational lessons:

- The key index (`/_index`) loads lazily, on the first Get or Put, never at construction,
  because "a go command that never asks for a key never downloads it" and "a test suite
  starts thousands of go commands a minute" against a tens-of-megabytes blob.
- Its guards are *the outputid hash, the build-id action, and the module index* — the
  outputid guard being the direct consequence of `OutputID == sha256(body)`.
- **Its `cacheprog` subcommand was deleted**: the consumer is now gosmopolitan's `cmd/go`,
  which calls the cache **in process**. So GOCACHEPROG is a protocol api-cache should be
  able to *speak* (to serve a stock `go`), but is not the only integration point.

**Design consequence for api-cache.** Go is the one major language where the right
integration is not a wrapper at all. A per-tool XML rule file for `go build` would be
wrong; what Go needs is a *mode* in which api-cache is the GOCACHEPROG server, deriving no
keys of its own and doing only storage. Compare the wrapper modes, where api-cache derives
the key.

## 2. CUDA / nvcc

sccache supports nvcc (`src/compiler/nvcc.rs`, Apache-2.0). Its approach is instructive
because it is **not** "wrap nvcc as one action".

`nvcc` is a driver that fans out into `cudafe++`, `cicc`, `ptxas`, `nvlink`, `fatbinary`,
**and** a host C++ compiler. sccache therefore:

1. Runs **`nvcc --dryrun` twice** to obtain the exact sub-command list — once with
   `--keep` (so the nvcc-internal tools' paths are relative to the temp dir) and once with
   `--keep --keep-dir <tmp>` (so the host-compiler commands' paths are relative to the
   original cwd, with absolute paths into the temp dir for generated files). It then
   interleaves the two listings by original line number. The dance exists because the
   sub-commands run in **two different working directories**.
2. Classifies each sub-command:
   - `cicc` and `ptxas` → **cacheable**, each as its own action (there are dedicated
     `src/compiler/{cicc,ptxas}.rs` modules).
   - `fatbinary` and `nvlink` → **not cacheable** (they are link-like).
   - the host preprocessor/compiler invocations → handled by the ordinary gcc/msvc path.
3. Groups the sub-commands so that independent device-compile groups can run in parallel
   when the user passed `nvcc --threads`.
4. Canonicalises `cicc`'s input path, because "cicc will get cache misses on otherwise
   identical" inputs otherwise.

**Host compiler detection** is `-ccbin` / `--compiler-bindir` (ccache marks both
`AFFECTS_CPP | TAKES_ARG`), defaulting to the platform host compiler; sccache carries an
`NvccHostCompiler` enum (`Msvc` vs the rest) because the preprocessing flag differs
(`-P` vs `-E`) and "other host compilers are presumed to match `gcc` behavior".

ccache instead wraps nvcc as a single action, mapping nvcc's long-form flags onto its
gcc table (`--compile`≈`-c`, `--generate-dependencies`≈`-M` (TOO_HARD),
`--generate-dependencies-with-compile`≈`-MD`, `--dependency-output`≈`-MF`,
`--output-directory`, `-odir`, `-ldir`, `-Xcompiler`, `--compiler-options`), and it
handles clang's CUDA mode by **splitting the preprocessed output into per-arch chunks**
(`split_preprocessed_output_from_clang_cuda`) and hashing each chunk separately — because
clang emits one `.i` containing several device passes plus the host pass.

**Lesson for a configurable engine:** a "tool" is not always one action. There must be a
way for a rule to say *"ask the tool to enumerate its sub-commands, then apply these rules
per sub-command"*, and to say which sub-commands are cacheable. This is where api-cli's
`<step over=>` construct maps almost directly.

## 3. Swift

Neither ccache nor sccache nor buildcache wraps `swiftc`. The reasons are structural and
worth recording so the planner does not budget for it:

- Swift compiles a **whole module at once** by default (whole-module-optimization), or in
  "batch mode" where one `swift-frontend` invocation compiles several files and emits
  several objects — the single-input/single-output shape does not hold.
- There is no preprocessor and no textual include set; module dependencies are resolved
  through `.swiftmodule` binaries whose content is compiler-version-specific, the same
  problem as C++20 modules.
- Xcode's own build system already caches at a higher level, and Swift 5.9+ has an
  integrated caching mode (`-cache-compile-job`) that uses a CAS internally. The right
  integration, as with Go, is the tool's own protocol, not a wrapper.

## 4. javac / kotlinc

Also unwrapped, for a different reason: **the build system already owns caching.** Gradle's
build cache and Bazel's action cache both key on (task inputs, classpath, compiler version)
and store the task's outputs. Wrapping `javac` under them would be redundant and, worse,
would key on a command line that Gradle constructs from a classpath that is itself content-
addressed.

The shape is still worth noting because it is the *generic* shape (§6): `javac` takes many
inputs and produces many `.class` files in an output directory, so the "one source, one
object" model does not apply at all. A generic mode that declares `inputs = <globs>` and
`outputs = <directory>` covers it, with the caveat that a directory output needs a
deterministic listing to be cacheable.

## 5. protoc, codegen, and clang-tidy

These are the cases where a *generic* mode earns its keep.

**protoc**: `protoc -I<dir> --cpp_out=<dir> a.proto` reads `a.proto` plus every `import`ed
`.proto` (a transitive include set resolved along `-I`, exactly like C's), and writes a
fixed set of files derived from the input's name (`a.pb.cc`, `a.pb.h`). It has a
dependency-output flag, `--dependency_out=<file>`, which emits a **Makefile-format dep
file** — so the C include-manifest machinery applies verbatim. Key = (protoc identity,
argv, source content, dep-derived include manifest). Outputs = derived siblings in
`--*_out`. A protoc rule is therefore expressible with *exactly* the gcc primitives minus
the preprocessor step.

**clang-tidy**: its "output" is its diagnostics. buildcache ships a Lua example for exactly
this (`lua-examples/clang_tidy_wrapper.lua`) and a C++ `ccc_analyzer_wrapper.cpp` and
`cppcheck_wrapper.cpp`. The build-files map can be empty; what is cached is
stdout + stderr + exit code. This is the cleanest demonstration that **stderr and the exit
code must be first-class cached artifacts, not an afterthought attached to a file.**
clang-tidy's inputs are the source plus its include set plus the `.clang-tidy`
configuration files found by walking parent directories — those config files are *implicit
inputs discovered by search*, which no argv classification can find. A rule language needs
an "extra files to hash" escape hatch (ccache has one: `extra_files_to_hash`, whose failure
mode is its own statistic, `error_hashing_extra_file`).

**Linkers.** ccache does not cache links (`called_for_link` is a bypass reason).
sccache does not either. Reasons:
- The inputs are large (every `.o` plus every `.a`/`.so`), so hashing them costs a
  meaningful fraction of what linking costs.
- The output is large, so storing and fetching it may exceed the link time.
- Hit rate is near zero in practice: a link's key changes whenever *any* object changes,
  which is the common case — you almost never re-link identical inputs, because if the
  inputs were identical you would not have re-run the link.
- `-flto` makes the link *the* expensive step, but also makes it depend on every object's
  bitcode.

**Bazel does cache links**, and this is not a contradiction: Bazel's remote cache is
generic over actions, so linking is cached for free by the same machinery as everything
else, and its inputs are already content-addressed in the CAS (so "hashing the inputs" is
free — they were uploaded as a Merkle tree anyway). The cost model that makes link caching
a bad deal for a wrapper does not apply to a system that has already paid it.

## 6. The generic action model (Bazel REAPI)

Bazel's Remote Execution API (Apache-2.0;
`build/bazel/remote/execution/v2/remote_execution.proto`) defines an action as:

```
Action {
  command_digest       -> Command { arguments[], environment_variables[], output_paths[],
                                    platform, working_directory }
  input_root_digest    -> Directory (a Merkle tree of files + symlinks + subdirs)
  timeout, do_not_cache, salt, platform
}
ActionResult {
  output_files[], output_directories[], output_symlinks[],
  exit_code, stdout_digest/stdout_raw, stderr_digest/stderr_raw,
  execution_metadata
}
```

The **Action digest is the cache key**, and it is a SHA-256 over the serialised `Action`
proto, which transitively covers the command, the environment, and the *exact content of
every input file*. Everything else is a CAS lookup.

Properties that follow, and that a wrapper does **not** get for free:

- **Inputs are stated, not discovered.** Bazel knows the input set because the BUILD rule
  declared it. A wrapper has to *discover* it (preprocessor, dep file, `-H`, `/showIncludes`),
  which is the entire source of the direct-mode/manifest complexity in §c-cxx.
- **Hermeticity is assumed.** Anything not in the input root is not visible, so there is no
  `CPATH`-style hidden input and no cwd leakage — `working_directory` is part of the
  Command.
- **stdout, stderr and exit_code are in the result by construction**, not bolted on.
- `output_paths` are declared up front, so "which files did this produce" is never a guess.
- `do_not_cache` and `salt` are explicit escape hatches — the equivalents of ccache's
  bypass verdicts and `CCACHE_RECACHE`.

**A "generic" mode for api-cache** would therefore be: the user declares, in XML,

- the command (argv template),
- the **input set**: literal paths, globs, and/or "derived from a dep file the tool emits",
- the **output set**: literal paths, derived paths (`<input>.pb.cc`), and/or directories,
- an **environment allowlist** (never a denylist — see below),
- optionally a `working_directory` normalisation.

and the key is `hash(tool identity, argv after classification, sorted (relpath, digest)
for every input, sorted env allowlist, normalised cwd)`.

**Allowlist, not denylist.** Bazel's `environment_variables` field is an allowlist of what
the action sees; ccache is a denylist-of-bypasses plus a small allowlist of hashed
variables, and that combination is why `CPATH` had to be discovered and added by hand, and
why `DEPENDENCIES_OUTPUT` is a bypass rather than a hash input. A new engine should default
to "the environment is not an input unless declared", and make the rule file state the
allowlist.

## 7. Dep files versus Merkle trees: the comparison

| | make-style dep file (gcc `-MD`, rustc `--emit=dep-info`, protoc `--dependency_out`) | Bazel input root |
|---|---|---|
| Produced | **after** the action runs | **before**, by the build system |
| Completeness | only as complete as the tool reports (gcc's `#pragma once` content-dedup omits files — see `c-cxx-gcc-clang.md` §3) | total, by construction |
| First build | no dep info exists → must preprocess, or run and learn | always available |
| Key derivation | needs a *second* mechanism (preprocessor mode, or manifest-with-candidates) to bootstrap | one hash |
| Handles a **new** include appearing | manifest validation must miss, then fall through | a different input root → a different key, automatically |
| Handles a **removed** include | the file is gone → stat fails → miss (correct) | different key |
| Cost | one extra tool run per miss (preprocess) or nothing (depend mode) | the build system already paid it |
| Escaping | ad-hoc Makefile escaping, divergent per tool (see the escaping table in `c-cxx-gcc-clang.md` §8) | none; it is a proto |

The practical reading: a wrapper is a **dep-file world**, and the manifest-with-multiple-
candidates is the necessary consequence of learning the input set *after* the fact. Any
design that tries to skip the manifest must either (a) preprocess on every lookup
(preprocessor mode — correct, slow) or (b) trust a stale dep file (depend mode — fast,
incomplete).
