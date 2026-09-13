# The template runtime — what actually happens at run time, and what it costs

This file answers: what a compiled template *is*, how it gets executed, what that costs, what is pure
data versus what needs `text/template` at run time, and whether a "cooked" precompiled form is
possible.

All measurements below are from a benchmark written for this survey against the real
`github.com/wow-look-at-my/api-dsl` module (Go 1.25, linux/amd64, Intel Xeon @ 2.80 GHz, 4 cores).
The benchmark source is at
`/tmp/claude-0/-home-user/d081e2e4-6259-5904-be17-f9339419bf13/scratchpad/tmplbench/` (scratchpad,
not in the repo). Reproduce with `go test -bench=. -benchmem`.

---

## 1. What a compiled template is

A **plain Go string** of `text/template` source. Nothing more. `CompileContent`
(`api-dsl/compile.go:24-26`) returns `(string, error)`; every consumer stores that string in an
ordinary struct field:

- `api-cli/config.go:255-259` — `Cmd{Shell bool; Template string; Argv []string}`
- `api-cli/config.go:313-328` — `Request{Method, URL, Body string; ...}` (every field a template)
- `api-mirror/config.go` — `Var{Name, Value string}`, `Header{Name, Value string}`, etc.

So the load-time output of the whole language is: **a tree of Go structs whose string fields are
template source, plus a `json.RawMessage` for `<entry>`.** That is 100% serializable by
`encoding/json` or `encoding/gob` with no custom work.

The one thing that is **not** a plain string is api-cli's `<entry>`: `buildEntry`
(`api-cli/xmlsource.go:532-541`) produces a `json.RawMessage` whose *string leaves* are template
source, and `renderEntry` (`api-cli/render.go:382-431`) walks and renders them at run time. Still
pure data.

## 2. How a render is called

Exactly one place executes a template in the whole family — `Renderer.Render`
(`api-dsl/render.go:66-76`):

```go
t, err := template.New("t").Funcs(r.funcs).Option("missingkey=zero").Parse(tmpl)
if err != nil { return "", fmt.Errorf("parse template %q: %w", tmpl, err) }
var buf bytes.Buffer
if err := t.Execute(&buf, data); err != nil { return "", fmt.Errorf("execute template %q: %w", tmpl, err) }
return buf.String(), nil
```

**A fresh `template.New` + `Funcs` + `Parse` on every single call. Nothing is cached at any level.**
Verified by grep: `api-cli` contains exactly one `text/template` import (`render.go:13`) and no
`template.New`/`.Parse` of its own; `api-mirror` has none at all.

Consumers reach it two ways:
- `api-cli/render.go:47` — `var renderer = apidsl.NewRenderer(cliFuncs())`, a package-level
  singleton; `renderString(tmpl, data)` = `renderer.Render(tmpl, data)` (`:170-172`). The
  **`Renderer`** is cached; the **template** is not.
- `api-mirror/dsl.go:9` — `renderString = apidsl.RenderString`, which uses api-dsl's own package-level
  `defaultRenderer` (`api-dsl/render.go:79`).

The only caching anywhere in the render path is `api-cli/format.go:127-161`, which memoizes a
**predicate's boolean verdict** by `(template source, context map pointer)` for the duration of one
invocation. It does not cache the parse.

## 3. The cost profile — measured

```
BenchmarkRenderShort       62,383 ns/op   43,739 B/op    64 allocs/op   // `{{ .arg.x }}`
BenchmarkRenderMedium      67,658 ns/op   46,587 B/op   150 allocs/op   // 87-byte template, 4 actions
BenchmarkRenderLong        86,618 ns/op   51,142 B/op   268 allocs/op   // ~220 bytes, range+if+6 funcs
```

**A trivial one-action template costs 62 microseconds and 43 kilobytes.** That is not a typo, and it
is the single most important number in this survey.

Decomposing it:

```
BenchmarkA_NewFuncs        60,330 ns/op   40,624 B/op    28 allocs/op   // template.New("t").Funcs(fm).Option(...)  — NO Parse, NO Execute
BenchmarkB_NewFuncsParse   73,410 ns/op   45,960 B/op   123 allocs/op   // the above + Parse(medium)
BenchmarkC_ParseNoFuncs     6,400 ns/op    3,664 B/op    49 allocs/op   // New().Option().Parse(...) with NO func map
BenchmarkD_ExecuteOnly      2,615 ns/op      473 B/op    24 allocs/op   // Execute a pre-parsed template
BenchmarkE_CachedRender     2,996 ns/op      609 B/op    27 allocs/op   // map lookup by source + Execute
```

**~97% of every render is `.Funcs(fm)`.** `text/template.addFuncs` reflects over every entry of the
func map (`reflect.ValueOf` per function, plus `goodName` validation), and api-dsl's `FuncMap()` has
**~200 entries** (sprig's `genericMap` is 196 names plus api-dsl's four). That reflection work is
redone from scratch on every `Render` call.

Cheap fixes, measured:

```
BenchmarkF_CloneParseExecute 63,339 ns/op  46,452 B/op   147 allocs/op   // base.Clone() + Parse + Execute
BenchmarkG_SmallFuncMapRender 12,887 ns/op  6,681 B/op   125 allocs/op   // same render, 2-entry func map
```

- **`Template.Clone()` does not help.** It copies the func map with the same per-entry cost.
- **Shrinking the func map is a 5x win** on its own (70 µs → 13 µs).
- **Caching the parsed template by source string is a 23x win** (70 µs → 3.0 µs) and is the obvious
  fix, since a config's set of templates is fixed at load.

Building the func map itself is cheap — `FuncMap()` 11 µs / 9.5 KB, `NewRenderer()` 10.5 µs — so
sprig's map construction is not the problem; `text/template`'s reflection over it is.

### Why this matters more here than it did for api-cli

api-cli is an interactive CLI or a long-lived MCP server: a few dozen renders per invocation, at
human timescales, and 2 ms is invisible. A compiler-wrapper cache runs **once per translation unit
and exits**, thousands of times per build, on the critical path of every compile. Cold cost is the
only cost; there is no steady state to amortize into.

```
BenchmarkInvocation1       59,038 ns/op     46,586 B/op     150 allocs/op
BenchmarkInvocation10     599,051 ns/op    465,872 B/op   1,500 allocs/op
BenchmarkInvocation30   1,787,927 ns/op  1,397,615 B/op   4,501 allocs/op
```

Thirty renders in one invocation is **1.8 ms of CPU and 1.4 MB of garbage**, before any real work.
For reference, api-cli's own leaf path renders: each var (× passes to a fixpoint, up to 10 passes ×
N vars), each templated flag default, each precondition, each step's `when=`, each step's entry leaf,
each step's cwd/stdin, the URL, each query param name and value, each header name and value, the
body, the jq program, the command, each `<fields>` `when=` and each `expr=`, and each format
predicate. A modest config passes 30 easily. (Process-start cost is a separate question, measured by
the `startup-perf` worker under `plan/research/startup-perf/`.)

## 4. `missingkey=zero`, precisely

`api-dsl/render.go:67` sets `Option("missingkey=zero")` and `:63-65` explains: *"a missing map key
yields the zero value of the map's element type."* The consequence is type-dependent and is pinned by
test (`api-dsl/render_test.go:161-169`):

| map type | missing key renders as |
|---|---|
| `map[string]any` | `<no value>` (nil's zero, printed by text/template as that literal) |
| `map[string]string` | `""` |

Every context map in api-cli holds `any` except `.env`, which `EnvMap()` makes a `map[string]string`
(`api-dsl/render.go:89-97`). So `{{ .var.nope }}` prints `<no value>` and `{{ .env.NOPE }}` prints
empty. api-cli's README:758 and CLAUDE.md rule 10 both restate it; api-cli mitigates it by ensuring
**every declared arg and flag is always present** (`zeroArg`, `flags.go:137-148`), so `<no value>` in
practice means the path itself is wrong.

A document that must stop on a missing value writes sprig's `fail` (`render.go:64-65`,
`render_test.go:176-179`). There is no `missingkey=error` option and CLAUDE.md forbids changing the
default, because "documents rely on a missing key rendering empty."

**For a cache key this is a footgun worth naming.** A mistyped path in a key-deriving template
renders the literal string `<no value>` and produces a *stable, wrong, silently-colliding* key rather
than an error. api-cli/README:303 already ran into the same shape for a digest — "A renamed manifest
field renders as the template engine's placeholder. The plan step rejects that before it fetches
anything, rather than leave the file unverified in silence."

## 5. `LookupPath` vs `DotPath` — two different resolutions

There are **two** ways a dotted path is resolved, and they behave differently:

**`DotPath(path)`** (`api-dsl/compile.go:61-82`) is a **compile-time** transform to template source:
`"var.base"` → `".var.base"`, `"flag.dry-run"` → `(index . "flag" "dry-run")`. The resulting lookup
is `text/template`'s own field/index evaluation, which handles structs, maps, and (via `index`)
slices, and obeys `missingkey=zero`.

**`LookupPath(data, path)`** (`api-dsl/render.go:132-149`) is a **run-time** walk:

```go
for _, seg := range strings.Split(path, ".") {
	switch m := cur.(type) {
	case map[string]any:   cur = m[seg]
	case map[string]string: cur = m[seg]
	default:               return nil       // anything else: nil, immediately
	}
}
```

Empty segments are skipped; a missing key yields nil; a non-map mid-walk yields nil. **It cannot
index a slice.** api-cli needed that and wrote its own (`fields.Lookup`, used by `overSource`
`render.go:140`, `collectPath` `:117`, and `jqProgram` `request.go:268`); api-cli's CLAUDE.md rule 8
says `lookupData` "walks maps by key and lists by index, so a numeric step indexes a list."

Consumers use `LookupPath` for path-valued attributes evaluated at run time — `<query from=>`
(`api-cli/request.go:188`), a header/param `when=` (`request.go:199`, `:222`), and throughout
api-mirror (`absorb.go:26`, `:62`; `ordering.go:41`; `replay.go:51`). `api-mirror/paths.go:10-12`
wraps it so absence has one stated reading.

**Note that api-cli never calls `DotPath` at all** — the function exists for exactly the use
(compiling a consumer's own path attribute) that neither consumer actually adopted.

## 6. `Truthy` semantics, exactly

`api-dsl/render.go:99-127`. After `TrimSpace`: empty is false; case-insensitive `"false"`, `"0"`,
`"no"` are false; **everything else is true**. `nil` is false, a `bool` is itself, a `string` goes
through `IsTruthy`, and anything else is `fmt.Sprintf("%v", x)` then `IsTruthy`.

Consequences worth stating before anyone designs a predicate on top of it:

| value | truthy? | why |
|---|---|---|
| `"off"`, `"n"`, `"disabled"`, `"FALSE "` | `"off"`/`"n"`/`"disabled"` → **true**; `"FALSE "` → false | only three words are falsy, case-insensitively, after trim |
| `0` (int) | false | stringifies to `"0"` |
| `0.0` | **true** | stringifies to `"0"`… actually `fmt.Sprintf("%v", 0.0)` is `"0"` → false. `0.5` → true |
| `[]any{}` | **true** | stringifies to `"[]"` |
| `map[string]any{}` | **true** | stringifies to `"map[]"` |
| `nil` | false | explicit case |
| `<no value>` (a missing `any` key) | **true** — the *string* `"<no value>"` would be, but the value is `nil`, so false | the nil arrives as nil, not as the rendered text |

`truthy` is what `<if test=>` compiles to (`compile.go:242`) and is therefore **not optional** — a
func map without it fails to execute (`api-dsl/render.go:19-20`, CLAUDE.md invariant). `IsTruthy` is
separately used on the *rendered output* of a `when=`/`until=` predicate
(`api-cli/steps.go:53`, `:135`; `format.go:141`), so a predicate is evaluated by rendering it to a
string and then reading that string.

## 7. "A bare dotted name is a context path" — the three-way attribute

`jqProgram` (`api-cli/request.go:253-277`) is the reference implementation of an attribute that may
hold a **template**, a **context path**, or a **literal program in a foreign language**:

```go
var contextPath = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_-]*(\.[A-Za-z0-9_-]+)*$`)  // :245

switch {
case spec == "":                     return "", nil
case strings.Contains(spec, "{{"):   return renderString(spec, data)         // template
case !contextPath.MatchString(spec): return spec, nil                        // the literal program
}
v, ok := fields.Lookup(data, spec)                                            // a context path
// must be a non-nil string, else an error naming the workaround
```

The disambiguation argument (`:241-244`): *"A jq program almost always opens with `.`, `$`, `[`, `{`,
a digit, or an operator, none of which start a path. A bare builtin like `length` is the one
collision, and it reads as the path."* The error for the collision names the escape:
`write ". | length" to mean the jq builtin` (`:270`).

`overSource` (`api-cli/render.go:138-151`) is the two-way version: no `{{` → a context path;
otherwise render and read the output as JSON.

## 8. A "cooked" / precompiled form: what is possible

### What is pure data (serializable today, no work)

- The whole DOM after parse (though `apidsl.Node` has no exported fields and no constructor, so it
  cannot be reconstructed — see §9).
- **Every consumer config struct.** `Config`, `Command`, `Step`, `Request`, `Transport`, `Fields`,
  `Download`, `Join` in api-cli; `Spec`, `Resource`, `Route`, `Event` in api-mirror. All plain Go
  types with string/int/bool/slice/map fields and `json` tags already present
  (`api-cli/config.go:20-37` etc.). `Cmd` and `FormatRef` even carry custom
  `MarshalJSON`/`UnmarshalJSON` (`config.go:262-296`, `:137-172`) written explicitly "mostly for
  tests" — so a JSON round-trip of a loaded config already works.
- The compiled template **source strings**.

So a "cooked config" in the trivial sense — parse XML once, `json.Marshal` the config tree, and load
that instead — needs no new machinery at all. It saves the XML tokenize + build + validate pass. That
pass is cheap relative to rendering, but it is not free.

### What needs `text/template` at run time

Only `Renderer.Render`. Three levels of pre-work are possible, in increasing ambition:

**(a) Cache the parsed `*template.Template` by source string.** Trivial, in-process, 23x per render
(70 µs → 3.0 µs). Works only if the process makes several renders, which it does.
**This is the single highest-value change and it does not require touching api-dsl** — a consumer can
hold its own `map[string]*template.Template` and call `text/template` itself, at the cost of
re-implementing the four lines of `Render`. Adding it *inside* api-dsl would benefit both existing
consumers and is a small, backwards-compatible change (`Renderer` is already documented as
"read-only after construction, and safe for concurrent use", so the cache needs a mutex or a
`sync.Map`).

**(b) Shrink the func map.** 5x on its own (70 µs → 13 µs), and it composes with (a). sprig's 196
functions include `genPrivateKey`, `genCA`, `bcrypt`, `derivePassword`, `encryptAES`,
`getHostByName` (a **DNS lookup**), `env` and `expandenv` (ambient environment reads) — several of
which are actively undesirable in anything that derives a cache key, because they make a render
non-deterministic or non-hermetic. A curated func map is both faster and safer. It is also a
deviation from the shared `FuncMap()`, so it belongs in the consumer (via `NewRenderer`, per
api-dsl's invariant) rather than in api-dsl.

**(c) Serialize the parse tree.** **Verified to work**, with caveats:

```
parse.Parse(name, text, "{{", "}}", funcs)   // exported entry point, returns map[string]*parse.Tree
template.AddParseTree(name, tree)            // installs a tree into a Template; Execute works
```

A gob round-trip of `tree.Root` executes correctly *after registering all 21 concrete node types*
(`ActionNode`, `BoolNode`, `ChainNode`, `CommandNode`, `CommentNode`, `DotNode`, `FieldNode`,
`IdentifierNode`, `IfNode`, `ListNode`, `NilNode`, `NumberNode`, `PipeNode`, `RangeNode`,
`StringNode`, `TemplateNode`, `TextNode`, `VariableNode`, `WithNode`, `BreakNode`, `ContinueNode`).
Measured: an 87-byte template source became **1,245 gob bytes** — ~14x expansion. `encoding/json`
marshals a tree fine (1,193 bytes) but **cannot unmarshal it**: `parse.Node` is an interface, so a
custom type-tagged decoder would be required.

**The verdict is that (c) is not worth it.** It buys only the 6.4 µs `Parse`, while the 60 µs
`.Funcs()` is unavoidable in any case, and it costs 14x the bytes plus a hand-maintained node
registry that breaks whenever the Go team adds a node type. Do (a) and (b) instead.

**(d) Constant-fold at load time.** A template with no actions (`!strings.Contains(src, "{{")`) does
not need the renderer at all — return it verbatim. api-cli already does a narrow version of this for
two hot fields: `renderCwd`/`renderStdin` (`build.go:369-384`) short-circuit an **empty** template so
"we don't pay template machinery on the common no-cwd path". Generalizing that check to
"no `{{` at all" is one line and removes the 60 µs entirely for every literal string in a config —
which, in a build-cache config, is most of them.

## 9. Things a cooked form cannot do today

- **`apidsl.Node` cannot be reconstructed.** All fields are unexported and `ParseDOM` is the only
  constructor (`api-dsl/dom.go:13-18`, `:71`). A DOM cannot be cached in a non-XML form and replayed;
  the cooked form must be the *consumer's* structs, after the build pass.
- **There is no source position anywhere.** `Node` carries no line/column, so nothing downstream can
  report one, cooked or not.
- **Error messages embed the whole template source** (`render.go:69`, `:73`:
  `parse template %q`, `execute template %q`). For a 2 KB shell body that is a 2 KB error line. A
  consumer that wants short errors must wrap or truncate.
- **`Renderer` has no way to pre-register templates.** The API is `Render(tmpl string, data any)`;
  there is no `Prepare(name, src)` / `RenderPrepared(name, data)` pair. Adding one is the natural
  shape for (a) above.

## 10. The complete function set available in a template

### From api-dsl (`render.go:21-28`)
`truthy`, `querystring`, `urlpath`, `repeatkey` — plus **all of sprig's `TxtFuncMap()`**.

### sprig v3.2.3 `genericMap`, all 196 names (MIT, Masterminds, `LICENSE.txt`)

*Dates:* `ago date date_in_zone date_modify dateInZone dateModify duration durationRound htmlDate
htmlDateInZone must_date_modify mustDateModify mustToDate now toDate unixEpoch`
*Strings:* `abbrev abbrevboth trunc trim upper lower title untitle substr repeat trimall trimAll
trimSuffix trimPrefix nospace initials swapcase snakecase camelcase kebabcase wrap wrapWith contains
hasPrefix hasSuffix quote squote cat indent nindent replace plural toString`
*Random:* `randAlphaNum randAlpha randAscii randNumeric shuffle randInt randBytes uuidv4`
*Hashes/encodings:* `sha1sum sha256sum adler32sum b64enc b64dec b32enc b32dec`
*Numbers:* `atoi int64 int float64 seq toDecimal gt gte lt lte until untilStep add1 add sub div mod
mul add1f addf subf divf mulf biggest max min maxf minf ceil floor round`
*Lists:* `split splitList splitn toStrings join sortAlpha tuple list append push mustAppend mustPush
prepend mustPrepend first mustFirst rest mustRest last mustLast initial mustInitial reverse
mustReverse uniq mustUniq without mustWithout has mustHas slice mustSlice concat chunk mustChunk
compact mustCompact`
*Dicts:* `dict get set unset hasKey pluck keys pick omit merge mergeOverwrite mustMerge
mustMergeOverwrite values dig`
*Defaults/logic:* `default empty coalesce all any ternary deepCopy mustDeepCopy deepEqual`
*Reflection:* `typeOf typeIs typeIsLike kindOf kindIs`
*JSON:* `fromJson toJson toPrettyJson toRawJson mustFromJson mustToJson mustToPrettyJson
mustToRawJson`
*Paths:* `base dir clean ext isAbs osBase osClean osDir osExt osIsAbs`
*Regex:* `regexMatch mustRegexMatch regexFindAll mustRegexFindAll regexFind mustRegexFind
regexReplaceAll mustRegexReplaceAll regexReplaceAllLiteral mustRegexReplaceAllLiteral regexSplit
mustRegexSplit regexQuoteMeta`
*Crypto:* `bcrypt htpasswd genPrivateKey derivePassword buildCustomCert genCA genCAWithKey
genSelfSignedCert genSelfSignedCertWithKey genSignedCert genSignedCertWithKey encryptAES decryptAES`
*Semver:* `semver semverCompare`
*Env / network:* `env expandenv getHostByName`
*Control:* `fail`
*URL:* `urlParse urlJoin`
*Misc:* `hello`

Three of these deserve a flag for anything deriving a cache key:
`env` / `expandenv` read the ambient process environment inside a template, bypassing the explicit
`.env` namespace; `getHostByName` performs a **DNS lookup** during a render. `randAlphaNum` and the
rest of the random family, plus `now`, `uuidv4` and `date`, are non-deterministic by construction.

Note also that `sha1sum`, `sha256sum` and `adler32sum` exist — they take a **string** and return a
hex string. There is **no file hashing, no `[]byte` path, and no streaming hash** anywhere in the
available function set.

### From api-cli's `cliFuncs` (`api-cli/render.go:28-43`) — the consumer-extension precedent
`shellquote spread fileExists dirExists tabwriter padRight padLeft displayWidth stripANSI
filterSuffix filterPrefix collect`. Note `fileExists`/`dirExists` already reach the filesystem from
inside a template, so filesystem access in a consumer helper has precedent.

## 11. Summary table for a planner

| question | answer | cite |
|---|---|---|
| What is a compiled template? | a plain Go string of `text/template` source | `api-dsl/compile.go:24` |
| Is the parse cached? | **no**, nowhere, at any level | `api-dsl/render.go:67` |
| Cost of one render? | **~62-87 µs, ~44-51 KB** | benchmark, §3 |
| What dominates it? | `.Funcs(fm)` over ~200 sprig entries: **60 µs, 40 KB, 97%** | benchmark `A_NewFuncs` |
| Parse alone? | 6.4 µs | benchmark `C_ParseNoFuncs` |
| Execute alone? | 2.6 µs, 473 B | benchmark `D_ExecuteOnly` |
| Fix with the best ratio? | cache parsed templates by source → 3.0 µs (**23x**) | benchmark `E_CachedRender` |
| Does `Clone()` help? | **no** — it re-copies the func map | benchmark `F_CloneParseExecute` |
| Does a smaller func map help? | yes, 5x on its own, composes with caching | benchmark `G_SmallFuncMapRender` |
| Can a parse tree be serialized? | yes (gob + 21 registered node types, `AddParseTree` executes) | verified, §8(c) |
| Is it worth it? | **no** — buys 6.4 µs, costs 14x bytes and a hand-kept node registry | §8(c) |
| What is pure data? | every consumer config struct, already `json`-tagged | `api-cli/config.go:20-37` |
| What cannot be cooked? | `apidsl.Node` (unexported fields, `ParseDOM` is the only constructor) | `api-dsl/dom.go:13-18` |
