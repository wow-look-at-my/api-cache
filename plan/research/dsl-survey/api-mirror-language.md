# api-mirror — the second consumer, and the design patterns worth copying

Module `github.com/wow-look-at-my/api-mirror`, Go 1.26, MIT (`/home/user/api-mirror/LICENSE:1`).
The engine is one package, `internal/mirror` (~70 source files); `cmd/api-mirror` holds nothing else.
Dependencies: api-dsl, testify, `go-containers`, `modernc.org/sqlite` (pure-Go SQLite, BSD-3-Clause).
**No cobra, no sprig beyond what api-dsl pulls in, no third-party router.**

The vocabulary is not api-cache's vocabulary, so this file records the *patterns*. Section 8 is the
extract.

---

## 1. The api-dsl boundary: `internal/mirror/dsl.go` (25 lines)

```go
var (
	renderString   = apidsl.RenderString     // :9   — note: RenderString, NOT a Renderer
	lookupPath     = apidsl.LookupPath       // :10
	isTruthy       = apidsl.IsTruthy         // :11
	envMap         = apidsl.EnvMap           // :12
)
type node = apidsl.Node                     // :16
var checkAttrs = apidsl.CheckAttrs          // :19
var (
	parseDOM       = apidsl.ParseDOM         // :22
	compileContent = apidsl.CompileContent   // :23
	textOf         = apidsl.TextOf           // :24
)
```

**Two consumers, two nearly identical boundary files** (compare `api-cli/dsl.go`). The differences
are instructive:

| | api-cli | api-mirror |
|---|---|---|
| renderer | `apidsl.NewRenderer(cliFuncs())`, own helpers | bare `apidsl.RenderString` — **no consumer helpers at all** |
| `CompileTextElem` | used | not aliased; uses `compileContent` + its own `checkAttrs` |
| `IsPlaceholder` | used (in `entryValue`) | not used |
| `MergeVars` | used | not used (vars resolve in declaration order, §4) |
| `Truthy` (func) | aliased as `templateTruthy` | not used; only the string form |

So the *minimum* a consumer needs is: `parseDOM`, `checkAttrs`, `compileContent`, `textOf`,
`renderString`, and usually `lookupPath` + `isTruthy` + `envMap`. Everything else is optional.

---

## 2. Load: builders check shape, validate checks meaning

`Load` (`load.go:16-29`) — the same four-step shape as api-cli's:

```go
os.ReadFile → ParseSpec(raw) → spec.validate() → return
```

The doc comment states the split outright (`load.go:12-15`):

> Parsing and validation are separate steps on purpose: a builder checks the SHAPE of the file (an
> unknown element, a missing attribute), and validate checks what the shape MEANS (a route pointing
> at nothing, a resource nobody [gated]).

`ParseSpec` (`:32-41`): `parseDOM` → **root check `<mirror>` in the consumer** (`:37-39`) →
`buildSpec`. `buildSpec` (`:43-140`) is one `switch child.Name()` over ~16 element names, each
delegating to a `build*` function, with a `default:` that rejects the unknown child.

Builders live in `load.go` (the core grammar), `load_events.go` (the webhook half),
`load_ops.go` (`<dashboard>`, `<cors>`, `<notify>`, `<refresh>`, `<replay>`, `<health>`,
`<ratelimit>`). Validators live in `validate.go` (766 lines) split into `validate()` and
`validateOps()`, plus `schema.go`'s `validateNames`.

`validate.go`'s file comment (`:26-28`):

> validate rejects a spec the engine cannot serve honestly. Every check here exists because its
> absence is a silent failure at runtime: a resource nobody gated, a route pointing at nothing, an
> invalidation with no stated reason.

### The error-message standard

Every message names the element, the offending value, and **what goes wrong at run time if it is
allowed**. A sample, from `validate.go`:

- `:136` — `resource %q needs at least one <key>: a fact with no identity cannot be stored once`
- `:158` — `resource %q stores columns but declares no <field>: it would serve an empty answer`
- `:189` — `<keep name=%q> needs a reason naming the consumer that needs the field -- an unexplained hole in the drop rule is how a URL key creeps back`
- `:196` — `resource %q has no <reveal>: a stored fact with no rule about who may read it cannot be served`
- `:207` — `<credential/> already gates every read; a <public> or <probe> alongside it is dead code`
- `:219` — `<probe> needs a <grant ttl=>: a proof that never expires is not a proof`
- `:326` — `give it a default or mark it key="true" -- an unkeyed parameter with no default lets two different requests share one cached answer`
- `:339` — `refusing to absorb %d -- a transient failure stored is an outage remembered long after it ended`
- `:108` — `<replay> needs both <list> and <redeliver>: listing failures it cannot ask back is not recovery`
- `:126` — `<cors> names no <origin>, so it would allow nothing while looking like a policy`
- `:353` — `rewrite %s: drop the trailing slash, the prefix already matches a path under it`
- `:359` — `rewrite %s: from and to are the same, so this rule does nothing`

Note the class at `:126`, `:359`, `:119` (`<notify> has nothing to announce: this spec declares no
<events>`): **a declaration that would do nothing is a load error**, not an ignored no-op. That is a
stricter rule than api-cli applies and it is cheap to copy.

---

## 3. How templates are actually used

Very sparingly, and only where a value genuinely varies. The complete list of render sites
(grep across `internal/mirror/*.go`, excluding tests):

| site | file:line | context handed to the template |
|---|---|---|
| var values | `engine.go:117` | `{env, var}` |
| `<upstream base=>` | `upstream.go:31` | vars |
| upstream `<header>` name/value | `upstream.go:80`, `:84` | vars |
| `<dashboard><token>` | `admin.go:34` | vars |
| `<events><secret>` | `events.go:59` | `{env, var}` |
| `<field expr=>` | `absorb.go:56` | **the upstream document itself** |
| `<set expr=>` | `events.go:403` | `{payload}` |
| `<subject>` | `ordering.go:31` | `{payload}` |
| `<reveal><public>` | `reveal.go:123` | `{key, row, ...}` via `rv.context(key,row)` |
| `<probe path=>` | `reveal.go:257` | `rv.context(key, nil)` |
| `<replay><redeliver>` | `replay.go:190` | `{delivery}` |
| `<notify db=>` | `notify.go:56` | vars |

Everything else is a **path**, resolved at run time with `lookupPath` (`absorb.go:26`, `:62`,
`ordering.go:41`, `replay.go:51`, `paths.go:19`, `:38`). A resource `<field>` body is a *path*;
`expr=` is the escape hatch, and `validate.go:181` makes them mutually exclusive and mandatory:
`give it a source path or an expr, not both and not neither` — exactly the shape api-cli uses for
`<field>` (`xmlsource.go:211-216`) and api-dsl uses for `<value>` (`compile.go:186-192`).

`paths.go:10-12` notes the engine wraps `lookupPath` rather than calling it directly, "because they
carry the engine's reading of an absent value".

---

## 4. Vars: declaration order, not a fixpoint

`resolveVars` (`engine.go:113-124`):

```go
vars := map[string]any{}
ctx := map[string]any{"env": envMap(), "var": vars}
for _, v := range spec.Vars {           // declaration order
	s, _ := renderString(v.Value, ctx)  // sees the vars BEFORE it
	vars[v.Name] = s
}
return ctx, nil                          // the whole context, not just the vars
```

Strictly simpler than api-cli's two-pass fixpoint (`api-cli/build.go:408-475`), and it is enough
because api-mirror has **no flags and no per-invocation context**. Vars resolve **once at engine
construction**, not per request. Note `Vars` is a `[]Var` here (ordered) versus api-cli's
`map[string]any` (unordered, hence the fixpoint).

That is the trade a planner should see explicitly: *ordered list + one pass* versus *map + fixpoint*.
The first is 12 lines and gives the author a stated evaluation order; the second is 45 lines and lets
an author write vars in any order.

---

## 5. The derived schema and the fingerprint (`schema.go`)

The single most transferable mechanic for a cache.

- `resourceDDL(r)` (`:32-54`) builds `CREATE TABLE res_<name> (...)` from the declared `<key>`s (as
  `TEXT NOT NULL`, and as the `PRIMARY KEY`) and `<field>`s (`sqlType`, `:18-25`), plus the engine's
  own `mirror_written_at INTEGER NOT NULL`.
- `Spec.DDL()` (`:58-66`) = the engine's fixed `schema.sql` + each resource's DDL in declared order.
- **`Spec.Fingerprint()` (`:69-71`) is `database.Fingerprint(s.DDL())` — a hash of the derived DDL
  text.** CLAUDE.md states the invariant: *"The fingerprint is derived, never declared. It hashes the
  schema the spec produces, so a resource change always nukes and nothing has to be kept in step by
  hand."* README:57 restates it: *"Editing a resource rebuilds the cache on the next start, with no
  migration and no version constant to forget."*

Compare go-s3-server, which uses a hand-maintained `currentCacheVersion` constant an operator must
remember to bump (`go-s3-server/CLAUDE.md`, `cacheversion.go`). api-mirror's derivation is strictly
better for anything whose invalidation condition is "the config changed".

- `columnsOf(r)` (`:76-88`) returns the stored columns in **one stable order** (keys as declared,
  then fields as declared). *"Every write and read builds its statement from this, so a column can
  never be written in order and read in another."*
- `validateNames` (`:96-114`) + `validateIdent` (`:119-137`): a name must be
  `[a-z][a-z0-9_]*`, must not collide with `reservedColumns` (`:91`: `mirror_written_at`,
  `document`, `rowid`), must not start with the `mirror_` engine prefix (`:12`), and must not be one
  of 30 hand-picked SQL keywords (`:142-148`). Rationale at `:116-118`: *"Refusing everything else
  means the engine never has to guess how to quote a name."*

---

## 6. The XSD, used far more lightly than api-cli's

`mirror.schema.xsd` (12.9 KB) sits at the repo root and is **not enforced at load** (CLAUDE.md:
*"the reference grammar. Not enforced at load; a test walks the shipped specs against it"*).

`schema_xsd_test.go` does **name coverage, in one direction only**
(`schema_xsd_test.go:14-16`):

> A name a spec uses and the XSD does not know is the editor lying. The reverse is not drift, so this
> walk runs in that direction only.

`declaredNames` (`:36-67`) tokenizes the XSD with `encoding/xml` and collects every
`<xs:element name=>` and `<xs:attribute name=>`. `namesUsedBy` (`:70-96`) tokenizes each shipped spec
and collects every element and attribute actually used. The assertion is that every used name is
declared. Two hand-maintained exceptions:

```go
// A placeholder is api-dsl's, shared with api-cli, and appears in any
// element's content rather than being declared per site.
return append(elements, "value", "if", "for", "else"),
       append(attributes, "test", "eq", "each", "expr", "as", "default")   // :63-66
```

That is a **third option** for api-cache's grammar story, cheaper than api-cli-spec's full
XSD-plus-resolved-form and stronger than nothing: ~130 lines of Go, no external validator, no second
module, and it catches the one failure that actually bites an author (the editor autocompleting a
name the loader rejects). It does not catch a structurally wrong document.

Note also that a placeholder appears **in any element's content**, so a schema that declares
placeholders per site is unwritable — api-cli-spec solves this by declaring a mixed-content type once
and referencing it everywhere; api-mirror solves it by exempting the four names from the test.

---

## 7. Other mechanisms worth noting individually

### A closed vocabulary of reasons
`router.go:11-22` — `PassReason` is a string type with **seven** constants and a comment per value:
`unrouted`, `unrouted-method`, `unmodeled-accept`, `unmodeled-query`, `unmodeled-response`,
`unverified-identity`, `relayed`. `reveal.go:20-27` does the same for `DenyReason`:
`probe-refused`, `cached-denial`, `no-proof`, `probe-inconclusive`, with the comment *"DenyReason
says which rung refused: 'denied' alone cannot be acted on."* `observe.go:13-23` does it a third time
for `Lane`: *"Lane is the grain the dashboard groups by; a lane it cannot name is a hole."*

Three independent instances of the same discipline: **when something falls out of the fast path,
the reason comes from a closed enumeration with one comment per value, and there is no "other".**

### A passthrough is unfinished work
CLAUDE.md: *"It is forwarded with a stated reason from a closed vocabulary. There is no 'correctly
uncached'."* `shapes.go` then turns "this request left" into "this family of requests is still
leaving" (`:12-13`) by generalizing paths (`generalize`, `:18-26`; `generalizeWith`, `:33+`, which
uses the spec's own vocabulary of declared path segments) — and the dashboard hands each family
**the `<resource>` and `<route>` sketch that would stop it leaking**.

The transferable shape: *a cache miss / fallback is not a neutral outcome; it is counted, grouped
into families, and each family is presented with the configuration that would eliminate it.*

### Observation lives in the transport
`observe.go:82-97`, `observedClient(base, lane, obs)` wraps a `*http.Client`'s `RoundTripper`:

> Observation lives in the TRANSPORT rather than at the call sites, because call sites only ever
> cover the calls somebody remembered to instrument. A client built here cannot make an invisible
> request.

`reportingBody` (`:152-169`) reports on `Close` with a `sync.Once`, "the call no consumer skips", so
the byte count is accurate. The lane rides in the `context.Context`
(`withLane`/`laneFrom`, `:53-60`) so one client serves several lanes.

### Fail closed
`reveal.go:53-59`: *"A failure anywhere refuses: a store error, a template that cannot render and a
row that is not there all mean the engine has no proof, and no proof is a refusal."* And in the
grammar, a resource with no `<reveal>` cannot be served at all (`validate.go:196`).

### Absorb, not replay
`absorb.go:12-17`: *"A field the spec does not declare is a field the mirror does not keep... the
answer's shape is the spec's, and it cannot drift with whatever the upstream added this week."*
`coerce` (`:69+`) types every value into the declared column type and **errors** on a value the type
cannot hold, because "[a zero] written here is indistinguishable from a real upstream [value]".

### Hit and miss share one path
CLAUDE.md invariant: *"An answer is rebuilt from stored state either way, so a route's shape never
changes with cache state."* Directly relevant: a build cache's hit and miss paths must produce
byte-identical observable results, and the way to guarantee that is to make them one code path.

### A background job with a missing precondition does not run
`<replay requires=>` (`replay.go:51`) names a value the failure log cannot be read without; empty
means the job declines to start and logs which value would start it. *"A cycle that can only fail,
forever, on a timer is a job that looks busy and recovers nothing."*

### Bounded, memory-only telemetry
CLAUDE.md: *"A live view, not an audit log ... Every store sweeps lazily and reports what it dropped
rather than truncating quietly."*

---

## 8. The extract: design patterns api-cache should copy

| # | Pattern | Where it is stated |
|---|---|---|
| 1 | **Builders check SHAPE, validate checks MEANING**, as two separate passes over the same tree. | `load.go:12-15`; mirrored in `api-cli/config.go:420-435` |
| 2 | **Every check exists because its absence is a silent runtime failure**, and the error message says what that failure would be. | `validate.go:26-28` and every message in §2 |
| 3 | **A declaration that would do nothing is a load error.** | `validate.go:119`, `:126`, `:207`, `:359` |
| 4 | **Fail closed**: unknown means refuse; a render error, a store error and a missing row are the same verdict. | `reveal.go:53-59`; CLAUDE.md |
| 5 | **A closed vocabulary of reasons**, one comment per value, no "other". | `router.go:11-22`, `reveal.go:20-27`, `observe.go:13-23` |
| 6 | **The fallback path is unfinished work**: counted, grouped into families, each shown the config that would remove it. | CLAUDE.md; `shapes.go:12-13` |
| 7 | **Derived fingerprints, never declared version constants.** Hash what the config produces; a config change invalidates by construction. | `schema.go:58-71`; CLAUDE.md |
| 8 | **Instrument the transport, not the call sites.** A client built through the wrapper cannot make an invisible request. | `observe.go:82-97` |
| 9 | **Hit and miss share one code path**, so the observable result never varies with cache state. | CLAUDE.md |
| 10 | **The engine owns every mechanism; the spec owns only vocabulary** — names, paths, which field carries what. | `docs/design.md:295-306` |
| 11 | **A stable, declared column/field order** that every read and write derives from, so nothing can be written in one order and read in another. | `schema.go:73-88` |
| 12 | **Identifier hygiene at load**: a restricted character set plus a reserved-name set plus an engine prefix, so no downstream layer has to guess how to quote or disambiguate. | `schema.go:96-148` |
| 13 | **A "requires=" precondition on a background job**, so a job that can only fail declines to start and says what would start it. | `replay.go:51`; `docs/design.md:272-275` |
| 14 | **Project into declared fields; never replay bytes you did not parse.** | `absorb.go:12-17`; `docs/design.md:82-83` |
| 15 | **State the invariants as a list, each with its "because"**, and keep it in CLAUDE.md next to the file map. | `/home/user/api-mirror/CLAUDE.md`, "Invariants" |

The closing line of `docs/design.md` is the framing sentence for the whole family of projects
(`:303-306`):

> ## What the spec owns
> Names. Paths. Which field carries the clock. What "public" means for this API. Nothing else.
