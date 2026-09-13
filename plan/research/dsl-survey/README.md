# dsl-survey — the shared XML language, its two consumers, and what api-cache can reuse

Survey of `/home/user/api-dsl`, `/home/user/api-cli`, `/home/user/api-mirror` and
`/home/user/api-cli-spec`, written so a planner can design api-cache's vocabulary on the same
language with maximal reuse and zero forks.

## Files

| file | contents |
|---|---|
| `api-dsl.md` | Every exported symbol in `dom.go`, `compile.go`, `render.go` with signatures and line numbers. The compiled-form contract table verbatim. `FuncMap` contents, `NewRenderer`, `missingkey=zero`, `dedentTabs`, `CheckAttrs`, `ParseDOM`/`StripXMLDecl`/XML 1.1. A long list of what it does **not** provide. |
| `api-cli-language.md` | The full vocabulary as built: every element, its attributes, its builder (file:function), its validation, and every context path that exists at render time. The steps engine, the transports mechanism, the vars fixpoint, `<run>` inheritance and clearing, all twelve `cliFuncs` helpers, `asList`/`collect`/`spread`, the MCP path. The README's "Limits and workarounds" table verbatim. |
| `api-mirror-language.md` | The engine/spec split, builders-vs-validate, the `dsl.go` boundary compared against api-cli's, how templates are actually used (sparingly), the derived schema fingerprint, the light XSD approach. Ends with a 15-row table of **design patterns** to copy. |
| `api-cli-spec.md` | How the XSD is kept, what "resolved form" means and why it is the module's real invention, how a consumer embeds `spec.Schema` and validates in tests, the "what a schema cannot state" table verbatim, and what adding a new grammar actually costs. |
| `template-runtime.md` | The runtime model and **measured** cost profile. What a compiled template is, how `Render` is called, where the microseconds go, `missingkey=zero` precisely, `LookupPath` vs `DotPath`, `Truthy`'s exact semantics, the three-way "template / context path / literal" attribute, what a cooked form could be, and all 196 sprig function names. |
| `reuse-map.md` | A 46-row table: for each capability api-cache plausibly needs — reuse as-is / copy a pattern from file X / import a package / build new — with citations. Plus the transport pattern spelled out, and a dependency-and-license summary. |
| `gaps.md` | 16 gaps the language cannot express today, each with its evidence and whether the fix belongs in api-cache's own vocabulary, a `NewRenderer` helper, an additive api-dsl change, or a breaking one. Plus an **Addendum** with detailed evidence on argv flag declarations, sibling order, overlays/includes, and binary-safe capture. |

## Summary

api-dsl is 690 lines and does three things: an order-preserving XML DOM, a compiler turning
`<value>`/`<if>`/`<for>`/`<else>` into Go `text/template` source, and a renderer. It owns no
vocabulary, checks no root element, and has no schema, no includes, no source positions and no way to
build a `Node`. Its only dependency is sprig. Everything between "a compiled template string" and "a
running program" is consumer code, and both consumers write it the same way: a `dsl.go` boundary file
aliasing the shared API, builders that walk the DOM and call `CheckAttrs` on every element, then a
separate validate pass. **The minimum a new consumer needs from api-dsl is six functions.**

The most reusable mechanisms are api-cli's `<transport>` (a program stands in for a built-in
mechanism, with a stated I/O contract, a registry, a selection order, a reserved name for the
built-in, and a deferred-rendering variant for a worker) and its steps engine (`when=`/`over=`/
`until=`, an injected capture closure, `.result.<name>`). The most reusable *disciplines* are
api-mirror's: builders check shape and validate checks meaning; every check exists because its
absence is a silent runtime failure and the message says which; a declaration that would do nothing
is a load error; fail closed; a closed vocabulary of reasons with no "other"; fingerprints derived
rather than declared; instrument the transport, not the call sites; hit and miss share one path.

Two findings change the shape of a plan. **First, cost**: nothing caches a parsed template anywhere,
and a single render measures ~62-87 µs and ~44 KB, of which ~97% is `.Funcs()` reflecting over
sprig's ~200 entries on every call. Neither existing consumer cares; a per-compile wrapper is the
first that would. Skipping the renderer for a template with no `{{`, caching parses by source (23x),
and shrinking the func map (5x) are all consumer-local fixes. **Second, bytes**: the language is
string-in, string-out end to end, and both consumers keep byte work in Go — the config names which
file, which algorithm and which expectation. api-cli already has a streaming, hash-as-it-goes,
`.part`-and-rename capture of a program's stdout, but it is wired only to downloads and it *verifies*
a declared digest rather than *producing* one.

Nothing in api-dsl must change for api-cache to exist. Three additive changes would help and none is
a prerequisite: a prepared-template cache, a `PureFuncMap` without sprig's environment/DNS/random
functions, and source positions on `Node`.
