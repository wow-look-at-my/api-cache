# refs — reference repositories

Git submodules the plan, the research and the probes read or build against. Each is pinned to a commit so a citation stays valid.

| Path | Repository | License | Why it is here |
|------|------------|---------|----------------|
| `bin-file-fmt` | wow-look-at-my/bin-file-fmt | MIT | binpazer, the block container evaluated for the result format and the cooked trailer. Probes build against `go/` and `c/`. |
| `buildcache` | bits-n-bites/buildcache | zlib | The closest prior art: Lua wrapper contract, built-in wrappers, direct mode. Code may be adapted. |
| `sccache` | mozilla/sccache | Apache-2.0 | The rustc, MSVC and CUDA decision procedures, the daemon model, the storage backends. Code may be adapted. |
| `ccache` | ccache/ccache | GPL-3.0-or-later | Behavior reference only: argument processing, manifests, sloppiness, the bypass reasons. **No code may be copied from it.** |
| `bazel-remote` | buchgr/bazel-remote | Apache-2.0 | The Bazel HTTP and gRPC cache protocols as implemented, and the disk layout. |
| `remote-apis` | bazelbuild/remote-apis | Apache-2.0 | The REAPI v2 protobuf definitions: Digest, Action, ActionResult, CAS, ByteStream. |

Add one with `git submodule add <url> refs/<name>`. Workflows check out with `submodules: true`.
