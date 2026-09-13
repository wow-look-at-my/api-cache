# api-dsl — the shared lexical layer (exact public API)

Module `github.com/wow-look-at-my/api-dsl`, package `apidsl`. MIT (`/home/user/api-dsl/LICENSE:1`).
Go 1.25.0. Only two non-test dependencies: `github.com/Masterminds/sprig/v3 v3.2.3` and
`github.com/stretchr/testify v1.11.1` (`/home/user/api-dsl/go.mod:1-8`).

Total source: 690 non-test lines across four files (`doc.go` 15, `dom.go` 159, `compile.go` 266,
`render.go` 252). It is small enough to read in full in one sitting, and a planner should.

Self-description (`/home/user/api-dsl/doc.go:1-15`):

> It holds three things and no vocabulary of its own:
>   - an order-preserving XML DOM (ParseDOM, Node) ...
>   - a compiler that turns the placeholder elements <value>, <if> and <for> into Go text/template source (CompileContent);
>   - the renderer that executes that source (RenderString, Renderer).

---

## 1. Complete exported surface

### dom.go (`/home/user/api-dsl/dom.go`)

```go
type Node struct{ /* unexported: name, attrs, attrMap, content */ }   // :13
type Attr struct{ Name, Value string }                                // :21
type Item struct{ Text string; Elem *Node }                           // :28

func (i Item) IsText() bool                    // :34   Elem == nil
func (n *Node) Name() string                   // :37   local name, namespace prefix dropped
func (n *Node) Attr(name string) string        // :40   "" when absent
func (n *Node) HasAttr(name string) bool       // :44   absent vs set-to-empty
func (n *Node) Attrs() []Attr                  // :47   document order
func (n *Node) Content() []Item                // :50   mixed content, document order
func (n *Node) Children() []*Node              // :53   elements only, text dropped

func ParseDOM(src []byte) (*Node, error)       // :71
func StripXMLDecl(src []byte) []byte           // :130
func CheckAttrs(n *Node, allowed ...string) error // :152
```

`Node` has **no exported fields**. An element's name is the method `Name()`, never a field —
api-cli's CLAUDE.md calls this out explicitly as a gotcha for its own `xnode` alias.

### compile.go (`/home/user/api-dsl/compile.go`)

```go
func IsPlaceholder(name string) bool                 // :14   "value","if","for","else"
func CompileContent(n *Node) (string, error)         // :24   mixed content -> template source
func CompileTextElem(n *Node) (string, error)        // :30   CheckAttrs(n) with NO allowed attrs, then CompileContent
func TextOf(n *Node) (string, error)                 // :40   literal text only; rejects any child element; TrimSpace'd
func DotPath(path string) string                     // :61   "var.base" -> ".var.base"
```

Unexported but behaviour-defining: `compileItems` (:84), `cleanText` (:116), `dedentTabs` (:132),
`isTemplateIdent` (:164), `compileValue` (:180), `compileIf` (:205), `compileFor` (:253).

### render.go (`/home/user/api-dsl/render.go`)

```go
func FuncMap() template.FuncMap                       // :21   fresh map every call
type Renderer struct{ /* funcs */ }                   // :36   read-only after construction, concurrency-safe
func NewRenderer(extra ...template.FuncMap) *Renderer // :42   later map wins on collision
func (r *Renderer) Funcs() template.FuncMap           // :53   returns a COPY
func (r *Renderer) Render(tmpl string, data any) (string, error) // :66
func RenderString(tmpl string, data any) (string, error)         // :83   uses package-level defaultRenderer (:79)
func EnvMap() map[string]string                       // :89   os.Environ() as a map
func IsTruthy(s string) bool                          // :101
func Truthy(v any) bool                               // :116
func LookupPath(data any, path string) any            // :132
func MergeVars(parent, child map[string]any) map[string]any // :153
```

Unexported helpers behind the func map: `queryString` (:167), `addQueryValue` (:195), `repeatKey` (:229).

---

## 2. The compiled-form contract (verbatim)

`TestCompileContent_PlaceholderForms`, `/home/user/api-dsl/compile_test.go:20-46`. The comment above
it (`:18-19`) reads: *"These are the compiled forms every consumer depends on. A change here changes
what every shipped document means."*

| name | src | want |
|---|---|---|
| value name | `<t><value name="var.base"/></t>` | `{{ .var.base }}` |
| value default and as | `<t><value name="env.X" default="def" as="urlpath"/></t>` | `{{ urlpath (.env.X \| default "def") }}` |
| value default only | `<t><value name="env.X" default="def"/></t>` | `{{ .env.X \| default "def" }}` |
| value expr | `<t><value expr="{{ upper .env.Z }}"/></t>` | `{{ upper .env.Z }}` |
| if eq with else | `<t><if test="env.Y" eq="1">yes<else/>no</if></t>` | `{{ if eq (printf "%v" .env.Y) "1" }}yes{{ else }}no{{ end }}` |
| if without else | `<t><if test="env.W">on</if></t>` | `{{ if truthy .env.W }}on{{ end }}` |
| for each | `<t><for each="items"><value name="name"/></for></t>` | `{{ range .items }}{{ .name }}{{ end }}` |
| nested for and if | `<t><for each="items"><if test="on">x</if></for></t>` | `{{ range .items }}{{ if truthy .on }}x{{ end }}{{ end }}` |
| literal text around a value | `<t>Bearer <value name="var.token"/></t>` | `Bearer {{ .var.token }}` |
| dashed path uses index | `<t><value name="flag.dry-run"/></t>` | `{{ (index . "flag" "dry-run") }}` |
| empty eq is an equality test | `<t><if test="flag.s" eq="">empty<else/>set</if></t>` | `{{ if eq (printf "%v" .flag.s) "" }}empty{{ else }}set{{ end }}` |
| structural newlines are dropped | `"<t>\n\t<value name=\"a\"/>\n</t>"` | `{{ .a }}` |
| inline whitespace is kept | `<t> <value name="a"/> </t>` | `` ` {{ .a }} ` `` |
| empty element | `<t/>` | `` (empty string) |

### Placeholder attribute grammar (enforced by `CheckAttrs` inside each compiler)

- `<value>`: `name`, `expr`, `default`, `as` (`compile.go:181`). **Exactly one** of `name=`/`expr=`
  required (`:186-188`). `expr=` cannot combine with `default=` or `as=` (`:190-192`). `expr=` is
  emitted **verbatim**, no wrapping braces added — the author writes `{{ ... }}` themselves (`:193`).
  `default=` appends ` | default "..."` with the literal Go-quoted (`:197-199`); `as=` wraps:
  `as + " (" + core + ")"` (`:200-201`).
- `<if>`: `test`, `eq` only (`:206`). `test=` required and non-empty (`:209-212`). At most one
  `<else/>` (`:217-220`), and `<else/>` may carry **no attributes** (`:221`). `eq=` presence is
  tested with `HasAttr`, so `eq=""` is a real equality test against the empty string (`:239`).
- `<for>`: `each` only — no `as=`, no `index=`, no `limit=` (`:254`). `each=` required (`:257-259`).
  It compiles to a bare `{{ range PATH }}`, so `.` rebinds; there is **no loop index variable** and
  no `{{ else }}` empty-branch.

### Error cases pinned by test (`compile_test.go:85-111`)

value with name and expr; value with neither; value expr with default; value expr with as; value
unknown attribute; if without test; if with empty test; if unknown attribute; two else elements;
else with an attribute; for without each; for unknown attribute; unexpected element (any non-
placeholder element inside compiled content); bad element inside if / else / for.

That last family matters for a planner: **`CompileContent` refuses any element it does not know**
(`compile.go:102-103`, `"unexpected element <%s> in text content"`). So a consumer element can never
appear inside content that is compiled — a consumer must decide, per element, whether it is
*structural* (walk children) or *template* (call CompileContent). `IsPlaceholder` (`compile.go:14`)
is the discriminator a consumer uses when it wants to mix its own children with placeholders.

---

## 3. `DotPath` semantics

`compile.go:61-82`. Split on `.`; if **every** segment is a valid Go template identifier
(`isTemplateIdent`, `:164` — letters/`_` anywhere, digits after position 0) emit `"." + path`;
otherwise emit `(index . "seg" "seg" ...)`.

Pinned cases (`compile_test.go:146-162`):

| in | out |
|---|---|
| `var.base_url` | `.var.base_url` |
| `items` | `.items` |
| `a.b2.c` | `.a.b2.c` |
| `" var.x "` (whitespace) | `.var.x` (TrimSpace'd at `:62`) |
| `flag.dry-run` | `(index . "flag" "dry-run")` |
| `a.2b` | `(index . "a" "2b")` |
| `a..b` | `(index . "a" "" "b")` |
| `""` | `(index . "")` |

The index form is the one that works on **both** `map[string]any` and `map[string]string`
(`compile_test.go:164-168`), which is why `env` (a `map[string]string`) is still reachable by a
kebab-case key. The doc comment (`:56-60`) notes the field form is "graceful on a missing key under
missingkey=zero", i.e. the two forms differ in missing-key behaviour — see §6.

`DotPath` is exported specifically so a consumer can compile its **own path-valued attribute** the
same way, "such as a `when=` predicate" (`:52-53`). api-cli does exactly this.

---

## 4. Whitespace / dedent rules

`cleanText` (`compile.go:116-127`):
1. A whitespace-only chunk **containing a newline** → dropped entirely (structural indentation).
2. A whitespace-only chunk with **no** newline → kept verbatim (the space in `Bearer `).
3. A non-blank chunk containing a newline → `dedentTabs`.
4. Otherwise verbatim.

`dedentTabs` (`compile.go:132-161`): trim leading and trailing blank lines; compute the minimum
count of **leading tab bytes** over non-blank lines; strip that many bytes from every line long
enough. A blank line does not lower the common indent (`compile_test.go:80-82`). **Spaces never
count** — `"<t>\n  first\n  second\n</t>"` → `"  first\n  second"` (`compile_test.go:77-78`). This is
the "structural indentation is tabs" invariant, and it is why every shipped XML in the org uses tabs.

A shell body or a multi-line request body therefore keeps its relative indentation but loses the
document's own nesting level. For api-cache this matters for any element whose content is a literal
script or a multi-line list.

---

## 5. `ParseDOM` behaviour and its deliberate non-behaviour

`dom.go:71-123`.

- `xml.NewDecoder` over `StripXMLDecl(src)`, with `dec.Strict = true`.
- Comments, processing instructions and directives are **dropped** (`dom_test.go:71-75`). CDATA
  arrives as ordinary `xml.CharData` (`dom_test.go:44-48`).
- Namespace declarations (`xmlns`, `xmlns:*`) are skipped as attributes (`dom.go:88-91`), so an XSD-
  carrying document still passes `CheckAttrs` (`dom_test.go:65-69`).
- A **duplicate attribute** is a parse error (`dom.go:92-94`).
- A second top-level element is an error whose message is deliberately generic — "multiple top-level
  elements; expected a single root element" (`dom.go:108`) — and a test asserts the message does
  **not** contain "config" (`dom_test.go:93-98`). This is the no-consumer-vocabulary invariant,
  enforced by a test.
- `ParseDOM` **does not check the root element's name**. The doc comment states why (`dom.go:67-70`):
  each consumer names its own root. api-cache will check its own root, in its own loader.

`StripXMLDecl` (`dom.go:130-147`): strips a UTF-8 BOM, then a leading `<?xml ... ?>` after leading
whitespace. It is careful to not eat `<?xml-stylesheet ...?>` (checks the byte after `<?xml` is
whitespace or `?`). Reason (`:125-129`): Go's `encoding/xml` supports **XML 1.0 only** and errors on
`version="1.1"`, while shipped documents declare 1.1 for the org's stricter external validator.
Pinned cases at `dom_test.go:100-120`; note it returns the text **after** the declaration including
a following newline ("bom and declaration" → `"\n<r/>"`).

`CheckAttrs(n, allowed...)` (`dom.go:152-158`): linear `slices.Contains` over the element's
attributes; the first attribute outside the set errors with `<name>: unknown attribute "x"`. The
invariant in CLAUDE.md: *"CheckAttrs on every element a consumer builds. An unread attribute is a
typo that must fail the load."* Cheap, and it is the only mechanism that makes a misspelled
attribute a load error rather than a silent no-op — there is no schema at load time (see §8).

---

## 6. Render: FuncMap, Renderer, missingkey=zero

`FuncMap()` (`render.go:21-28`) is **sprig's `TxtFuncMap()` plus exactly four**:

| name | impl | meaning |
|---|---|---|
| `querystring` | `queryString`, `render.go:167` | map → `?a=1&b=2`, leading `?` included, empty values dropped, slice repeats the key, keys sorted by `url.Values.Encode` |
| `urlpath` | `url.PathEscape` | percent-escape one path segment |
| `repeatkey` | `repeatKey`, `render.go:229` | `repeatkey "tag" list` → `tag=a&tag=b`, **no** leading `?` |
| `truthy` | `Truthy`, `render.go:116` | what `<if test=>` compiles to |

`querystring` accepts `map[string]string` and `map[string]any`; a value may be nil (dropped), string
(dropped when empty), bool, `json.Number`, int/int64/float64, `[]any`, `[]string`. Any other type is
an error (`render.go:221-223`). Pinned table: `render_test.go:224-249`.

`Renderer` (`render.go:36-76`). `NewRenderer(extra ...template.FuncMap)` starts from `FuncMap()` and
applies each extra map in order, **later wins** (`render_test.go:206-214`). The doc comment warns
that replacing `truthy` "changes what every `<if test=>` in that consumer's documents means"
(`:40-41`). A consumer's helpers stay out of the shared set — proven by test at
`render_test.go:195-204`.

`Render` (`render.go:66-76`) is the whole runtime:

```go
t, err := template.New("t").Funcs(r.funcs).Option("missingkey=zero").Parse(tmpl)
...
var buf bytes.Buffer
if err := t.Execute(&buf, data); err != nil { ... }
return buf.String(), nil
```

**A fresh `template.New(...).Parse(...)` on every single call.** Nothing is cached, at any level.
See `template-runtime.md` for the cost consequences — this is the single most important fact for a
build-cache wrapper that runs on every compiler invocation.

Errors wrap the *whole template source* into the message: `parse template %q: %w` and
`execute template %q: %w` (`:69`, `:73`). For a long shell body that makes a noisy error, but it
does name the failing text.

**missingkey=zero semantics are subtle and pinned** (`render_test.go:161-169`):

```go
RenderString("[{{.var.nope}}]", map[string]any{"var": map[string]any{}}) // => "[<no value>]"
RenderString("[{{.env.NOPE}}]", map[string]any{"env": map[string]string{}}) // => "[]"
```

Zero value **of the map's element type**: `any`'s zero is nil, which `text/template` prints as
`<no value>`; `string`'s zero is `""`. api-cli's CLAUDE.md rule 10 restates this. A document that
must stop on a missing value uses sprig's `fail` (`render.go:64-65`, `render_test.go:176-179`).

`Truthy`/`IsTruthy` (`render.go:99-127`): after `TrimSpace`, empty is false; case-insensitive
`"false"`, `"0"`, `"no"` are false; **everything else is true**. `nil` false, `bool` itself, `string`
via `IsTruthy`, anything else `fmt.Sprintf("%v", x)` then `IsTruthy`. Note the consequences: the
string `"off"` is **true**; an empty slice stringifies to `"[]"` which is **true**; the integer `0`
stringifies to `"0"` which is false.

`LookupPath(data, path)` (`render.go:132-149`): walks dotted segments through `map[string]any` and
`map[string]string` **only**. Empty segments are skipped. Any other type mid-walk returns nil. It
**does not index a slice** — api-cli needed that and wrote its own `lookupData` (see
`api-cli-language.md`).

`MergeVars(parent, child)` (`render.go:153-162`): shallow merge, child wins, always a fresh map, nil
inputs are empty.

`EnvMap()` (`render.go:89-97`): the process env as `map[string]string`. Note the type — this is
exactly why `env` keys with dashes need `DotPath`'s index form.

---

## 7. Compile → render, the one-line pipeline

From the README (`/home/user/api-dsl/README.md:33-37`):

```go
root, err := apidsl.ParseDOM(src)                 // order-preserving DOM
tmpl, err := apidsl.CompileContent(root)          // "Bearer {{ .env.GITHUB_TOKEN }}"
out, err := apidsl.RenderString(tmpl, data)       // "Bearer ghp_..."
```

Compile happens at **load time** in both consumers; render happens at **run time**, per invocation.
The intermediate — template **source text**, a plain string — is the only artifact between them, and
it is what a consumer stores in its config structs. This is the natural serialization boundary for a
"cooked" config form (see `template-runtime.md` §6).

---

## 8. What api-dsl does NOT provide

A planner must budget for every one of these in api-cache's own code:

- **No schema validation.** No XSD, no DTD, no structural grammar at all. The only structural checks
  are: well-formedness (from `encoding/xml`), duplicate attributes, a single root, and whatever
  `CheckAttrs` the consumer remembers to call. api-cli pushes grammar validation into a *separate
  module* (`api-cli-spec`) used *only in tests* — see `api-cli-spec.md`.
- **No root element check** (`dom.go:67-70`, stated as an invariant).
- **No includes, imports, or file references.** `ParseDOM` takes `[]byte`. There is no `<include>`,
  no entity expansion beyond what `encoding/xml` does natively, no multi-file spec. Each consumer
  reads one file.
- **No document-level or element-level validation** of any kind beyond attributes.
- **No line/column information.** `Node` carries no source position, so a consumer's error message
  can name the element and attribute but never the line number. Errors compose by wrapping strings.
- **No mutation API.** `Node` is read-only from outside the package (all fields unexported, no
  setters). A consumer cannot build a `Node` programmatically — only `ParseDOM` produces one. That
  blocks any "generate XML from Go" or round-trip use.
- **No serialization back to XML.** No `String()`, no marshaller.
- **No template caching, no precompiled form, no parse-tree reuse** (`render.go:67`).
- **No `<for>` index or key variable, no `else` branch on an empty range, no `<let>`/`<with>`, no
  nested-scope binding.** The placeholder vocabulary is exactly four element names, frozen by
  `IsPlaceholder` (`compile.go:14-20`).
- **No binary/byte handling.** Everything is `string`. `CompileContent` returns a string; `Render`
  returns a string. There is no `[]byte` path and no notion of non-UTF-8 data.
- **No hashing, no file-system access, no subprocess execution, no HTTP.** `EnvMap` is the only
  thing in the module that touches the outside world.
- **No error type.** Every error is `fmt.Errorf`; nothing is `errors.Is`-able and there are no
  sentinel errors or codes.
- **No concurrency primitives** beyond `Renderer` being immutable after construction.

## 9. The invariants, as the module states them

From `/home/user/api-dsl/CLAUDE.md` "Invariants" — these are the rules a change to api-dsl would
break, and therefore the rules that make a fork tempting and a change expensive:

1. No consumer vocabulary lives here. `value`/`if`/`for`/`else` is the whole owned vocabulary.
2. `ParseDOM` does not check the root element's name.
3. Compiled forms are a contract (the table in §2).
4. `truthy` is not optional.
5. A consumer adds template functions through `NewRenderer`, never through `FuncMap`.
6. Templates render with `missingkey=zero`.
7. Structural indentation is tabs.
8. `CheckAttrs` on every element a consumer builds.

Coverage minimum in this module is 80%, run through `go-toolchain` (never bare `go`).
