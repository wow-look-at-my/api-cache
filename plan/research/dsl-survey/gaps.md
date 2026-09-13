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
