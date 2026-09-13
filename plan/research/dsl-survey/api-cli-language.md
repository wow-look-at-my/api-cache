# api-cli — the consumer vocabulary, as built

Module `github.com/wow-look-at-my/api-cli`, Go 1.26, MIT (`/home/user/api-cli/LICENSE:1`).
Package `main` — the whole CLI is one flat package: **27 non-test source files, 8,767 lines**, plus
the importable `fields/` sub-package (5 files, 1,064 lines).

Key dependency licenses (from go.mod, `/home/user/api-cli/go.mod`):
cobra Apache-2.0, sprig/v3 MIT, gojq MIT, testify MIT, `golang.org/x/term`/`x/text` BSD-3-Clause,
modelcontextprotocol/go-sdk MIT, bubbletea MIT, api-dsl/api-cli-spec/tml/go-containers/ascii-timeline
all MIT (same org).

---

## 1. The api-dsl boundary: `dsl.go` (25 lines, read it in full)

`/home/user/api-cli/dsl.go:11-25`:

```go
type xnode = apidsl.Node        // a type ALIAS, not a new type
var (
	parseDOM        = apidsl.ParseDOM
	checkAttrs      = apidsl.CheckAttrs
	compileContent  = apidsl.CompileContent
	compileTextElem = apidsl.CompileTextElem
	textOf          = apidsl.TextOf
	isPlaceholder   = apidsl.IsPlaceholder
	envMap          = apidsl.EnvMap
	lookupPath      = apidsl.LookupPath
	mergeVars       = apidsl.MergeVars
	isTruthy        = apidsl.IsTruthy
	templateTruthy  = apidsl.Truthy
)
```

Everything else in the package calls the short names. **Exactly one file imports api-dsl for the
DOM** (`render.go:16` also imports it, for `NewRenderer`). Note what is *not* aliased: `DotPath`,
`RenderString`, `FuncMap`, `Renderer`, `Truthy`(→ renamed `templateTruthy`). api-cli never calls
`apidsl.DotPath` — its path-valued attributes (`when=`, `over=`, `test=` on a `<query><if>`) go
through `fields.Lookup`/`lookupPath` at run time instead of being compiled to template source. That
is a notable divergence from what api-dsl's `DotPath` doc comment suggests.

**This is the entire integration surface a new consumer needs to copy.** api-cache should write the
same file.

---

## 2. Load pipeline

`Load(path)` (`config.go:420-435`):

```
os.ReadFile → parseConfigXML(raw) → validate(cfg) → cfg.Dir = filepath.Dir(path)
```

`parseConfigXML` (`xmlsource.go:17-26`) is three lines: `parseDOM(src)`, check
`root.Name() != "config"` — **the root check the shared module refuses to do** — then `buildConfig`.

The split is the same one api-mirror names explicitly: **builders check shape, validate checks
meaning.** `xmlsource.go`/`xmlrequest.go`/`transport.go`/`download.go`/`join.go`/`tmlview.go` hold
`build*` functions; `config.go` holds `validate`/`validateCommand`/`validateRequest`/`validateFormat`
/`validateTransports`/`validatePoll`(in steps.go)/`validateRunnable`(runnable.go)/`validateDownloads`
/`validateTML`.

Every builder opens with `checkAttrs(n, ...allowed)` and every `default:` in a child-dispatch switch
returns `unexpected child element <%s>`. That pair is the entire "typo catching" mechanism. Examples:
`buildConfig` (`xmlsource.go:29`, `:92-94`), `addCommandChild` (`:401-403`), `buildRequest`
(`xmlrequest.go:385`, `:444-446`), `buildTransports` (`transport.go:28`, `:33-35`).

---

## 3. The full element vocabulary

### Top level — `<config name= schema=>` (`xmlsource.go:28-97`)

| child | builder | struct field |
|---|---|---|
| `<description>` | `textOf` | `Config.Description` |
| `<vars>` | `buildVars` `:99` | `Config.Vars map[string]any` |
| `<run>` | `buildRun` `:123` | `Config.Command *Cmd` **or** `Config.Request *Request` |
| `<cwd>` / `<stdin>` | `compileTextElem` | template strings |
| `<formats>` | `buildFormats` `:234` | `map[string]*Format` |
| `<transports>` | `buildTransports` (`transport.go:27`) | `map[string]*Transport` |
| `<downloads>` | `buildDownloads` (download.go) | `*Downloads` |
| `<command>` | `buildCommandNode` `:279` | `[]Command` |

`schema=` is accepted and ignored at load (`buildConfig:32`) — it is an editor hint at the XSD
(README:789).

### `<command>` (`xmlsource.go:279-405`)

Attributes: `name`, `description`, `passthrough`, `runnable`, `confirm` (`:280`).
Children dispatched by `addCommandChild` (`:299-405`): `arg`, `flag`, `vars`, `run`, `cwd`, `stdin`,
`confirm`, `preconditions`, `steps`, `entry`, `fields`, `tml`, `format`, `download`, `command`.

### `<arg>` (`buildArg`, `:407-419`)
`name`, `type` (`string|int`, `config.go:410`), `required`, `variadic`, `pattern`, `description`.
Validation (`validateCommand:585-605`): name required, type in set, no duplicate name, variadic must
be last, **a required arg cannot follow an optional one** (`:602-604`).

### `<flag>` (`buildFlag`, `:421-463`)
`name`, `short`, `type` (`string|bool|int|string-slice`), `default`, `required`, `conflicts`
(comma-split, `:432-438`), `description`. `HasAttr("default")` distinguishes absent from empty
(`:439`), and the default is typed per `type=` at load. Validation (`:609-644`): unique name, unique
single-char short, **name may not start with `no-`** (reserved for bool negation, `:630-632`),
conflicts must name a declared sibling and not itself.

### `<run>` (`buildRun`, `xmlsource.go:123-163`) — the three forms

```go
// 1. <request> must be the only child
for _, e := range elems { if e.Name() == "request" { if len(elems) != 1 { err } ... } }
// 2. any <argv> => all children must be <argv>; each compileTextElem'd into one argv slot
// 3. otherwise: compileContent(n) of the whole <run>, TrimSpace'd, Shell=true
```

`Cmd` (`config.go:255-259`) is `{Shell bool; Template string; Argv []string}` and `Defined()` is
`c != nil && (c.Shell || len(c.Argv) > 0)` (`:299-304`). `Request.Defined()` is a non-blank URL
(`:353-355`).

### `<steps><step>` (`buildStep`, `:465-514`)
Attributes: `name`, `when`, `over`, `until`, `interval`, `attempts` (`:466`).
Children: `run`, `entry`, `cwd`, `stdin` (`:483-512`).

### `<entry>` (`buildEntry`, `:532-595`) — the interesting one
An `<entry>` becomes a `json.RawMessage` whose **string leaves are template source**. `entryValue`
(`:559-594`) decides per element:
- no structural (non-placeholder) children → `compileContent(n)`, a template string;
- all structural children are `<param>` → a `map[name]templateString`;
- otherwise → a nested object keyed by child element name.

`renderEntry` (`render.go:382-431`) later walks the JSON and renders every string leaf, sorting
object keys for determinism (`:404-409`). Object **keys are never rendered** (`:378`).
This is api-cli's mechanism for "arbitrary user-defined structured data in the config" and it is
directly reusable.

### `<request>` (`xmlrequest.go:384-449`)
Attributes: `method`, `transport`, `allow-status`. Children: `url`, `query`, `header`, `if`, `body`,
`response`.
`<if test=>` inside a `<request>` is **not** an api-dsl placeholder — it is a structural element
whose only allowed children are `<header>` (`:418-432`), and `test=` is stored on each header as
`Header.When`, a **context path** evaluated at run time with `templateTruthy(lookupPath(data, when))`
(`request.go:222`). Same for `<query><if>` around `<param>` (`xmlrequest.go:479-493`).
`<response jq=>` (`:439-443`).

### `<transports><transport>` (`transport.go:27-85`)
`<transport name= default=>` with children `run` (must be a command, `:64-67`), `cwd`, `stdin`.
`StdinSet` (`config.go:348`) distinguishes `<stdin/>` (send nothing) from no `<stdin>` (send the
body).

### `<fields when=>` / `<field>` (`xmlsource.go:165-232`)
`<fields over= footer= when=>`; `<field name= default= truncate= firstline= priority= show_in=
expr=>` with the body as the record-relative path. A field takes a path **or** `expr=`, never both
and never neither (`:211-216`).

### `<formats><format>` / `<view>` (`:234-277`), `<format ref=>` (`buildFormatRef`, `:516-528`).
### `<download>`, `<join>`, `<tml>`, `<prop>` — see `download.go`, `join.go`, `tmlview.go`.

---

## 4. Inheritance — the rule and both code paths

`buildCommand` (`build.go:40-145`) threads seven inheritable things down the tree: **vars, run
(`*Cmd` OR `*Request`), cwd, stdin, confirm, format**, plus the constant `formats` registry.

The clearing rule (`build.go:96-105`):

```go
effectiveVars := mergeVars(inheritedVars, node.Vars)      // child wins per key
effectiveCmd, effectiveRequest := inheritedCmd, inheritedRequest
if node.Request.Defined() {
	effectiveRequest, effectiveCmd = node.Request, nil     // a request CLEARS an inherited command
} else if node.Command.Defined() {
	effectiveCmd, effectiveRequest = node.Command, nil     // and vice versa
}
```

cwd/stdin/confirm/format each take `if node.X != "" { effective = node.X }` (`:106-121`) — closest
non-empty ancestor wins.

**The same threading exists twice.** `collectMCPLeaves` (`mcp.go`, driven by `mcpInherit`
`mcp.go:70-80`) is the second copy. CLAUDE.md rule 1 says a new inheritable field needs both paths.
This duplication is a known cost of the design, and is worth noting for api-cache: if there is only
one execution path (a wrapper has no MCP twin), the cost disappears.

---

## 5. The data context — every path that exists at render time

Built in `runLeafOnce` (`build.go:218-364`) and `resolveContext` (`:408-430`):

| path | where it is set | notes |
|---|---|---|
| `.arg.<name>` | `gatherArgs` (`flags.go:92-133`) | typed per `<arg type=>`; **every declared arg is present**, omitted ones hold `zeroArg` (`flags.go:137-148`): `""`, `0`, `[]string{}`, `[]int{}` |
| `.flag.<name>` | `gatherFlags` (`flags.go:158-196`) | typed; bool honours the hidden `--no-NAME`; a string default containing `{{` renders against the pre-flag context when the user did not set it (`:168-176`) |
| `.env.<VAR>` | `envMap()` = `apidsl.EnvMap()` | a `map[string]string`, so a missing key renders `""` not `<no value>` |
| `.var.<name>` | `renderVars` fixpoint (`build.go:441-475`) | see §6 |
| `.rest` | `passthroughParse` (`flags.go:204-316`) | passthrough mode only; `[]string` |
| `.result.<step>` | `runSteps` (`steps.go:89`) | `parseResult(out)` — decoded JSON or the raw trimmed string |
| `.entry` | `renderEntry` (`build.go:320-327`; per-step at `steps.go:188-195`) | |
| `.item` / `.index` | `runStepOver` (`steps.go:260`), `<download over=>` | saved and **restored** afterwards (`steps.go:251-256`, `restore` `:277-283`) |
| `.body` / promoted keys | `pollContext` (`steps.go:149-151`) → `promoteCtx` (`render.go:156-168`) | only inside a `until=` predicate |
| `.request.{method,url,body,headers,header_lines}` | `preparedRequest.context` (`transport.go:225-243`) | only inside a transport program's argv/cwd/stdin |
| `.run.tmpdir` | `openScratch` (`downloadrun.go`) | only on a `<download>` leaf |
| `.data`, `.tty`, `.width` | `formatContext` (`format.go:111-121`) | only in a format/view/fields predicate or a `<view>` template |
| `$` | text/template's root | in a `<field expr=>` the record is promoted and `$` is the whole context (README:726) |

Note `.result` is installed **before** the steps run (`build.go:302-303`), so it exists as an empty
map for a `<step when=>` on the first step.

---

## 6. Vars: the two-pass + fixpoint resolution

`resolveContext` (`build.go:408-430`) — the outer two passes:

```
pass 1: base + flag={} → renderVars → preFlag["var"]   // feeds a templated <flag default=>
gather(preFlag)                                        // cobra + templated defaults
pass 2: base + flag=<finished map> → renderVars        // this is the .var everything downstream sees
```

`renderVars` (`build.go:441-475`) — the inner fixpoint:
JSON-marshal the *original* var templates once (`:447`), then up to `maxVarPasses = 10` (`:433`)
iterations of `renderEntry(raw, ctx)` with `ctx["var"] = <previous pass>`. Stop when
`varsEqual` (JSON identity, `:478-485`) holds. **The original templates are re-rendered each pass**,
so resolved text is never double-processed (`:437-439`). No cycle detection — a cyclic var simply
runs 10 passes and returns whatever it has.

Both the CLI path and the MCP path go through `resolveContext` (`mcp_exec.go:20-22`).

---

## 7. The steps engine (`steps.go`, 283 lines) — the pattern to copy

`runSteps(steps, data, results, cmdTmpl, request, cwdTmpl, stdinTmpl, capture, errOut)`
(`steps.go:44-92`). Note the shape: **the caller supplies a `stepCapture` closure and an error
writer**, which is how the CLI and MCP share one loop (`steps.go:20-23`):

```go
type stepCapture func(c *Cmd, cwd, stdin string, data any) (string, int)
```

CLI passes `captureExec` (`build.go:305`); MCP passes a closure over `captureExecTo` with a private
stderr buffer (`mcp_exec.go:49-52`).

Per step, in order:
1. **`when=`** — `renderString(step.When, data)` then `isTruthy` (`:47-57`). A falsy render `continue`s
   and `.result.<name>` **stays unset**. The `when` is evaluated before anything else in the step
   renders, so a step that must not run cannot fail on a value it never had (README:664).
2. **Run selection** (`:59-68`): the step's own `<request>` wins, then its own command, else the
   leaf's effective run inherited from the caller. Declaring neither and having neither is an error.
3. **`over=`** → `runStepOver` (`:237-274`); else `runStepAction` (`:101-144`).
4. On a non-zero code: `oc.output, oc.code = out, code` and **return immediately** — the leaf's own
   run never happens (`:85-88`).
5. On success: `results[step.Name] = parseResult(out)` (`:89`).

### `runStepAction` — the poll loop (`:101-144`)
Without `until=`: one `runStepOnce`, `oc.executions++`.
With `until=`: up to `attempts` (default `defaultPollAttempts = 60`, `:13`) iterations. Each
iteration runs, counts, **returns immediately on a non-zero exit** (`:126-128` — "a job that reports
a failure is an answer"), parses the body, renders `step.Until` against `pollContext(data, last)` and
stops when truthy. Between attempts `pollSleep(interval)` — a package var so tests cost no real
seconds (`:16-18`). Exhaustion is an error naming the last body (`:142-143`).
`pollInterval` default `time.Second` (`:12`, `:154-166`); `validatePoll` (`:170-184`) rejects
`interval=`/`attempts=` without `until=`, a negative `attempts`, and a bad duration — **at load
time**.

### `runStepOnce` (`:187-225`)
Renders the step's `<entry>` into `data["entry"]` (note: **mutates the shared data map**, `:195`),
then either `runRequest` or renders cwd/stdin and calls `capture`.

### `runStepOver` (`:237-274`)
`overSource(data, step.Over)` → `asList` → per element set `data["item"]`/`data["index"]`, run,
collect `{"item": element, "result": parseResult(out)}`. Missing path and non-list are two distinct
errors (`:242-248`). Item/index are restored with a `defer` (`:251-256`).

**Result shape is a list of pairs, not two parallel lists** — the comment at `:230-233` is the
design argument.

---

## 8. Transports — "a program stands in for the built-in mechanism"

This is the single most transferable pattern in the repo for api-cache.

- **Registry.** `<transports><transport name= default=>` parsed by `buildTransports`
  (`transport.go:27-46`), held in **package-level vars** `transports` and `defaultTransport`
  (`:20-23`) with a stated justification: config data, one config per process, mirrors how
  `httpClient` and `execStdout` are held, and it spares every call site a parameter
  (`:16-19`). Published by `installTransports(cfg)` (`:90-103`), called by both `newRoot` and
  `buildMCPServer` (`mcp.go:97`).
- **Selection** (`resolveTransportNamed`, `:118-134`): explicit `transport=` → registry
  `default="true"` → built-in (a `nil` return). The name `http` is reserved
  (`builtinTransportName`, `:14`) as the per-request way back to the built-in client. **There is
  deliberately no runtime override** (`:109-110`): "How a request reaches its endpoint is a property
  of that endpoint, not a user preference."
- **The contract.** The program's **stdout is the response body**; a non-zero exit is a failed
  request; its stderr passes through untouched (`runViaTransport`, `:196-221`).
- **What the program sees.** `preparedRequest.context(data)` (`:225-243`) layers
  `.request.{method,url,body,headers,header_lines}` on top of the leaf's context, so the program's
  argv uses the same placeholders as any other command.
- **Stdin is explicit, never inherited** (`:205-211`, and `captureExecTo` `exec.go:107-110`): "a
  program that reads stdin cannot hang waiting for one."
- **A transport is never a second code path.** CLAUDE.md rule 4. `prepareRequest` produces the same
  `preparedRequest` either way; `<response jq=>` and `<fields>` run identically on the result
  (`request.go:69-96`).
- **Deferred rendering for a worker.** `prepareDownloadTransport` (`:155-181`) renders the argv/cwd/
  stdin **at plan time** into a plain `downloadTransport{Name, Argv, Cwd, Stdin}` (`:140-145`),
  because "the queue executes this on a worker long after the leaf's data context is gone, so nothing
  here may still need rendering." That is exactly the shape a cache-miss worker would need.
- **Validation** (`config.go:474-503`): every transport needs a `<run>` command; at most one
  `default="true"`; the name `http` is reserved; `validateRequest` (`:507-525`) rejects an unknown
  `transport=` and rejects `allow-status` + a named transport with an error that names the fix.

---

## 9. Execution (`exec.go`) — four capture modes and `resolveArgv`

| function | line | stdout | stderr | stdin |
|---|---|---|---|---|
| `doExec` | `exec.go:35` | streams to `execStdout` | `execStderr` | rendered string, else **inherits** `execStdin` |
| `captureExec` | `:71` | buffered, returned | `execStderr` | same |
| `captureExecTo` | `:111` | buffered | caller's `errOut` | **always** the rendered string, never inherited |
| `captureExecCapped` | `:144` | buffered to `maxBytes` then falls through to streaming | `execStderr` | same as doExec |

`cappedTee` (`:189-211`) is the buffer-then-stream writer. `defaultFormatCap = 32 << 20`
(`format.go:15`).

`resolveArgv(c, data)` (`:279-311`) is the render→argv function, split out precisely so a caller can
render where the context exists and execute elsewhere:

```go
if c.Shell { rendered := renderString(c.Template, data); return []string{"/bin/sh","-c", expandSpreadForShell(rendered)} }
// argv form: render each element; an element that begins with the spread sentinel expands into N argv slots
```

`parseResult(s)` (`:218-233`): strict single-value JSON decode with `UseNumber`; anything trailing or
a decode error yields the trimmed raw string. `normalizeNumbers` (`:238-261`) rewrites `json.Number`
to `int64`/`float64` so sprig arithmetic works without casts. gojq output goes back through the same
path (CLAUDE.md gotcha).

Exit codes: `exec.ExitError` code passes through; a start failure is 127; a render error is 1
(`:56-65`).

Test seams: `execStdin`/`execStdout`/`execStderr` are package vars (`exec.go:15-19`); so are
`httpClient` (`request.go:19`), `downloadClient`, `pollSleep` (`steps.go:18`), `isInteractive`
(`build.go:23`), `ttyOverride` (`format.go:84`), `transports`/`defaultTransport`
(`transport.go:20-23`). CLAUDE.md rule 14: a test that swaps one calls `t.Serial()` first.

---

## 10. `cliFuncs` — the consumer's template helpers, one line each

`render.go:28-43`. The renderer is built once: `var renderer = apidsl.NewRenderer(cliFuncs())`
(`render.go:47`), and `renderString(tmpl, data)` is `renderer.Render(...)` (`:170-172`).

| name | impl | one-line meaning |
|---|---|---|
| `shellquote` | `render.go:371` | POSIX single-quote a value: `'` → `'\''` |
| `spread` | `:243` | splat a slice into N argv slots; emits `\x00a\x00b\x01` sentinels |
| `fileExists` | `:285` | path exists and is a regular file; any error reads as false |
| `dirExists` | `:294` | path exists and is a directory |
| `tabwriter` | `:180` | align rows of tab-separated cells, display-width aware, 2-space gutter |
| `padRight` | = `fields.PadRight` (`:54`) | pad to a display width on the right |
| `padLeft` | = `fields.PadLeft` | pad on the left |
| `displayWidth` | = `fields.DisplayWidth` | terminal columns a string occupies (East-Asian wide aware) |
| `stripANSI` | = `fields.StripANSI` | remove ANSI escapes |
| `filterSuffix` | `:304` | keep the `[]string` elements ending in a suffix |
| `filterPrefix` | `:319` | keep the elements starting with a prefix |
| `collect` | `collectPath`, `:106` | gather one dotted path from every element of a list, flattening list values; **a missing path is an error, not a skip** |

Note `filterSuffix`'s own doc comment (`render.go:302-303`) names the compiler-wrapper use case
outright: *"Used in passthrough mode to locate specific files: `{{.rest | filterSuffix ".cpp1.ii" | first}}`."*

### `asList` / `overSource` / `promoteCtx`

- `asList(v)` (`render.go:77-95`): `[]any` passes through; **a string or `[]byte` is explicitly NOT a
  list** (`:82-84`, "iterating one gives a record per byte"); any other slice/array is reflected into
  `[]any`. This is what makes `over=` accept both a JSON result and a variadic arg's `[]string`.
- `overSource(data, expr)` (`:138-151`): **no `{{` → a context path** via `fields.Lookup`;
  otherwise render and read the output as JSON via `parseResult`. Returns `(value, found, error)` so
  "missing path" and "empty list" stay different mistakes (`:135-137`).
- `promoteCtx(data, rec, name)` (`:156-168`): copy the context, lay a record's keys over the top
  level, and also bind the record at `name`. Used by `pollContext` (`.body`) and by `over=`
  (`.item`). The README documents the resulting shadowing hazard as a grammar limit.

### `spread` mechanics
`spreadSentinel = "\x00"`, `spreadEndSentinel = "\x01"` (`render.go:22-23`). An element containing
either byte is an error (`:248-252`). An empty slice emits `\x00\x01`, which `resolveArgv` drops
entirely (`exec.go:296-304`) and `expandSpreadForShell` skips (`exec.go:342-344`) — that is what makes
`spread` the way to write a conditional argument (README:191).

---

## 11. HTTP request path (`request.go`)

`prepareRequest` (`:100-134`) renders method → URL → query → body → headers into a
`preparedRequest{Method, URL, Body, Headers, AllowStatus}` (`:24-31`). Query building
(`buildRequestQuery`, `:185-215`) merges `<query from=>` (a context path to a map, walked with
`lookupPath` and sorted keys) with explicit `<param>`s; a param whose `When` path is falsy is skipped;
an empty rendered value is dropped.

`doHTTP` (`:139-180`): `curl -f` semantics — status ≥ 400 prints the body to stderr and returns code
1, **unless** the status is in `allow-status`, in which case the body returns with code 0
(`:168-178`).

`jqProgram` (`:253-277`) — **"a bare dotted name is a context path"**, the three-way resolution:

```go
contextPath = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_-]*(\.[A-Za-z0-9_-]+)*$`)   // :245
switch {
case spec == "":                        return "", nil
case strings.Contains(spec, "{{"):      return renderString(spec, data)   // a template
case !contextPath.MatchString(spec):    return spec, nil                  // the program itself
}
// else: fields.Lookup(data, spec) and it MUST be a non-nil string
```

The disambiguation argument (`:241-244`): a jq program almost always opens with `.`, `$`, `[`, `{`, a
digit or an operator, none of which start a path; a bare builtin like `length` is the one collision
and the error message names the workaround (`". | length"`, `:270`).

This three-way "template / context path / literal" resolution is a reusable pattern for any
attribute that may hold a foreign-language program.

---

## 12. Presentation dispatch (`format.go:226-307`)

`execLeaf` precedence, in code order:
1. user opt-out (`--no-format` / `--format=raw` / `NO_FORMAT` / `API_CLI_FORMAT=raw`,
   `userVerdictFromFlags` `:52-76`) → stream raw.
2. `--as=<sink>` with no `<fields>` → synthesise an empty `FieldsBlock` (`:245-247`).
3. `<tml>` and no sink and a terminal → one frame (`:252-273`).
4. any `<fields>` blocks → `runFieldsFormatted` (`:275-278`).
5. a `<format>` whose author `when=` is truthy → `runFormatted` (`:280-306`).
6. else raw.

`renderFieldsBlocks` (`:416-440`) renders every block whose `when=` holds, in order; none matching
returns `matched=false` and the caller prints the raw body. **The CLI and MCP paths share this
function** (`mcp_exec.go:101`).

`renderPredicate` (`:127-146`) caches a `(template-source, ctx-pointer)` verdict in a per-invocation
map — the only caching of any kind in the render path, and it caches the *result*, not the parse.

---

## 13. The MCP path — how the same leaf runner is reused

`mcpExecLeaf` (`mcp_exec.go:13-115`) is a near-transcription of `runLeafOnce`:
same `resolveContext` (`:20-22`), same preconditions loop (`:27-35`), same `data["result"]` install
(`:37-38`), same `runSteps` with a different capture (`:49-52`), same `renderEntry` (`:60-67`), same
download hand-off rule (`:71-73`), same `renderFieldsBlocks` (`:98-109`).
Differences: confirmation is skipped (MCP cannot answer, `:12`), stdout/stderr are buffered and
combined (`mcpCombine`, `:117-128`), and formatting behaves as `--format=always` with `.tty` true and
width 80 (`:96-100`).

It is a **copy, not a shared function** — the two diverge in I/O ownership. That is the cost
CLAUDE.md rule 1 warns about. A single-path tool avoids it entirely.

---

## 14. Runnable parents and argv pattern matching (`runnable.go`)

Relevant to api-cache because it is the only place in the org's language where **a value is
classified by a regular expression**.

- `Command.executes()` (`:337-339`): a leaf, or a parent with `runnable="true"`. It gates `RunE`,
  the MCP tool list, and every leaf-only validation.
- `validateRunnable` (`:352-393`): every `<arg>` of a runnable node needs a `pattern=`; the pattern
  must compile; and **the pattern must not match any of the node's own subcommand names or any name
  cobra owns** — a load error with the fix in the message ("anchor it with ^ and $", `:388`).
- `argPatterns` (`:397-406`) compiles once per node; `matchArgPatterns` (`:411-429`) is the cobra
  `PositionalArgs` validator; `chainArgs` (`:448-459`) runs count-then-pattern so the count error
  reports first.

`passthroughParse` (`flags.go:204-316`) is the other argv-facing mechanism: a hand-rolled parser that
recognises **only declared flags**, by long name or `short=`, with **one or two leading dashes**
(`:264`, for tools like CUDA's `cicc` that use single-dash long flags), handles `=` and next-arg
syntax, and pushes everything else into `.rest` verbatim — including a bare `--` and everything after
it (`:254-257`). A `bool` consumes no value, a `string-slice` accumulates.

`passthrough` and `<arg>` are mutually exclusive; `passthrough` is leaf-only
(`config.go:573-578`); `runnable` and `passthrough` cannot both hold (`runnable.go:356-358`).

---

## 15. The README's "Limits and workarounds" table, verbatim

`/home/user/api-cli/README.md:791-805`. Preamble (`:793`): *"Each row is something the grammar does
not do, and the shape to write instead. Every one of them is a real report from somebody who got
stuck."*

| Limit | Write this instead |
|-------|--------------------|
| **A subcommand name always wins over an argument.** Cobra reads the first positional as a subcommand name, so a runnable parent needs values that cannot spell one. | Give every arg of a runnable node a `pattern=` that matches no subcommand name. The loader enforces that. Use `--` for a value that starts with a dash. |
| **`urlpath` takes a string.** An `<arg type="int">` reaches it as a number, and the render fails with `expected string`. | Drop `as="urlpath"` for an int, because a number has nothing to escape. Declare the arg as a string when the value itself needs escaping. |
| **A legacy `<format>` prints raw output off a terminal.** An omitted `when=` means `{{.tty}}`, so a redirect, a pipe and the MCP server all skip the view. | Write `when="true"` on the format, or move the leaf to `<fields>`, which renders anywhere and takes `--as`. `--format=always` forces the terminal answer for one call. |
| **`.result` is empty in a `<precondition>`.** Preconditions run before the steps, and the loader rejects one that reads `.result`. | Put the check in a `<step when=>`, which runs in order with the other steps. A step that fails aborts the leaf with its own exit code. |
| **`allow-status=` needs the built-in client.** A `<transport>` program reports an exit code, and the status it saw is not ours to read. A named transport plus `allow-status` is a load error. | Put `transport="http"` on that one request, which opts it out of a default transport and back onto the built-in client. Otherwise let the program exit non-zero, and branch on `.result` in a later `<step when=>`. |
| **A leaf takes `<fields>` or `<format>`, never both.** | Keep `<format>` for a leaf that needs full control of the template. Everything else belongs in `<fields>`, which the sinks and `--as` understand. |
| **A record key named `item` is shadowed.** `over=` promotes a record's keys and then puts the record itself at `.item`, so the record wins that name. | Name the field something else in the response, or reach it as `.item.item`. The `<field expr=>` form has the same rule. |
| **`<join contiguous=>` cannot see a missing last part.** It reads the whole numbers between the lowest and the highest order in the group. | Check the count yourself in a `<step when=>` against whatever the listing says it holds. A hole in the middle is what this attribute reports. |
| **Nothing selects a transport at run time.** There is no `--transport` flag, by design: how a request reaches its endpoint is a property of the endpoint. | Name the transport in the config, on the `<request>` or as the registry `default="true"`. `transport="http"` is the per-request way back to the built-in client. |

Two rows generalise directly to api-cache. The `allow-status` row is the shape of *"a pluggable
program cannot report everything the built-in mechanism can, so the grammar refuses the combination
at load time and names the way out."* The `item` shadowing row is the shape of *"key promotion is a
convenience with a documented collision."*

Also worth carrying: README:809 on where the grammar lives — *"The loader stays authoritative at run
time. It enforces the rules a schema cannot state. One example is the rule that a leaf needs a run,
its own or an ancestor's."*

---

## 16. Error-message style (worth copying wholesale)

Every load error names the element, the attribute, the offending value, and — where one exists — the
alternative shape. Samples:

- `config.go:522` — `"allow-status needs the built-in client, and transport %q reports an exit code rather than a status; write transport=%q on this request, or let the program fail and branch in a <step when=>"`
- `config.go:651` — `"a precondition runs before <steps>, so .result is empty; move the check into a <step when=> or into the leaf"`
- `runnable.go:388` — `"pattern %q matches the subcommand name %q, so %q would be ambiguous; narrow the pattern (anchor it with ^ and $)"`
- `steps.go:173` — `"interval= and attempts= describe a poll, so they need until="`
- `transport.go:65` — `"<run> must be a command; a transport is what performs a request, so it cannot be one"`
- `request.go:270` — `"a bare name is a context path and must name a string (write \". | %s\" to mean the jq builtin)"`

The `where` string is built up positionally as the walk descends: `commands[0].steps[2].request`
(`config.go:464`, `:586`, `:705`). No line numbers — api-dsl's `Node` carries none.

## 17. Line budget

go-toolchain warns at 500 lines and **fails at 750** (CLAUDE.md). That is why the package is 27 flat
files rather than 6 big ones, and why `transport.go`, `join.go`, `xmlrequest.go` and `runnable.go`
exist as topical splits rather than living inside `xmlsource.go`/`config.go`.
