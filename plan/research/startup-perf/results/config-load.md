# What a declarative XML config costs per exec

**Source: GitHub Actions hosted runner `ubuntu-latest`, run
[34728324912](https://github.com/wow-look-at-my/api-cache/actions/runs/34728324912),
commit `9f95956`.** In-process timing, median of 400 iterations per stage. See
[method.md](method.md). Raw output: [`gha/config-load-linux-x64/`](gha/config-load-linux-x64/).

## What is being loaded

`probes/fixtures/github.xml`, copied from api-cli's GitHub sample: 30,749 bytes,
663 lines, 528 DOM nodes, and 76 elements whose content holds a placeholder and
therefore compiles to a Go template. It is parsed by
[api-dsl](https://github.com/wow-look-at-my/api-dsl)'s `ParseDOM` (which sits on
`encoding/xml`), compiled by `CompileContent`, and executed through
`text/template` with api-dsl's function map, which is
[sprig](https://github.com/Masterminds/sprig) plus four helpers — 214 entries.

Serialized sizes of the same content: XML 30,749 B; `encoding/gob` of the DOM
28,737 B; the hand-rolled flat format 31,202 B; **the compiled template sources
alone 2,862 B.**

## The table

| stage | min µs | p50 µs | p90 µs | mean µs | note |
|---|---|---|---|---|---|
| read file | 9.8 | 10.8 | 19.1 | 15.8 | `os.ReadFile`, warm page cache |
| parse (`ParseDOM`) | 812.2 | 897.5 | 1243.1 | 957.1 | `encoding/xml` into the DOM, file already in memory |
| parse + compile | 972.3 | 993.2 | 1364.1 | 1069.5 | then `CompileContent` over every element |
| `apidsl.FuncMap()` | 7.0 | 7.6 | 11.0 | 9.2 | sprig's map plus the language's helpers |
| `template.Parse` x20 | 777.9 | 808.8 | 1225.7 | 917.1 | 20 compiled sources, func map attached to each |
| `template.Execute` x20 | 15.3 | 15.8 | 19.8 | 18.2 | executing the 20 already-parsed templates |
| **FULL: read+parse+compile+tparse** | **1687.9** | **2268.6** | **3251.1** | **2438.6** | everything a naive per-exec load does |
| gob decode (DOM) | 332.5 | 344.4 | 389.0 | 371.7 | `encoding/gob` of the whole DOM |
| flat decode (DOM) | 20.5 | 21.6 | 24.8 | 26.8 | string table + node array, hand-rolled |
| cooked decode (templates only) | 1.6 | 1.7 | 2.1 | 2.5 | length-prefixed compiled sources, no DOM |
| cooked decode + tparse x20 | 731.2 | 822.9 | 1207.4 | 925.8 | the cooked form still pays `template.Parse` |
| `template.Parse` x1 (largest, 436 B) | 40.7 | 42.9 | 55.2 | 50.1 | |
| `template.Parse` x1 (smallest, 13 B) | 36.0 | 38.4 | 58.6 | 45.9 | |
| `template.Parse` xALL (76) | 3038.6 | 3416.6 | 4191.8 | 3584.5 | every placeholder-bearing element |
| `template.Parse` x20, **no func map** | 48.6 | 50.2 | 65.1 | 58.9 | isolates the map copy |
| LAZY: cooked decode + 1 parse + 1 exec | 45.1 | 47.9 | 65.0 | 56.2 | parse only the template reached |
| shared-root Parse x20 (full func map) | 91.0 | 94.7 | 118.3 | 109.1 | one root carries the map, 20 associated |
| shared-root Parse xALL (full func map) | 251.9 | 276.1 | 388.7 | 312.8 | one root, 76 associated |
| Parse x20, 5-entry func map | 74.3 | 75.9 | 87.5 | 84.7 | per-template `Funcs()`, sprig dropped |
| **BEST: cooked decode + shared-root Parse xALL** | **270.3** | **279.1** | **463.6** | **321.8** | the whole per-exec config cost |

## Findings

### 1. The config load is bigger than the process startup

The naive load is **2,269 µs at the median**. The Go startup floor on the same
class of runner is about 1,041 µs. Loading the config therefore costs **more
than twice as much as starting the process it runs in**. Any conversation about
Go's startup tax that ignores this is arguing about the smaller number.

### 2. `template.Parse` is the stage a cooked form does NOT remove

Cooking removes the XML parse: `cooked decode` is **1.7 µs** against
`parse + compile` at 993 µs. But `cooked decode + tparse x20` is **823 µs**,
barely different from `template.Parse x20` at 809 µs. **The cooked form buys
back about 1 ms and leaves about 0.8 ms on the table**, because the compiled
form is still Go template SOURCE and `text/template` must still parse it.

### 3. Almost all of that 0.8 ms is copying the function map, not parsing

This is the single most actionable number here:

| | 20 templates |
|---|---|
| `template.Parse` with `Funcs(fm)` per template | **809 µs** |
| `template.Parse` with no func map at all | **50 µs** |
| one shared root carrying the map, 20 associated templates | **95 µs** |

`Funcs()` copies the map into the template, and api-dsl's map has 214 entries
because it is sprig's. Doing that per template costs about 38 µs each and it is
**16x the cost of the lexing and parsing it is attached to**.

Two independent fixes, both measured:

- **Share one root.** `template.New("root").Funcs(fm)` once, then
  `root.New(name).Parse(src)` per template. Associated templates share the
  parent's function map, so the copy happens once per process.
  76 templates: **3,417 µs → 276 µs, a 12x reduction.**
- **Drop sprig.** A 5-entry map instead of 214 takes 20 templates from 809 µs
  to 76 µs. Less effective than the shared root and it costs the vocabulary,
  so it is the weaker of the two.

### 4. Stacked up, the cooked form plus a shared root is an 8x win

**2,269 µs naive → 279 µs.** Against a ~1,041 µs Go startup floor, the config
load goes from "twice the cost of the process" to "a quarter of it".

### 5. Lazy parsing beats it again, when the wrapper knows what it needs

`cooked decode + 1 parse + 1 exec` is **48 µs**. A wrapper that resolves which
rule applies before parsing any template, rather than parsing all 76 up front,
pays 48 µs instead of 279 µs. Whether that is reachable depends on whether the
rule can be selected without evaluating templates, which is a language-design
question rather than a performance one.

### 6. `encoding/gob` is a bad choice for a cooked form

gob decode of the DOM is **344 µs**; the hand-rolled flat format is **22 µs**,
**16x faster**, for a file 8% larger. gob carries type descriptions and builds
decoder machinery through reflection at run time, and a per-exec path is
exactly where that does not pay. A sidecar cache that reaches for gob because
it is in the standard library gives back most of what it was built to save.

### 7. `Execute` is free, and `os.ReadFile` is nearly free

Executing 20 parsed templates is 16 µs, and reading the 30 KB file from a warm
page cache is 11 µs. Neither is worth optimizing. The cost is entirely in
getting from bytes to a parsed template.

## Caveats

- One config, from one project. A larger config scales the parse and the
  template count; the func-map finding is per template and does not care.
- `--warmup` semantics do not apply here (this is not hyperfine), but the
  probe warms up five iterations before timing, so no row includes first-call
  allocation.
- The file is always in the page cache. A cold first read is not measured.
- The 20-template subset is the first 20 of the 76 in document order, chosen so
  one pathological template cannot dominate. The xALL rows cover the full set.
