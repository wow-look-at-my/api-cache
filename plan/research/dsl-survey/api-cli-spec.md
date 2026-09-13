# api-cli-spec — how the grammar is kept, and what a new one costs

Module `github.com/wow-look-at-my/api-cli-spec`, package `spec`, Go 1.26, MIT
(`/home/user/api-cli-spec/LICENSE:1`). It is tiny: `api-cli.xsd` (792 lines, ~154 type/element
declarations), `resolved.xsd` (88 lines), `resolve.go` (176), `resolved.go` (69), `schema.go` (15),
`spec_test.go` (111), plus 12 document pairs in `testdata/`.

Dependencies: only `testify` and `wow-look-at-my/xml-validator/validator`
(`/home/user/api-cli-spec/go.mod:5-9`). The go.mod carries a `replace` with a comment explaining a
broken transitive revision (`:17-20`) — worth knowing before adding this module as a dependency.

## 1. The claim the module makes

`/home/user/api-cli-spec/README.md:3`:

> This repository is the authoritative source of truth for the language. An implementation conforms
> to it, and it never derives from an implementation.

Four artifacts, stated at `README.md:5`:
- `api-cli.xsd` — what a document may contain.
- `resolved.xsd` — what a reader must work out from one.
- `resolve.go` — works it out (the **reference reader**).
- `spec_test.go` — holds both to the documents under `testdata/`.

## 2. How a consumer uses it

`schema.go:1-15` embeds both XSDs as exported strings:

```go
//go:embed api-cli.xsd
var Schema string
//go:embed resolved.xsd
var ResolvedSchema string
```

api-cli keeps **no copy of the file**. Two consumption points:

1. **Docs.** `docs.go:14-16` — `var schemaDoc = spec.Schema`, printed by `api-cli docs schema`
   (`docs.go:32-41`). The comment says why: *"so this binary prints the one text rather than a copy
   of it."*
2. **Tests.** `schema_test.go:17-31`, `TestShippedConfigsValidateAgainstTheGrammar`: glob
   `*.example.xml`, append the two sample configs, and run each through
   `validator.ValidateWithSchema(file, strings.NewReader(spec.Schema))`.

**The XSD is never consulted at load time.** `Load` (`api-cli/config.go:420-435`) does
parse → build → validate, with no schema step anywhere. README:809 states the division:

> The loader stays authoritative at run time. It enforces the rules a schema cannot state. One
> example is the rule that a leaf needs a run, its own or an ancestor's.

So the XSD is an **editor aid and a CI gate**, not a runtime dependency. A config author points
`schema=` at the raw URL (`api-cli/README.md:780`, `:789` — "The loader ignores it"), and CI runs
`xml-validator --schema`.

## 3. "Resolved form" — the executable half of the spec

This is the module's real invention and the part most worth copying.

A document states each setting where the author wrote it. A command's **effective** settings come
from walking its ancestors, so the answer appears nowhere in the source. The resolved form writes
that answer down, and **names the node each winning value came from** (`README.md:44`):

> A resolved file names the node each winning value came from. That is what a reader has to get
> right. It is also the one thing the source document never writes down.

`testdata/minimal.xml` →

```xml
<resolved config="minimal">
	<command path="/hello" runs="true">
		<run from="/hello" kind="shell"/>
	</command>
</resolved>
```

`testdata/tree.resolved.xml` shows the inheritance being asserted: `/repo/sync` carries
`<run from="/repo" kind="shell"/>` and `<cwd from="/">/tmp</cwd>` — the declaring node is recorded,
not just the value.

### The model (`resolve.go:16-53`)

```go
type Setting struct{ From, Value string }
type Run struct{ From, Kind string }               // Kind: "shell" | "argv" | "request"
type Command struct{ Path string; Runs bool; Run *Run; Cwd, Stdin, Confirm, Format *Setting }
type Resolved struct{ Config string; Commands []Command }
```

Only the **inheritable** things appear. `Stdin`, `Confirm` and `Format` are markers carrying only
`from=` (no value) — `resolved.xsd:52-54` calls that type `marker`. `Cwd` carries its text.

### The algorithm (`resolve.go:58-132`), 75 lines total

- `Resolve` requires the root be `<config>` with a `name=` (`:60-66`) — **the root check, again in
  the consumer**.
- The root's own declarations resolve first at the path `"/"`, because *"The document root is an
  ancestor of every top-level command"* (`:69-71`, `README.md:38`).
- `walk` builds `path = parentPath + "/" + name`, computes `Runs = len(subcommands) == 0 ||
  runnable=="true"` (`:95`), records the command, recurses with its own resolved settings (`:104-107`).
- `declarations` (`:115-132`) layers a node's own **direct child** declarations over what it
  inherits. The comment states the subtlety (`:112-114`): *"Only a direct child counts: a `<cwd>`
  inside `<steps>`, or inside a `<transport>`, belongs to that thing rather than to the command
  tree."*
- `runKind` (`:137-147`): a `<request>` child → "request", an `<argv>` child → "argv", else "shell".
- `Resolve` **reads structure only. It never renders a placeholder** (`:56-57`, `README.md:29`).

### The suite (`spec_test.go`)

Three tests:
1. `TestEveryDocumentValidatesAgainstTheSchema` (`:64-71`) — each `testdata/x.xml` against
   `spec.Schema` and each `testdata/x.resolved.xml` against `spec.ResolvedSchema`. Note it validates
   against the **embedded string**, not the file beside it (`:52-53`), so the text a consumer gets is
   the text under test.
2. `TestEveryDocumentHasItsResolvedForm` (`:75-87`) — bidirectional: a document with no partner
   fails, and a partner with no document fails. *"A document with no resolved form states what it may
   say and never what it means, and a resolved form with no document describes nothing."*
3. `TestResolveProducesTheStatedForm` (`:89-101`) — the one with something to say. `Resolve(doc)`
   vs `ParseResolved(partner)`, compared **on the values** via `assert.Equal` on the structs, so
   attribute order and whitespace carry nothing.

Plus a negative test that each parser rejects the other's root (`:103-111`).

### The conformance argument (`README.md:31`)

> A second implementation reads a document, emits the resolved form, and compares against the partner
> file. ... A conformance suite therefore lives here, in the specification, rather than beside one
> reader where it drifts from every other.

### No rejection corpus, deliberately (`README.md:25`)

> A document the schema refuses states nothing the schema does not already state itself. It is the
> same rule written twice in two files. Nothing loosens an `xs:element` by accident either. An XSD is
> declarative and hand-written, so a rule changes only when somebody changes it, deliberately.

## 4. XSD conventions the org has settled on

- **XML 1.1 only.** Every document and every XSD opens with `<?xml version="1.1" encoding="UTF-8"?>`.
  `xml-validator` reads XML 1.1 only (`README.md:13`). Recall api-dsl's `StripXMLDecl` exists purely
  because Go's `encoding/xml` reads 1.0 (`api-dsl/dom.go:125-129`).
- **Child elements are order-free.** *"A document means the same thing whatever order its children
  appear in."* Every structural element uses `xs:all`, never `xs:sequence`, and
  `testdata/unordered.xml` is what keeps it that way (`README.md:58-60`, `api-cli.xsd:12-15`).
- **Booleans are `true` or `false`, and nothing else.** A named `bool` simpleType with two
  enumerations, so `1` and `yes` fail *by name* rather than reading as false
  (`api-cli.xsd:21-32`, `README.md:62-64`).
- **`xs:alternative` carries a mutual exclusion.** `<value name=>` vs `<value expr=>` is two
  complexTypes, `valueByName` and `valueByExpr`, where each prohibits the other's attributes
  (`api-cli.xsd:65-80`). That is how "exactly one of name= or expr=" (which the compiler enforces at
  `api-dsl/compile.go:186-188`) is also stated in the grammar.
- **Named lexical types** for the recurring shapes: `bool`, `nonEmpty`, `path` (a context path,
  `[^\s]+`), `overExpr` (a path *or* a template), `template` (`api-cli.xsd:19-60`). The comments
  distinguish them by meaning, not by syntax — `overExpr` is looser than `path` precisely because a
  `<step over=>` may be a template while a `<fields over=>` may not.

## 5. What an XSD cannot state — the table to reuse verbatim

`/home/user/api-cli-spec/README.md:66-88`. Preamble: *"These rules are part of the language. A
conforming reader must reject a document that breaks one. XSD reaches an element's own attributes and
its content model, and none of the rules below fit in either."*

| Rule | Why a schema cannot carry it |
|---|---|
| `<entry>` holds an object whose keys are the author's own element names | An open wildcard needs `processContents="lax"`, which xml-validator refuses by design. Nothing constrains an `<entry>` subtree, so no schema can describe it. |
| A leaf needs a run, its own or an ancestor's | It reads the ancestor chain. |
| `<download>`, `<fields>`, `<steps>`, `<entry>` and `<preconditions>` need a node that runs | They read whether the node has subcommands. |
| `<fields>` and `<format>`, or `<tml>` and `<fields>`, are exclusive | Two sibling elements, not one element's attributes. |
| `<download>` takes neither `<fields>` nor `<format>` | The same. |
| `group=` and `order=` need a `<join>` | An attribute and a child element of the same node. |
| `<join contiguous=>` needs `order=`, and a joined part needs its own `<to>` | The same. |
| `runnable="true"` needs subcommands, and each of its args needs a `pattern=` | It reads the node's children. |
| An arg `pattern=` compiles, and matches no subcommand name | It reads the sibling commands, and it runs a regular expression engine. |
| `passthrough="true"` is leaf-only, and takes no args | It reads the node's children. |
| A variadic arg comes last, and a required arg never follows an optional one | Order among siblings of one name. |
| `conflicts=` names a flag on the same node | It reads the sibling flags. |
| `transport=` names a declared transport | The name `http` is legal and declares nothing, so an `xs:keyref` rejects a correct document. |
| At most one transport is the default | "At most one true" is not a uniqueness constraint. |
| `allow-status=` needs the default transport | It reads which transport the request resolves to. |
| A precondition cannot read `.result` | It reads the template body. |
| `<format ref=>` names a declared format | The reference crosses from a command to the top-level `<formats>`, past the subtree an identity constraint selects over. |

Every row of that table maps to a `validate*` function in `api-cli/config.go`. The two documents are
kept in step by hand; nothing checks that every entry in the table has a matching loader error.

## 6. What adding a new grammar costs

From api-cli's CLAUDE.md, "Adding a new field to the config", step 5:

> Add it to `api-cli.xsd` in api-cli-spec, **with a document that uses it and the resolved form that
> document produces**. Bump the module here once that lands. Document it in `README.md`. Exercise it
> in `api.example.xml` when an integration test needs it.

So a single new attribute costs, at minimum:

| repo | work |
|---|---|
| api-cli-spec | edit `api-cli.xsd`; possibly add `testdata/<feature>.xml` **and** `<feature>.resolved.xml`; extend `resolve.go` only if the thing inherits; merge; get a module pseudo-version |
| api-cli | struct field (`config.go`), builder + `checkAttrs` (`xmlsource.go`), inheritance in **two** places (`build.go` + `mcp.go`) if it inherits, `validate*` rule, README row, unit test, integration test, `go.mod` bump of api-cli-spec |

That is a two-repo, cross-module round trip with a version bump in the middle. For a **new project**
the honest options are:

- **A) Own XSD in its own spec module, mirroring api-cli-spec.** Highest fidelity, highest ceremony,
  and a second module to keep on a branch.
- **B) An XSD checked into api-cache itself** and validated in a Go test with `xml-validator`. Loses
  the "spec never derives from an implementation" claim but removes the cross-repo round trip; a
  single-consumer language has nobody to conform *to*.
- **C) No XSD at all**, relying on `checkAttrs` + the child-dispatch `default:` cases, which already
  produce good errors, plus a shipped-config load test. Loses editor completion via `schema=` and
  loses the CI XML gate.

The resolved-form idea is separable from the XSD question: a table of
`(node path → effective setting, and the node that declared it)` asserted against a checked-in
partner file is valuable to api-cache for **any** inheritable setting, with or without a schema, and
it is ~75 lines of Go plus two files per test case.

## 7. CI

`.github/workflows/ci.yml` runs one `spec` job: checkout + `wow-look-at-my/go-toolchain@master`
with `autorelease: 'false'` (the spec ships no binary). Every assertion lives in the Go test.
