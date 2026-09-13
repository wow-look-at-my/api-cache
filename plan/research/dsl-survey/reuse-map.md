# Reuse map — where each api-cache capability can come from

Verdict codes:
**AS-IS** — call the existing exported API unchanged.
**PATTERN** — copy the shape of an existing file; write new code.
**IMPORT** — import an existing Go package as a library.
**NEW** — nothing in the family does this; build it.

Everything here is about code reuse. Build/CI tooling is out of scope and is not treated as a
constraint anywhere in this file.

---

## 1. The table

| # | Capability | Verdict | Source | Notes |
|---|---|---|---|---|
| 1 | Parse an XML config into an order-preserving DOM | **AS-IS** | `apidsl.ParseDOM` (`api-dsl/dom.go:71`) | Also gives BOM/XML-1.1-declaration stripping (`dom.go:130`), duplicate-attribute rejection (`:92`), namespace-decl skipping (`:88`). |
| 2 | Reject the wrong root element | **PATTERN** | `api-cli/xmlsource.go:22-24`; `api-mirror/load.go:37-39` | api-dsl deliberately does not do this (`dom.go:67-70`). Three lines. |
| 3 | Reject a typo'd attribute | **AS-IS** | `apidsl.CheckAttrs` (`api-dsl/dom.go:152`) | Call it first in every builder. It is the only defence against a silently unread attribute. |
| 4 | Reject an unknown child element | **PATTERN** | the `default:` arm of every child switch, e.g. `api-cli/xmlsource.go:401-403`, `api-mirror/load.go` | One line per builder. |
| 5 | `<value>`/`<if>`/`<for>` placeholders → template source | **AS-IS** | `apidsl.CompileContent` (`api-dsl/compile.go:24`), `CompileTextElem` (`:30`), `TextOf` (`:40`), `IsPlaceholder` (`:14`) | The compiled forms are a frozen contract (`api-dsl/compile_test.go:20-46`). |
| 6 | Compile a consumer's own path-valued attribute | **AS-IS** | `apidsl.DotPath` (`api-dsl/compile.go:61`) | Exported for exactly this and **used by neither existing consumer** — both resolve paths at run time instead. |
| 7 | Render a template | **AS-IS** (with a caveat) | `apidsl.NewRenderer(...).Render` (`api-dsl/render.go:42`, `:66`) | **Caveat: ~62-87 µs and ~44 KB per call, nothing cached.** See `template-runtime.md` §3. For a per-compile wrapper, add a parse cache in the consumer or in api-dsl. |
| 8 | Add consumer template helpers | **AS-IS** | `apidsl.NewRenderer(extra...)` (`api-dsl/render.go:42`) | The stated extension point. `api-cli/render.go:28-47` is the model. Never mutate `FuncMap()`. |
| 9 | Truthiness for a predicate | **AS-IS** | `apidsl.Truthy` / `IsTruthy` (`api-dsl/render.go:116`, `:101`) | `truthy` must be in the func map or `<if test=>` fails to execute. |
| 10 | Dotted-path lookup into decoded JSON | **AS-IS** *or* **IMPORT** | `apidsl.LookupPath` (`api-dsl/render.go:132`) — maps only, **no slice indexing**; or `fields.Lookup` (`api-cli/fields/types.go:46`) — maps by key **and lists by index** | api-cli needed the second and wrote it. |
| 11 | Process environment as a template namespace | **AS-IS** | `apidsl.EnvMap` (`api-dsl/render.go:89`) | Returns `map[string]string`, so a missing key renders `""` not `<no value>`. |
| 12 | Merge inherited vars | **AS-IS** | `apidsl.MergeVars` (`api-dsl/render.go:153`) | Shallow, child wins, fresh map. Only needed if vars inherit down a tree. |
| 13 | `<vars><var>` with cross-references | **PATTERN** — pick one | simple: `api-mirror/engine.go:113-124` (12 lines, declaration order, one pass); full: `api-cli/build.go:441-475` + `resolveContext` `:408-430` (fixpoint, two passes, capped at 10) | api-mirror's is enough when there are no flags to feed back in. |
| 14 | Arbitrary author-keyed structured data in the config | **PATTERN** | `api-cli` `<entry>`: `buildEntry`/`entryValue` (`xmlsource.go:532-595`) → `json.RawMessage`, then `renderEntry`/`walkEntry` (`render.go:382-431`) | ~110 lines total. Renders every string leaf, never a key, sorts keys for determinism. |
| 15 | Run a subprocess with a rendered argv | **PATTERN** | `api-cli/exec.go`: `resolveArgv` (`:279`), `buildExecCmd` (`:263`), `doExec` (`:35`), `captureExec` (`:71`), `captureExecTo` (`:111`), `captureExecCapped` (`:144`) | Four capture modes differing only in where stdout/stderr/stdin go. `resolveArgv` is split out precisely so a caller can render in one place and execute in another (`:271-278`). |
| 16 | Shell form vs argv form of a command | **PATTERN** | `Cmd` (`api-cli/config.go:255-304`); `buildRun` (`xmlsource.go:123-163`) | `<run>` text → `/bin/sh -c`; `<argv>` children → direct exec. |
| 17 | Splat a list into N argv slots | **PATTERN** | `spread` (`api-cli/render.go:243`), `expandSpreadForShell` (`exec.go:319`), the consumption in `resolveArgv` (`exec.go:296-304`) | NUL/SOH sentinels. An empty spread contributes **no** argument, which is how a conditional argument is written. |
| 18 | Filter an argv list by prefix/suffix | **PATTERN** | `filterSuffix`/`filterPrefix` (`api-cli/render.go:304`, `:319`) | The doc comment already names the compiler-wrapper case: `{{.rest \| filterSuffix ".cpp1.ii" \| first}}`. |
| 19 | Accept an arbitrary trailing command line | **PATTERN** | `passthrough="true"` + `passthroughParse` (`api-cli/flags.go:204-316`) | Recognises declared flags only, one **or two** leading dashes, `=` and next-arg forms; everything else into `.rest`; bare `--` and after goes in verbatim. This is the closest thing in the family to a compiler-wrapper front end. |
| 20 | Validate a value against a regex | **PATTERN** | `<arg pattern=>`: `validateRunnable` (`api-cli/runnable.go:352-393`), `argPatterns` (`:397`), `matchArgPatterns` (`:411`) | The only regex-driven classification in the language. Patterns are compiled **once at load**, not per call. |
| 21 | Shell-quote a value | **AS-IS** (copy 1 func) | `shellQuote` (`api-cli/render.go:371`) | Three lines. |
| 22 | HTTP request with rendered URL/query/headers/body | **PATTERN** | `api-cli/request.go`: `prepareRequest` (`:100`), `doHTTP` (`:139`), `buildRequestQuery` (`:185`), `renderHeaders` (`:219`); grammar in `xmlrequest.go:384-449` | Only needed if api-cache talks to a remote cache over a declared HTTP shape rather than a fixed client. |
| 23 | `curl -f` semantics + allow-listed error statuses | **PATTERN** | `doHTTP` (`api-cli/request.go:168-178`), `parseAllowStatus` (`xmlrequest.go:361-382`) | |
| 24 | **A program stands in for a built-in mechanism** | **PATTERN** | the whole of `api-cli/transport.go` (244 lines) | The single most transferable design. See §2. |
| 25 | Defer rendering so a worker can execute later | **PATTERN** | `prepareDownloadTransport` (`api-cli/transport.go:155-181`) + `downloadTransport` (`:140-145`) | "nothing here may still need rendering." Exactly the shape for handing work to a pool. |
| 26 | Sequential pre-stages whose output feeds later templates | **PATTERN** | `api-cli/steps.go` (283 lines): `runSteps` (`:44`), `runStepOnce` (`:187`) | `.result.<name>` = `parseResult(stdout)`. The caller injects a `stepCapture` closure (`:20-23`), which is how two hosts share one loop. |
| 27 | Repeat a stage per element (`over=`) | **PATTERN** | `runStepOver` (`api-cli/steps.go:237-274`) + `overSource` (`render.go:138`) + `asList` (`:77`) | Result is a list of `{item, result}` pairs. Missing path ≠ empty list ≠ non-list — three distinct errors. |
| 28 | Poll until a predicate holds (`until=`) | **PATTERN** | `runStepAction` (`api-cli/steps.go:101-144`), `pollContext` (`:149`), `pollInterval` (`:154`), `validatePoll` (`:170`) | Fixed interval, capped attempts, non-zero exit ends the poll, exhaustion names the last body. `pollSleep` is a package var for tests. |
| 29 | Gather one path from every element of a fan-out | **PATTERN** | `collectPath` (`api-cli/render.go:106-128`) | A missing path in one element is an **error**, not a skip. |
| 30 | Conditionals in config content | **AS-IS** | `<if test= eq=>` / `<else/>` via `CompileContent` | Note `<if>` may also be *structural* rather than a placeholder — `api-cli/xmlrequest.go:418-432` uses `<if test=>` as a wrapper whose `test=` becomes a run-time `When` path on each child. |
| 31 | A predicate on a declaration (`when=`) | **PATTERN** | a plain template rendered then `isTruthy`'d: `api-cli/steps.go:47-57`, `format.go:127-146`, `renderFieldsBlocks` (`format.go:416-440`) | `when=` is a full template; `test=` is a context path. Do not blur the two. |
| 32 | Load-time validation with actionable errors | **PATTERN** | `api-mirror/validate.go` (the style), `api-cli/config.go:437-745` (the recursion + `where` strings) | See `api-mirror-language.md` §2 for the message standard. |
| 33 | Positional `where` strings in errors | **PATTERN** | `api-cli/config.go:464`, `:586`, `:705` — `commands[0].steps[2].request` | api-dsl carries no source position, so this is the only locator available. |
| 34 | A grammar/XSD | **PATTERN** — three tiers | heavy: `api-cli-spec` (separate module, XSD + resolved form + conformance suite); light: `api-mirror/mirror.schema.xsd` + `schema_xsd_test.go` (name-coverage test only, ~130 lines, no validator dependency); none: `checkAttrs` + child-switch `default:` only | See `api-cli-spec.md` §6. The light tier catches the failure that actually bites (an editor completing a name the loader rejects). |
| 35 | An "effective settings" conformance table | **PATTERN** | `api-cli-spec/resolve.go` (176 lines) + `resolved.xsd` + paired `testdata/*.resolved.xml` | Separable from the XSD question. Valuable for **any** inheritable setting: it writes down the one thing the source document never states. |
| 36 | Docs generation | **PATTERN** | `api-cli/docs.go` — `//go:embed README.md`, `//go:embed api.example.xml`, and `spec.Schema` for the grammar, behind a `docs` subcommand (`:21-54`) | 63 lines. |
| 37 | MCP tool exposure | **PATTERN** | `api-cli/mcp.go` + `mcp_exec.go` (~500 lines), `modelcontextprotocol/go-sdk` (MIT) | **Cost warning:** it is a *second copy* of the leaf runner, and every inheritable field must be threaded twice (`api-cli/CLAUDE.md` rule 1). Only worth it if an agent must drive the cache. |
| 38 | Output formatting for a `stats` / `status` command | **IMPORT** | `github.com/wow-look-at-my/api-cli/fields` — a **standalone importable package** (`api-cli/fields/types.go:1-6`, `docs/fields-package.md`) | Give it decoded JSON + a `Fields` declaration; get a table / list / lines / raw / json / markdown / csv / timeline, default chosen from the data's shape. `Render(r, f, parsed, ctx, sink, width)` (`types.go:35`), and the `Renderer` is injected so the package parses no XML and reads no flag. It also exports the width-aware aligner (`AlignColumns`, `PadRight`, `PadLeft`, `DisplayWidth`, `StripANSI`) usable on its own. |
| 39 | The `<fields>`/`<field>` grammar to drive it | **PATTERN** | `buildFields`/`buildFieldsBody`/`buildField` (`api-cli/xmlsource.go:165-232`), `FieldsBlock` (`config.go:396-399`), `renderFieldsBlocks` (`format.go:416-440`) | ~70 lines of builder. The structs are already the `fields` package's own types, aliased (`config.go:385-388`). |
| 40 | A remote cache client over the org's wire protocol | **IMPORT** | `github.com/wow-look-at-my/go-s3-server/cacheclient` — its own module (`/home/user/go-s3-server/cacheclient/go.mod`), deps limited to lz4, klauspost/compress and go-containers | Covers single GET/PUT, `/_index`, `/_batch/get`, `/_batch/put`, lz4 framing, and the read guards. Deliberately carries no cobra/prometheus so a consumer can vendor it. Diagnostics go to an injected `Logger`, default silence. The storage-protocol survey covers this in depth. |
| 41 | Normalizing JSON numbers for template arithmetic | **PATTERN** | `parseResult` + `normalizeNumbers` (`api-cli/exec.go:218-261`) | `json.Number` → `int64`/`float64` so sprig's `add`/`mul` work uncast. |
| 42 | Test seams for I/O | **PATTERN** | package-level vars: `execStdin`/`execStdout`/`execStderr` (`api-cli/exec.go:15-19`), `httpClient` (`request.go:19`), `pollSleep` (`steps.go:18`), `transports`/`defaultTransport` (`transport.go:20-23`) | `transport.go:16-19` states the justification: config data, one config per process, spares every call site a parameter. |
| 43 | A derived fingerprint that invalidates on config change | **PATTERN** | `api-mirror/schema.go:58-71` — `Fingerprint() = hash(DDL())` | "derived, never declared." Contrast `go-s3-server`'s hand-bumped `currentCacheVersion` constant. |
| 44 | A closed vocabulary of fallback reasons | **PATTERN** | `PassReason` (`api-mirror/router.go:11-22`), `DenyReason` (`reveal.go:20-27`), `Lane` (`observe.go:13-23`) | One comment per constant, no "other". |
| 45 | Grouping fallbacks into actionable families | **PATTERN** | `api-mirror/shapes.go` — `generalize` (`:18`), `generalizeWith` (`:33`) | Turns "this request left" into "this family is still leaving", and attaches the config that would stop it. |
| 46 | Instrumenting every outbound request | **PATTERN** | `observedClient` (`api-mirror/observe.go:82-97`), `reportingBody` (`:152-169`) | In the `RoundTripper`, never at a call site. |

---

## 2. The transport pattern, spelled out

Capability 24 deserves its own note because "a program computes X" is likely central to api-cache
(a preprocessor, a hasher, a compiler probe, a remote-cache fetcher).

The complete mechanism, in `api-cli/transport.go`:

1. **Grammar.** `<transports><transport name= default=>` with children `<run>`, `<cwd>`, `<stdin>`
   (`buildTransports:27-46`, `buildTransport:48-85`). A transport's `<run>` **must be a command**,
   not a request, and the error says why (`:65`).
2. **Registry as package state.** `transports map[string]*Transport` + `defaultTransport string`
   (`:20-23`), published by `installTransports(cfg)` (`:90-103`) from every activation path. The
   justification is written down at `:16-19`.
3. **Selection: explicit → registry default → built-in.** `resolveTransportNamed` (`:118-134`). The
   name `http` is **reserved** for the built-in (`:14`), which is the per-call way back to it.
   **No runtime override**, deliberately (`:109-110`).
4. **A uniform rendered payload.** `preparedRequest` (`request.go:24-31`) is produced once and fed to
   either path, so the built-in and the program see an identical request.
5. **A context namespace for the program.** `preparedRequest.context(data)` (`:225-243`) layers
   `.request.{method,url,body,headers,header_lines}` over the leaf's context, so the program's argv
   uses the same placeholders as any other command.
6. **A stated I/O contract.** stdout is the result; a non-zero exit is a failure; stderr passes
   through untouched (`runViaTransport:196-221`). **Stdin is always explicit, never inherited**
   (`:205-211`) — "a program that reads stdin cannot hang waiting for one."
7. **Never a second code path.** Everything downstream of the result is identical
   (`request.go:69-96`). api-cli's CLAUDE.md rule 4 states it as an invariant.
8. **Load-time validation with a named fix.** Unknown name; missing `<run>`; two defaults; and the
   `allow-status` incompatibility whose message names the way out (`config.go:474-525`).
9. **A deferred-execution variant** for a worker that runs long after the context is gone
   (`prepareDownloadTransport:155-181`).

The one adaptation a cache needs: item 6's "stdout is the result" is fine for a small result but
`prepareDownloadTransport`'s sibling `fetchViaTransport` already shows the streaming variant —
"Its stdout streams into the file rather than into a buffered response body ... it is also why a file
larger than memory is fine" (`api-cli/README.md:287`).

---

## 3. What is genuinely new

Nothing in the family does any of the following. They are enumerated with their implications in
`gaps.md`:

- Byte-level content addressing: hashing files, hashing streams, hashing an argv.
- A first-class notion of a **key** derived from inputs.
- A **manifest** of multiple outputs from one action.
- Binary data anywhere in the pipeline (everything in api-dsl and both consumers is `string`).
- Classifying and **rewriting** an argv by declared rules.
- Parsing a compiler's dependency output (`.d` files), or globbing.
- A hot path where a render's 62 µs is a real cost.

`gaps.md`'s **Addendum** carries the detailed evidence on four of these: exactly what
`passthroughParse` and `<flag>` can and cannot express today (arity, exact-match lookup only, no
role, no pattern on a flag, no attached-value short form, silent failure), whether sibling order
survives the DOM and where both consumers already depend on it, the fact that **no include, overlay
or document merge exists anywhere in the family**, and where a binary-safe streaming-and-hashing
capture of a program's stdout already exists (`api-cli/downloader.go:329-431`) versus where a step's
output is trimmed and JSON-decoded before any template sees it (`api-cli/exec.go:218-233`).

---

## 4. Dependency and license summary

| module | license | note |
|---|---|---|
| `wow-look-at-my/api-dsl` | MIT (`/home/user/api-dsl/LICENSE:1`) | 690 source lines; deps: sprig + testify only |
| `wow-look-at-my/api-cli` | MIT (`/home/user/api-cli/LICENSE:1`) | the `fields/` sub-package is importable |
| `wow-look-at-my/api-mirror` | MIT (`/home/user/api-mirror/LICENSE:1`) | `internal/mirror`, so **not importable** — pattern only |
| `wow-look-at-my/api-cli-spec` | MIT (`/home/user/api-cli-spec/LICENSE:1`) | |
| `wow-look-at-my/go-s3-server/cacheclient` | **no LICENSE file in this checkout** (neither at the repo root nor in `cacheclient/`; the four sibling repos all carry MIT) — confirm before depending on it | own go.mod, minimal deps |
| `Masterminds/sprig/v3 v3.2.3` | MIT (`LICENSE.txt`, "Copyright (C) 2013-2020 Masterminds") | arrives transitively through api-dsl; 196 functions |
| `spf13/cobra v1.10.2` | Apache-2.0 | api-cli only |
| `spf13/pflag` | BSD-3-Clause | via cobra |
| `itchyny/gojq v0.12.19` | MIT | api-cli only |
| `stretchr/testify` | MIT | |
| `golang.org/x/term`, `golang.org/x/text` | BSD-3-Clause | via api-cli's `fields` |
| `modelcontextprotocol/go-sdk v1.5.0` | MIT | api-cli only |
| `modernc.org/sqlite v1.57.0` | BSD-3-Clause | api-mirror only |
| `pierrec/lz4/v4`, `klauspost/compress` | BSD-3-Clause / (Apache-2.0 + BSD) | cacheclient only |
| `wow-look-at-my/go-containers` | MIT (same org) | `set.Of` / `set.New[T]` |

**Taking api-dsl alone brings in exactly one third-party transitive dependency tree: sprig.** That is
worth knowing, because sprig is also the source of the 60 µs-per-render cost
(`template-runtime.md` §3) and of every non-deterministic template function
(`template-runtime.md` §10).
