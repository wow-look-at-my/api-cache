# Gaps — what the language cannot express today

Each entry states the gap, the evidence, and **where the fix belongs**. That last question has one
structural constraint: **api-dsl is a shared module with two live consumers** (api-cli, api-mirror),
and its own CLAUDE.md names the compiled forms as a frozen contract — *"Changing an entry changes
what every shipped document means, in both consumers"* (`/home/user/api-dsl/CLAUDE.md`, Invariants).
So the disposition of every gap is one of:

- **CONSUMER** — api-cache's own vocabulary carries it. No shared change. Preferred by default.
- **HELPER** — a template function added through `NewRenderer(extra...)`, which is the stated
  extension point (`api-dsl/render.go:30-41`). Consumer-local; no shared change.
- **DSL-ADD** — a purely additive change to api-dsl (a new exported function, an optional method) that
  breaks no compiled form and no existing consumer.
- **DSL-BREAK** — would change a compiled form, a placeholder's grammar, or an existing signature.
  Expensive; needs both consumers to move.

A note on the whole list: **api-dsl's language layer is string-in, string-out.** `CompileContent`
returns a `string`; `Render` returns a `string`; `Node` content is a `string`. Several gaps below are
the same gap wearing different clothes.

---

## 1. Byte-level and binary data

**Gap.** Nothing in api-dsl or either consumer moves bytes through the language. `Item.Text` is a
`string` (`api-dsl/dom.go:28-31`), `CompileContent` returns a `string` (`compile.go:24`), `Render`
returns a `string` (`render.go:66`). The only `[]byte` in api-dsl is `ParseDOM`'s input.

**Why it matters.** A compiler wrapper must hash stdin, hash compiler stdout, store an object file,
and compare bytes. None of that can travel *through* a template.

**Disposition: CONSUMER.** This is not a language gap at all once you see it correctly. The language's
job is to produce *decisions and paths* — "which file", "which algorithm", "which key" — and the Go
runtime does the byte work, exactly as api-cli already does: the config says
`<hash algo="sha256"><value name="digest"/></hash>` (a template producing a **hex string**,
`download.go:471-499`), and the streaming hash lives in Go (`newHasher`, `downloader.go:435-449`;
`partFile.digest`, `:363-370`). Keep that split. The moment a template is handed bytes, the 62 µs
render cost and the `<no value>` hazard (`template-runtime.md` §4) both land on the hot path.

**Caveat to record.** `sha256sum`/`sha1sum`/`adler32sum` **are** in sprig's func map and take a
string. They will be reachable from any template in api-cache and they are not what anyone wants for
a file. Consider shadowing them in `NewRenderer` with versions that fail loudly, or documenting the
distinction.

---

## 2. A cache key as a first-class notion

**Gap.** There is no "key" concept in api-dsl. The nearest analogue is api-mirror's `<key>` element
(`api-mirror/load.go:225+`, `absorb.go:20-31`), which is a **consumer** element: a name, an optional
`from=` path into the document, and `fold="true"` for case folding. api-mirror derives its primary key
from the declared `<key>` list, in declaration order (`schema.go:32-54`, `columnsOf` `:76-88`), and
enforces a stable order so "a column can never be written in order and read in another."

**Disposition: CONSUMER.** api-mirror's shape transfers directly and the surrounding discipline
transfers with it:

- **A stable declared order** that both the writer and the reader derive from (`schema.go:73-88`).
- **Identifier hygiene at load**: a restricted charset, a reserved-name set, an engine prefix
  (`schema.go:96-148`).
- **A derived fingerprint over the whole declaration**, never a hand-bumped constant
  (`schema.go:58-71`; contrast `go-s3-server`'s `currentCacheVersion`).

**One real hazard to design around.** Under `missingkey=zero` a mistyped path in a key-deriving
template renders the literal text `<no value>` and yields a **stable, wrong, silently-colliding key**
rather than an error (`api-dsl/render_test.go:161-169`). api-cli hit the identical shape for a digest
and solved it by **validating the rendered form at plan time**: `renderHash`
(`download.go:478-499`) rejects anything that is not an N-character hex string, with the reasoning in
`README.md:303` — *"A renamed manifest field renders as the template engine's placeholder. The plan
step rejects that before it fetches anything, rather than leave the file unverified in silence."*
Any key-producing template needs the same post-render shape check. There is no way to get an error
out of the renderer itself without changing `missingkey`, which api-dsl's invariants forbid.

---

## 3. Classifying and rewriting an argv

**Gap.** The language can *read* an argv list and *build* one, but cannot classify or transform it by
declared rules.

What exists:
- **Read.** `passthrough="true"` + `passthroughParse` (`api-cli/flags.go:204-316`) recognises declared
  flags only (one or two leading dashes, `=` and next-arg forms) and pushes the rest into `.rest`.
  Everything after a bare `--` goes in verbatim (`:254-257`).
- **Filter.** `filterSuffix` / `filterPrefix` over `.rest` (`api-cli/render.go:304`, `:319`) — the doc
  comment literally names the compiler case.
- **Validate one value.** `<arg pattern=>`, a Go regex compiled once at load
  (`runnable.go:379`, `argPatterns:397`) and checked per invocation (`matchArgPatterns:411-429`).
- **Build.** `<argv>` elements, each a template (`xmlsource.go:144-157`), plus `spread`
  (`render.go:243`) to splat a list into N slots and drop to zero slots when empty.

What does not exist: no declarative "this flag takes a value", "this flag is cache-irrelevant",
"rewrite `-o X` to `-o -`", "this flag makes the action uncacheable", "these flags are order-
insensitive". `passthroughParse` knows only a flag's *type* (`string|bool|int|string-slice`), which
is a proxy for arity and nothing more.

**Disposition: CONSUMER** — and this is the largest genuinely new piece of vocabulary api-cache needs.
Nothing in api-dsl obstructs it: an `<argv>`-classification grammar is ordinary structural elements
with ordinary attributes, checked with `CheckAttrs`, some of whose values are placeholder-carrying
content and some of which are literal patterns via `TextOf`.

**Two design cues from the family worth carrying.**
- Compile every regex **once at load and fail there**, never per invocation
  (`runnable.go:379-382` returns `pattern %q does not compile: %w`; `argPatterns:397-406` then uses
  `MustCompile` because the load already proved it).
- Make the *ambiguous* case a load error with the fix in the message. `validateRunnable:386-390` is
  the template: *"pattern %q matches the subcommand name %q, so %q would be ambiguous; narrow the
  pattern (anchor it with ^ and $)"*. A flag-classification table has the same failure mode (two rules
  matching one flag) and deserves the same treatment.

---

## 4. A manifest of several outputs

**Gap.** Both consumers assume **one result per action**. A step stores exactly one value at
`.result.<name>` (`api-cli/steps.go:89`); a leaf produces one stdout; a resource stores one row per
key (`api-mirror/schema.go:29-31`).

The closest existing shape is `<join>` (`api-cli/join.go`), which groups N downloads into one output
file: `group=` buckets, `order=` positions numerically, membership is decided **at plan time** so the
joiner knows each group's size before the first transfer (api-cli CLAUDE.md rule 27), and **a group
short a member is never written**. And `<step over=>` produces a list of `{item, result}` pairs
(`steps.go:270`) rather than two parallel lists — the comment at `:230-233` argues for the pairing
precisely because "a screen that draws a card per build walks ONE list, rather than reaching across
two of them by position."

**Disposition: CONSUMER.** The `<join>` plan-time-membership discipline and the `over=` pairing
convention both transfer to a multi-output manifest. Nothing shared changes.

---

## 5. Filesystem interaction: globs, stat, dependency files

**Gap.** The language reaches the filesystem in exactly two places, both consumer helpers:
`fileExists` and `dirExists` (`api-cli/render.go:285`, `:294`), each of which swallows every error
other than not-exist ("template helpers shouldn't error on permission issues during a precondition
check", `:283-284`). There is no glob, no stat (size/mtime/mode), no directory walk, no readlink, no
realpath, and no reader for a compiler `.d` dependency file.

**Disposition: HELPER for the simple reads, CONSUMER for the parsers.**
A `glob`, `stat`, `mtime`, `realpath` helper is exactly what `NewRenderer(extra...)` exists for, and
`fileExists` is the precedent that filesystem access from a template is acceptable in this family.

Two cautions:
1. **Cost.** Every helper call happens inside a 62 µs render (`template-runtime.md` §3). A glob over a
   large tree inside a template is invisible until it is not.
2. **Error swallowing is the wrong default here.** `fileExists` returning false on a permission error
   is fine for a precondition and wrong for anything that feeds a cache key: it turns an I/O failure
   into a *different but stable* key. Prefer sprig's `fail` semantics, or validate after the render
   as `renderHash` does.

A `.d`-file parser is not a template helper at all — it is Go code that produces a list the template
then reads, the same way `parseResult` (`api-cli/exec.go:218`) turns a step's stdout into structured
data the next template reads.

---

## 6. Determinism and hermeticity of a render

**Gap.** api-dsl's `FuncMap()` is sprig's whole `TxtFuncMap()` (`render.go:22`), which includes:

- `env` and `expandenv` — read the **ambient** process environment from inside a template, bypassing
  the explicit `.env` namespace entirely.
- `getHostByName` — performs a **DNS lookup** during a render.
- `now`, `date`, `uuidv4`, `randAlphaNum`, `randAlpha`, `randAscii`, `randNumeric`, `randInt`,
  `randBytes`, `shuffle` — non-deterministic by construction.
- `genPrivateKey`, `genCA`, `bcrypt`, `derivePassword`, `encryptAES` — expensive and irrelevant.

For a tool whose entire correctness argument is "the same inputs produce the same key", a function set
that can read the environment and the network behind the config author's back is a real hazard, and
there is no marker distinguishing a pure template from an impure one.

**Disposition: HELPER (shadowing), or DSL-ADD.**
- The cheap fix is consumer-local: `NewRenderer` applies extras **after** `FuncMap()` and a later map
  wins (`api-dsl/render.go:42-50`, pinned by `render_test.go:206-214`), so api-cache can replace
  `env`, `expandenv`, `getHostByName`, `now`, `uuidv4` and the random family with versions that
  `error`. The doc comment already contemplates deliberate replacement (`:40-41`).
- A shared `apidsl.PureFuncMap()` — sprig minus the impure names — would be purely additive and would
  also cut the per-render cost (a smaller func map is measured at 5x, `template-runtime.md` §3). That
  is a **DSL-ADD** worth proposing but not worth blocking on.

---

## 7. Render cost on a hot path

**Gap.** ~62-87 µs and ~44 KB **per render**, with nothing cached at any level
(`api-dsl/render.go:66-76`; measurements in `template-runtime.md` §3). ~97% of it is `.Funcs(fm)`
reflecting over ~200 sprig entries on every call. Thirty renders in one invocation measured at 1.8 ms
and 1.4 MB of garbage.

Neither existing consumer cares: api-cli is interactive or long-lived, api-mirror renders at engine
construction and then almost never. A per-compile wrapper is the first consumer for which cold cost is
the only cost.

**Disposition: CONSUMER now, DSL-ADD later.** Three fixes, in order of ratio:
1. **Skip the renderer entirely when a template has no actions** (`!strings.Contains(src, "{{")`) —
   one line, removes 100% of the cost for every literal string in a config. api-cli already does the
   narrow version of this for two hot fields, with the reasoning stated:
   *"An empty template short-circuits ... so we don't pay template machinery on the common no-cwd
   path"* (`build.go:366-374`).
2. **Cache the parsed `*template.Template` by source string** — 23x (70 µs → 3.0 µs). A consumer can
   hold its own map at the cost of re-implementing `Render`'s four lines; adding `Prepare(src)` /
   `RenderPrepared` to `apidsl.Renderer` would be additive and benefit both existing consumers.
3. **Shrink the func map** — 5x on its own, composes with (2), and overlaps entirely with gap 6.

`Template.Clone()` was measured and **does not help** (it re-copies the func map at the same cost).
Serializing parse trees was verified to work via gob + `AddParseTree` but buys only the 6.4 µs parse
at 14x the bytes — not worth it (`template-runtime.md` §8(c)).

---

## 8. No source position in an error

**Gap.** `apidsl.Node` carries no line or column (`api-dsl/dom.go:13-18`), so no consumer error can
name one. Both consumers compensate with positional `where` strings built during the walk —
`commands[0].steps[2].request` (`api-cli/config.go:464`, `:586`, `:705`) and
`resource %q field %q` (`api-mirror/validate.go:178`).

Separately, `Render`'s errors embed the **whole template source**: `parse template %q: %w` and
`execute template %q: %w` (`api-dsl/render.go:69`, `:73`). For a multi-line script body that is a
very long error line.

**Disposition: DSL-ADD (position) / CONSUMER (error length).** Adding a `Pos()` to `Node` is additive
— no existing field or signature changes — but it touches the DOM for both consumers' benefit and is
not required. The `where`-string convention is proven and costs nothing. Truncating the template in an
error is a consumer wrapper.

---

## 9. `<for>` has no index, and there is no local binding

**Gap.** `<for each="path">` compiles to a bare `{{ range PATH }}` (`api-dsl/compile.go:253-266`).
There is no loop index, no key variable, no `{{ else }}` empty branch, and no `<let>`/`<with>`. The
attribute set is `each` and nothing else (`:254`), enforced by `CheckAttrs`.

**Disposition: CONSUMER, using `expr=`.** `<value expr="...">` is emitted verbatim
(`compile.go:193`), so an author writes `{{ range $i, $v := .list }}` by hand today. api-cli's own
documentation does exactly this for a transport argv
(`api-cli/README.md:188`). Adding `as=`/`index=` to `<for>` would be **DSL-BREAK** territory (a new
compiled form), and the escape hatch already covers it.

Note that api-cli's repetition constructs — `<step over=>`, `<download over=>`, `<prop over=>` — are
**consumer** elements that iterate in Go, not in a template (`steps.go:237-274`), and they supply
`.item` **and** `.index` (`:260`). That is the pattern to follow when iteration needs an index: put it
in the consumer's element, not in `<for>`.

---

## 10. `<if>` is a placeholder in content and a structural element elsewhere

**Gap (really a trap).** Inside compiled content, `<if test= eq=>` is api-dsl's placeholder. But
`api-cli/xmlrequest.go:418-432` and `:479-493` use an element *also named* `<if>` as a **structural**
wrapper around `<header>`/`<param>` children, where `test=` is stored as a run-time `When` **context
path** evaluated with `templateTruthy(lookupPath(data, when))` (`request.go:199`, `:222`) rather than
compiled to `{{ if truthy ... }}`.

So the same element name means two different things depending on where it appears, and a structural
`<if>` supports only `test=` (not `eq=`) and only one kind of child.

**Disposition: CONSUMER — decide deliberately.** `IsPlaceholder` (`compile.go:14`) is the
discriminator that makes the double life possible. api-cache should either reuse the convention
knowingly or avoid a structural `<if>` and reach for a `when=` attribute instead, which is what every
other repeatable declaration in api-cli does (`<step when=>`, `<fields when=>`, `<download when=>`,
`<view when=>`, `<format when=>`).

Related distinction worth writing into api-cache's own docs, because api-cli's CLAUDE.md flags it as a
gotcha: **`when=` is a full template predicate; `test=` is a context path checked for truthiness.**
They are not interchangeable.

---

## 11. No includes, imports, or multi-file configs

**Gap.** `ParseDOM([]byte)` reads one document (`api-dsl/dom.go:71`). There is no `<include>`, no
entity resolution beyond `encoding/xml`'s built-ins, no per-directory override and no merge. Both
consumers read exactly one file: `Load(path)` → `os.ReadFile` → parse
(`api-cli/config.go:420-435`; `api-mirror/load.go:16-29`).

api-cli's only concession is `Config.Dir` (`config.go:33-36`), recorded so a `<tml src=>` resolves
relative to the config file "rather than wherever the shell happens to sit."

**Disposition: CONSUMER, if wanted at all.** A wrapper reading a project-level config plus a
user-level one would merge **after** parse, at the struct level — which is straightforward because
every config struct is plain data (`template-runtime.md` §8). Doing it at the DOM level is impossible:
`Node` has no exported fields and `ParseDOM` is its only constructor (`dom.go:13-18`), so two DOMs
cannot be spliced. Record that as a hard constraint.

---

## 12. No reconstructible DOM / no XML output

**Gap.** `Node` cannot be built programmatically or serialized back to XML. All fields unexported, no
setters, no `MarshalXML`, no `String()`. Consequence: no config generator, no formatter, no
round-trip, no migration tool.

**Disposition: CONSUMER (work at the struct level) or DSL-ADD.** Everything a tool would want to emit
lives in the consumer's own structs, which already carry `json` tags and even custom marshallers
(`api-cli/config.go:262-296`, `:137-172`). Emitting XML from those is ordinary Go. Adding a builder to
api-dsl would be additive but serves nobody today.

---

## 13. No validation vocabulary; everything is hand-written Go

**Gap.** api-dsl offers `CheckAttrs` and nothing else. Every semantic rule is a hand-written `if` in a
consumer: `api-cli/config.go` has ~310 lines of `validate*`, `api-mirror/validate.go` has 766.
Neither has a mechanism connecting a rule to its documentation — api-cli-spec's "what a schema cannot
state" table (`api-cli-spec/README.md:70-88`) lists 17 such rules, each of which corresponds to a
`validate*` clause kept in step **by hand**, with nothing checking the correspondence.

**Disposition: CONSUMER.** This is the design's accepted cost and both consumers pay it happily,
because a hand-written check produces a far better message than a schema violation. Copy the two
message standards instead of trying to generalise:
- api-mirror: *"Every check here exists because its absence is a silent failure at runtime"*
  (`validate.go:26-28`) — the message says what would go wrong.
- api-cli: the message names the alternative shape (`config.go:522`, `:651`; `runnable.go:388`;
  `steps.go:173`; `request.go:270`).

And copy api-mirror's stricter rule that **a declaration which would do nothing is a load error**
(`validate.go:119`, `:126`, `:207`, `:359`).

---

## 14. No grammar tier is obviously right, and all three exist

**Gap (a decision, not a missing feature).** Three live approaches, none of which api-dsl provides:

| tier | what it is | cost | catches |
|---|---|---|---|
| heavy | `api-cli-spec`: a separate module with an XSD, a `resolved.xsd`, a reference reader, and a conformance suite over paired `testdata/x.xml` + `x.resolved.xml` | a second module and a cross-module version bump per grammar change | structure, attribute types, mutual exclusions expressible in XSD, **and** the effective-settings semantics |
| light | `api-mirror`: `mirror.schema.xsd` at the repo root, not enforced at load; `schema_xsd_test.go` (~130 lines) asserts one direction only — every element and attribute a shipped spec **uses** is **declared** in the XSD | one file plus one test, no external validator | an editor completing a name the loader rejects |
| none | `CheckAttrs` + the child-switch `default:` only | zero | a typo'd attribute or element, at load, with a good message |

**Disposition: CONSUMER.** A single-consumer language has nobody to conform *to*, which removes most
of the heavy tier's argument. The **resolved-form idea is separable from the XSD question** and is
worth taking on its own: a checked-in table of `(node → effective setting, and the node that declared
it)` for every inheritable setting, asserted against a reference reader, is ~75 lines of Go plus two
files per case (`api-cli-spec/resolve.go:58-132`) — and it writes down the one thing the source
document never states.

One mechanical note if an XSD is written at all: **a placeholder can appear inside any element's
content**, so it cannot be declared per site. api-cli-spec solves this with a shared mixed-content
type referenced everywhere; api-mirror solves it by exempting the six placeholder names from the
coverage test (`schema_xsd_test.go:63-66`).

---

## 15. Two execution hosts means two copies of the runner

**Gap (a cost to avoid, not a missing feature).** api-cli's MCP path is a hand-maintained second copy
of the leaf runner: `mcpExecLeaf` (`mcp_exec.go:13-115`) re-implements `runLeafOnce`
(`build.go:218-364`), and `collectMCPLeaves`'s `mcpInherit` (`mcp.go:70-80`) re-implements
`buildCommand`'s inheritance threading (`build.go:40-145`). CLAUDE.md rule 1 makes it explicit:
*"buildCommand (build.go) and collectMCPLeaves (mcp.go) each thread it, so a new inheritable field
needs both paths."*

api-cli **did** factor out the parts that could be shared: `runSteps` takes an injected
`stepCapture` + `errOut` (`steps.go:44`, `:20-23`), `resolveContext` is shared (`mcp_exec.go:20`), and
`renderFieldsBlocks` is shared (`mcp_exec.go:101`). The duplication is in the *orchestration*, where
I/O ownership genuinely differs.

**Disposition: CONSUMER — design it away.** If api-cache has one execution host, the cost is zero. If
it grows a second (a daemon, a server mode), factor the leaf runner with an injected I/O policy
**before** writing the second host, not after.

---

## 16. Summary: what must change in api-dsl

**Nothing must.** Every gap above is either consumer vocabulary, a `NewRenderer` helper, or a design
decision. api-cache can be built on api-dsl exactly as it is, with zero forks and zero shared changes.

Three **additive** changes would help api-cache and would not break either existing consumer. They are
worth proposing separately, and none is a prerequisite:

| change | why | who else benefits |
|---|---|---|
| `Renderer.Prepare(src)` / `RenderPrepared(name, data)`, or an internal parse cache | removes 95%+ of a render's cost (`template-runtime.md` §3) | both consumers, marginally |
| `apidsl.PureFuncMap()` — sprig minus `env`, `expandenv`, `getHostByName`, `now`, `uuidv4`, the random family | determinism for anything deriving a key; also 5x faster | api-mirror (whose renders feed stored rows) |
| `Node.Pos()` | line numbers in load errors | both consumers |

If none of them lands, the consumer-local equivalents are: hold your own
`map[string]*template.Template`; shadow the impure names via `NewRenderer(extra...)`; keep building
positional `where` strings.

---

# Addendum — evidence for the argv-rule-surface question

Four specific questions, answered as evidence. None of the findings favours a particular shape for
api-cache's rule surface; each constrains **every** candidate shape (a declarative table, an
api-cli-style steps-and-templates arrangement, or a hybrid).

---

## A. What `passthroughParse` and `<flag>` actually give you, and where each stops

### The declaration

`<flag>` accepts exactly seven attributes (`buildFlag`, `api-cli/xmlsource.go:421-463`;
`checkAttrs` list at `:422`):

| attribute | type | parsed at | notes |
|---|---|---|---|
| `name` | non-empty string | load | may not start with `no-` (`config.go:630-632`) |
| `short` | one character | load | `shortFlag` in the XSD is `xs:length 1` + `[^\s]` (`api-cli-spec/api-cli.xsd:543-547`) |
| `type` | `string\|bool\|int\|string-slice` (empty ⇒ `string`) | load | `validFlagTypes`, `config.go:406` |
| `default` | typed per `type=` | load | `HasAttr("default")` distinguishes absent from empty (`:439`); a `string` default containing `{{` is a **template** rendered at invocation (`flags.go:168-176`) |
| `required` | bool | load | |
| `conflicts` | comma-separated sibling names | load, split at `:432-438` | validated against declared siblings (`config.go:634-644`) |
| `description` | string | load | |

`<arg>` is the positional sibling, with `name`, `type` (`string\|int`), `required`, `variadic`,
**`pattern`** (a Go regex), `description` (`buildArg`, `xmlsource.go:407-419`;
`api-cli-spec/api-cli.xsd:528-540`).

**`pattern=` is the only attribute in the whole language that classifies a value.** It sits on `<arg>`
and not on `<flag>`. It is compiled once at load, and a pattern that does not compile is a load error
naming the regex (`runnable.go:379-382`); `argPatterns` then uses `MustCompile` because the load
already proved it (`:397-406`).

### The parser

`passthroughParse(rawArgs, flags) (flagMap, rest)` — `api-cli/flags.go:204-316`, 112 lines, no
dependency on cobra. It builds a lookup from **long name and `short=`** to a `{name, typ}` pair
(`:209-221`), pre-fills every declared flag with its default (`:223-248`), then scans:

```go
if arg == "--" { rest = append(rest, rawArgs[i:]...); break }      // :254-257
if !strings.HasPrefix(arg, "-") { rest = append(rest, arg); continue }  // :259-262
stripped := strings.TrimLeft(arg, "-")                             // :264  — one OR two dashes
name, value, hasEquals := split on the first '='                   // :266-272
def, known := lookup[name]; if !known { rest = append(rest, arg); continue }  // :274-278
switch def.typ {
case "bool":         // consumes no value; `=true|1|yes` honoured    :281-287
case "int":          // `=v` or the NEXT arg                          :287-296
case "string-slice": // `=v` or the NEXT arg, APPENDED                :297-305
default:             // string: `=v` or the NEXT arg                  :306-312
}
```

`strings.TrimLeft(arg, "-")` is deliberate: the comment at `:200-201` says it exists "to support tools
like CUDA's `cicc` that use single-dash long flags". README:609 restates it — *"Both `-o` and `--o`
match."*

### What it can express today

- Which flags are known, by long name or one-character short.
- A flag's **arity**, indirectly: `bool` takes no value; everything else takes `=v` or the next
  argument.
- A repeated flag: `string-slice` accumulates; every other type is last-wins.
- A default per flag, and for a `string` a **templated** default (`flags.go:168-176`).
- That everything unrecognised, in original relative order, is `.rest`
  (`:250`, `:259-262`, `:274-278`) — and `{{spread .rest}}` rebuilds the remaining command line
  (README:611).

### Where it stops — each of these is a real limitation, not a style choice

1. **No role.** A flag is `string|bool|int|string-slice` and nothing else. There is no attribute for
   "this names an output file", "this names an input", "this is cache-irrelevant", "this forces a
   bypass". `validFlagTypes` (`config.go:406`) is a closed four-value set checked at load.
2. **No pattern on a flag.** `pattern=` exists only on `<arg>` (`xmlsource.go:408`). A flag's *value*
   is never validated or classified.
3. **No attached-value short form.** `-O2` strips to the name `O2`, finds no declared flag, and goes
   to `.rest` verbatim (`:264`, `:274-278`). `-DFOO=1` strips to name `DFOO`, value `1` — so it is
   only recognised if a flag literally named `DFOO` is declared. The common compiler forms
   (`-I/usr/include`, `-DNAME=value`, `-Wl,-rpath`) are all invisible to the declaration layer and land
   in `.rest` as opaque strings.
4. **No clustered shorts.** `-abc` is one token; there is no splitting into `-a -b -c`.
5. **No prefix or glob matching.** Lookup is an exact map hit (`:274`). A rule covering "every flag
   starting with `-W`" cannot be declared.
6. **Absolute position is lost.** `.rest` preserves the *relative* order of what it kept, but an
   extracted flag's index is gone, and `flagMap` is a map — so nothing records that `-o` appeared
   before `-c`. A rule surface that needs "the argument after `-o`" has it (next-arg consumption);
   a rule surface that needs "where in the line this appeared" does not.
7. **Failure is silent by construction.** An unrecognised flag is not an error; it is `.rest`
   (`:274-278`). A malformed value is not an error either: the `int` case does
   `n, _ := strconv.Atoi(raw)` and **discards the error** (`:295`), so `--jobs abc` yields `0`. That
   is the opposite of the load-time strictness the rest of the language applies, and it is the one
   place in api-cli where a user mistake becomes a silent wrong value rather than a message.
8. **It is not the cobra path.** `passthrough="true"` swaps out cobra entirely
   (`build.go:64-65` sets `cobra.ArbitraryArgs`; `build.go:222-227` branches to `passthroughParse`),
   so nothing in the cobra flag machinery — required flags, conflicts, `--no-NAME` negation
   (`flags.go:28-35`, `:180-185`) — applies in passthrough mode. `registerConflicts`
   (`flags.go:64-81`) is never reached. `validateCommand` still validates `conflicts=` against declared
   siblings (`config.go:634-644`), so a passthrough config can declare a conflict that is checked at
   load and then never enforced at run time.

### The growth path, mechanically

Adding attributes to `<flag>` is cheap and local: one `checkAttrs` string (`xmlsource.go:422`), one
struct field (`config.go:235-243`), one line in `buildFlag`, one clause in `validateCommand`. Adding a
*new element* — a `<rule>`, a `<classify>`, a table — is equally cheap and reaches nothing shared:
`addCommandChild`'s switch (`xmlsource.go:299-405`) is the only dispatch point.

Two structural cues from the family if a table is written:

- **Compile every pattern at load, fail there, and `MustCompile` afterwards** — `runnable.go:379-406`
  is the two-step.
- **Make an ambiguous rule a load error whose message names the fix.** `validateRunnable:386-390` is
  the exact template: *"pattern %q matches the subcommand name %q, so %q would be ambiguous; narrow
  the pattern (anchor it with ^ and $)"*. Two rules matching one flag is the same failure mode.

---

## B. Does the DOM's order preservation matter for a rule table? Yes, and it is already load-bearing

### What api-dsl guarantees

`Node.Content()` returns mixed content **in document order** (`api-dsl/dom.go:49-50`);
`Node.Children()` filters that to elements, preserving order (`:53-61`); `Node.Attrs()` returns
attributes in document order (`:46-47`). `ParseDOM` appends to `p.content` in token order
(`:100`, `:115`). Order preservation is the module's stated reason for existing at all
(`doc.go:5-6`: *"an order-preserving XML DOM ... which keeps mixed content in document order so a
placeholder inside text survives the parse"*).

**Attribute order is preserved too** (`Attrs() []Attr`, pinned by `dom_test.go:50-57`) — though no
consumer uses it, and `CheckAttrs` iterates the slice only to reject unknowns (`dom.go:153-157`).

### Where both consumers already depend on sibling order

Every builder appends in `Children()` order, so document order becomes slice order:

| declaration | order means | cite |
|---|---|---|
| `<arg>` | **positional index** — arg 0 is `args[0]` | `xmlsource.go:306`, `flags.go:97-131` |
| `<argv>` | argv slot order | `xmlsource.go:145-155` |
| `<step>` | execution order; a later step reads `.result` of earlier ones | `xmlsource.go:363`, `steps.go:46` |
| `<field>` | **column order** in every sink | `xmlsource.go:186` |
| `<fields>` block | render order of matching blocks | `config.go:390-399`, `format.go:419` |
| `<view>` | first matching `when=` wins, else first `default=`, else `views[0]` | `format.go:196-216` |
| `<header>` / `<param>` | render and emission order | `xmlrequest.go:417`, `:478` |
| `<command>` | help listing order, and the order `validateRunnable` checks patterns against ("A config author reads the first match, so it must be the name they are most likely to have meant", `runnable.go:359-362`) |
| api-mirror `<key>` / `<field>` | **primary-key and column order**, derived once and reused by every read and write | `schema.go:48-52`, `:76-88` |
| api-mirror `<var>` | evaluation order — each var sees the ones before it | `engine.go:113-124` |

api-mirror states the strongest version: `columnsOf` exists so that *"a column can never be written in
one order and read in another"* (`schema.go:74-75`).

### The nuance the grammar layer records

api-cli-spec's README:58-60 says *"Child elements are order-free"* and every structural element uses
`xs:all` rather than `xs:sequence`. That is about **different element names**: `<fields>` before
`<run>` means the same as after it. It says nothing about siblings of the *same* name, and
api-cli-spec's own "what a schema cannot state" table lists exactly that as a rule XSD cannot carry:
*"A variadic arg comes last, and a required arg never follows an optional one — Order among siblings
of one name"* (`api-cli-spec/README.md:82`).

### So, for a rule table

The transport is free: order among same-named siblings survives parse, and both consumers already rely
on it. The decision is semantic, and it has to be **stated**, because the reader cannot infer it:

- **Ordered / first-match-wins** costs nothing and makes an overlay natural (prepend a rule). It
  matches how `<view>` and `<step>` already read. The risk is a shadowed rule nobody notices.
- **Unordered / all-must-be-unambiguous** needs a load-time overlap check, which is harder to write
  but turns a shadowed rule into a load error. `validateRunnable`'s pattern-vs-subcommand check
  (`runnable.go:386-390`) is the nearest existing example of that kind of check, and it is 5 lines
  because the candidate set is small; over a table of N patterns it is O(N²) regex-vs-regex, which is
  undecidable in general — in practice one tests each rule's pattern against every *other rule's
  literal name or sample*, not against the pattern.

Whichever is chosen, `<field>`'s and `<key>`'s precedent says: if the order is load-bearing, derive it
once into a named accessor (`columnsOf`) and make every consumer of the order go through it.

---

## C. Overlays and includes: nothing in the family supports them

**Answer: no. Neither repository has any form of include, import, overlay, layered config, or
document merge. This was checked directly and comes back empty.**

- `Load(path)` is `os.ReadFile` → `parseConfigXML` → `validate` (`api-cli/config.go:420-435`) and
  `os.ReadFile` → `ParseSpec` → `validate` (`api-mirror/load.go:16-29`). One file, one call, no
  second path.
- `ParseDOM([]byte)` takes one document (`api-dsl/dom.go:71`) and errors on a second top-level element
  (`:106-110`). There is no entity resolution beyond `encoding/xml`'s built-ins, and
  `dec.Strict = true` (`:73`).
- Config discovery is two steps and stops at the first hit: `--config <path>`, else `./api.xml`
  (`api-cli/README.md:914-920`, `preparseGlobalFlags` in `main.go`). There is no user-level file, no
  `$XDG_CONFIG_HOME` lookup, no directory walk upward.
- A grep for `merge`/`include`/`overlay` across both repositories returns only: `mergeVars` (vars down
  one tree, below), `includedFields` (a `show_in` filter in the `fields` package,
  `fields/fields.go:124-125`), sprig's `mergeOverwrite`, and api-mirror's `Ingest.merge`
  (`events.go:364-392`, which overlays a webhook payload's named fields onto a **stored database
  row**, not onto a spec).

### The two things that do exist, and exactly how far they go

1. **`mergeVars` down the command tree.** `apidsl.MergeVars(parent, child)`
   (`api-dsl/render.go:153-162`) is a **shallow** map merge, child wins per key, always a fresh map.
   api-cli calls it once per node in `buildCommand` (`build.go:96`) and once in the MCP walk
   (`mcp.go:166`). It merges **only `<vars>`**, only **within one document**, and only **down a
   parent-child chain**. Nothing else inherits by merging — `<run>`, `cwd`, `stdin`, `confirm`,
   `format` are **replaced wholesale** by the nearest declaring ancestor
   (`build.go:96-121`), and a `<run>` of one kind **clears** an inherited run of the other
   (`:99-105`). api-cli-spec's resolution rules state this as *"A `<run>` replaces an inherited one
   entirely"* (`api-cli-spec/README.md:39`).
2. **`Config.Dir`.** The directory the config was read from, recorded at `config.go:433` so a
   `<tml src=>` resolves against it "rather than wherever the shell happens to sit"
   (`config.go:33-36`). That is a *file reference for a sub-asset*, not an include: `loadTMLView`
   (`tmlview.go`) reads a tml template, not another config document.

### What an overlay would cost, and where it has to happen

**It cannot happen at the DOM level.** `apidsl.Node` has every field unexported and `ParseDOM` is its
only constructor (`dom.go:13-18`, `:71`); there is no builder, no setter, no `AddChild`. Two parsed
documents cannot be spliced, and a merged DOM cannot be synthesised and then walked.

**It can happen at the struct level**, and cheaply, because every config struct is plain data with
`json` tags (`api-cli/config.go:20-37`, `:71-92`; `Cmd` and `FormatRef` even carry custom
marshallers at `:262-296`, `:137-172`). Parse both documents into the same structs, then merge the
structs under a stated rule. The rule is the hard part and the language offers no precedent for it:
`mergeVars` is the only merge, it is shallow, and it is over a `map[string]any` — whereas a rule table
is a **slice**, where "merge" has to choose between append, prepend, replace-by-key, and
replace-wholesale, and the choice interacts with question B's ordered-vs-unordered decision.

**The third option the family does use for this problem is a registry plus a reference.** `<formats>`
+ `<format ref="name">` (`xmlsource.go:516-528`, resolved by `resolveFormat`, `format.go:35-43`) and
`<transports>` + `transport="name"` (`transport.go:118-134`) both let a declaration name a shared,
separately-declared thing without merging documents. api-cli-spec notes that a `ref=` crossing from a
command to the top-level registry is precisely what an XSD identity constraint cannot check
(`api-cli-spec/README.md:88`), so it is validated in Go (`config.go:730-734`).

---

## D. Binary-safe capture of a program's stdout, and hashing rather than parsing it

### The step path: byte-exact capture, then a lossy store

`captureExec` (`api-cli/exec.go:71-105`) sets `cmd.Stdout = &buf` (a `bytes.Buffer`) and returns
`buf.String()`. A Go `string` holds arbitrary bytes, so **the capture itself is byte-exact** — NUL
bytes, invalid UTF-8 and binary all survive. The same is true of `captureExecTo` (`:111-134`) and
`captureExecCapped` (`:144-182`).

**What happens next is not.** `runSteps` stores `results[step.Name] = parseResult(out)`
(`steps.go:89`), and `parseResult` (`exec.go:218-233`) opens with:

```go
s = strings.TrimSpace(s)
dec := json.NewDecoder(strings.NewReader(s)); dec.UseNumber()
var v any
if err := dec.Decode(&v); err != nil { return s }   // not JSON: the TRIMMED raw string
```

So by the time a template can see a step's output:

- **Leading and trailing whitespace is gone, unconditionally.** `TrimSpace` runs before the JSON
  attempt and its result is what is returned on the non-JSON path. A trailing newline — which every
  `sha256sum`, `md5sum` and `cksum` emits — is removed. That is *convenient* for a digest and
  *destructive* for bytes.
- **Valid-JSON output is decoded and re-shaped**, then `normalizeNumbers` rewrites every
  `json.Number` to `int64`/`float64` (`:238-261`). A program whose stdout happens to be valid JSON
  cannot get its exact bytes back out.
- **There is no opt-out.** `<step>` accepts `name`, `when`, `over`, `until`, `interval`, `attempts`
  (`xmlsource.go:466`) — no `input=`/`raw=`/`capture=` attribute. Contrast `<format input="json|
  lines|raw">` (`config.go:414`, `parseInput` `format.go:165-178`), which **does** have the knob, but
  applies only to the presentation of a leaf's final output, never to a step's stored result.
- Even `raw` there is `strings.TrimRight(s, "\n")` (`format.go:174`), so no path in api-cli preserves a
  trailing newline.

There is also **no way for a config to hash a step's output.** The only hash functions reachable from
a template are sprig's `sha1sum`, `sha256sum`, `adler32sum` — all `string → hex string`, all going
through the same trimmed value, with no `sha512`, no streaming, and no size limit
(`template-runtime.md` §10).

### The download path: genuinely binary-safe, streaming, hashed — but pointed the wrong way

`fetchViaTransport` (`api-cli/downloader.go:329-358`) runs a program and streams its stdout straight
to disk:

```go
cmd.Stdout = pf.sink            // :346
cmd.Stderr = item.batch.errOut  // :347
```

`pf.sink` is an `io.MultiWriter` over the `.part` file, the progress counter, and — when the
declaration supplied a digest — the hasher (`openPart`, `:397-401`):

```go
sink := []io.Writer{f, item}
if pf.digest = newHasher(item.spec.HashAlgo, item.spec.Hash); pf.digest != nil { sink = append(sink, pf.digest) }
pf.sink = io.MultiWriter(sink...)
```

The comment says why (`:395-396`): *"Digested on the way past, so verifying costs no second pass over
a file that may not fit in memory or in the page cache."* `commit` (`:407-425`) closes, compares
`hex.EncodeToString(p.digest.Sum(nil))` against the expected value, and only then renames the `.part`
to the real name — a mismatch deletes the file and is final, "an answer, not a hiccup" (`:413-415`).
`newHasher` (`:435-449`) covers `md5`, `sha1`, `sha256` (default) and `sha512`.

**So every mechanical piece of "run a program, stream its stdout, hash it as it goes, never hold it in
memory" already exists in this codebase.** Three things point it the wrong way for a cache:

1. **Direction.** The hash is *verified against a declared expectation* (`<hash algo=>` renders to a
   hex string, `download.go:471-499`), never *produced as a value the configuration can read*. There
   is no `.result.<name>.hash`, no `.digest`, nothing.
2. **Destination.** The bytes go to a file, and the config's access to that file is its path
   (`downloadDest`, `:506+`). The Go side keeps `p.digest`; nothing surfaces it.
3. **Trigger.** It is reachable only from a `<download>` leaf, which "stands in for the leaf's `<run>`"
   (api-cli CLAUDE.md rule 5) and runs after the steps. A step cannot use this path.

### What this means for a preprocess-and-hash step

Whatever shape api-cache's rule surface takes, "run the preprocessor, hash its stdout" needs **new
consumer code**, not new language:

- The streaming-hash writer already exists in a copyable form (`openPart`/`partFile`/`commit`,
  `downloader.go:363-431`) and is ~70 lines including the `.part`-sibling and rename discipline.
- The step loop already supports an injected capture function — `stepCapture`
  (`steps.go:20-23`) is `func(c *Cmd, cwd, stdin string, data any) (string, int)`, supplied by the
  caller, which is how the CLI and MCP paths share one loop (`build.go:305`, `mcp_exec.go:49-52`). A
  third capture that hashes instead of buffering fits that seam, though the **signature returns a
  `string`**, so a digest-producing variant either returns the hex digest in that slot or the
  signature widens.
- The thing that must be decided in the *vocabulary*, because no existing element carries it, is
  **what a step's output means**: bytes to hash, JSON to read, a path to a file, or a list of paths.
  `<format input=>` (`config.go:414`) is the only precedent for that kind of knob anywhere in the
  language, and it lives on presentation rather than on a step.
- **`missingkey=zero` remains the hazard** on any template feeding this: a mistyped path renders
  `<no value>` and produces a stable wrong digest rather than an error
  (`api-dsl/render_test.go:161-169`). api-cli's answer is a post-render shape check —
  `renderHash` rejects anything that is not an N-character hex string, "rather than leave the file
  unverified in silence" (`download.go:493-497`, `README.md:303`). Any digest or key a template
  produces needs the same guard.

**None of this needs a change to api-dsl.** Byte handling was never in the language layer, in either
consumer, by design: the config names *which* file, *which* algorithm and *which* expectation, and Go
moves the bytes.
