# 02 — The language

What a rule file says, how it reuses api-dsl unchanged, and the shape of the tool-rule surface, which is the open decision `00-goals.md` names. This file proposes a concrete grammar so the reviewer can judge it against real invocations, and records the alternatives with the same examples.

## What is reused, exactly

Everything in `plan/research/dsl-survey/reuse-map.md` marked AS-IS is used as-is. The boundary is one `dsl.go` file aliasing six functions, the same shape both existing consumers have (`api-cli/dsl.go`, `api-mirror/internal/mirror/dsl.go`):

| Need | Source |
|---|---|
| Parse the XML into an order-preserving DOM | `apidsl.ParseDOM` |
| Reject unread attributes | `apidsl.CheckAttrs` on every element a builder reads |
| Placeholders `<value>`, `<if>`, `<for>`, `<else>` in content | `apidsl.CompileContent`, `CompileTextElem`, `TextOf`, `IsPlaceholder` |
| Render | `apidsl.NewRenderer(cacheFuncs())`, with the prepared-template cache described in `06-hot-path.md` |
| Truthiness, env map, path lookup | `apidsl.Truthy`, `EnvMap`, `LookupPath` |

Nothing in api-dsl changes. Three additive proposals to api-dsl are recorded in `12-decisions.md` (a prepared-template cache, a pure func map, source positions on `Node`) and each has a consumer-local fallback that the plan uses until they land.

The builder-then-validate discipline is api-mirror's (`plan/research/dsl-survey/api-mirror-language.md` §8): builders check shape and call `CheckAttrs` first, `validate` checks meaning, every check exists because its absence is a silent runtime failure, and its message says what would go wrong and names the fix.

## Determinism of a render

A template that feeds a cache key must be pure. sprig's func map includes `env`, `expandenv`, `getHostByName`, `now`, `uuidv4` and the random family (`plan/research/dsl-survey/gaps.md` §6). The renderer shadows every impure name with a function that fails the render with a message naming the function. It also shadows `sha256sum` and friends, which take a string and are the wrong tool for a file, with versions that fail and point at the `hash` role instead.

A key-producing template is validated after rendering. `missingkey=zero` means a mistyped path renders as the literal `<no value>`, which is a stable and silently colliding key (`gaps.md` §2). The loader rejects, at cook time, any rendered identity or key fragment that contains `<no value>`, the way api-cli's `renderHash` rejects a malformed digest.

## The document

One root, `<cache>`. A deployment has several documents: the shipped rules, a user's overlay, a project's overlay. They merge at the struct level after parsing, because the DOM cannot be spliced (`gaps.md` §11). The merge rules are in "Overlays" below.

```xml
<?xml version="1.1" encoding="UTF-8"?>
<cache name="default" format="1">
	<vars>
		<var name="root"><value name="env.API_CACHE_DIR" default="~/.cache/api-cache"/></var>
	</vars>

	<store dir="{{ .var.root }}" max-size="20GiB" restore="auto" compress="auto"/>

	<remote name="team" url="https://cache.example.com/" read="true" write="ci-only"
	        token-env="API_CACHE_TOKEN" batch="auto" probe="auto"/>

	<tool name="gcc" syntax="gnu" ...>  ... </tool>
	<tool name="cl"  syntax="msvc" ...> ... </tool>
	<tool name="rustc" syntax="rustc" ...> ... </tool>
</cache>
```

`<vars>` is api-cli's, resolved in declaration order with one fixpoint pass (api-mirror's simpler variant suffices: there are no flags to feed back). Every attribute that names a path or a size is a template.

`<store>` and `<remote>` are engine settings with a closed attribute set; `04-local-store.md` and `05-remote-tier.md` list them. Their precedence against environment variables and the command line is in `08-cli-and-ops.md`.

## The tool rule

The proposal is the hybrid from `00-goals.md`: a table of meanings for classification, the engine's named behaviours switched on by attributes, and api-cli's steps and templates only where a rule computes something. The whole gcc rule is shown in `09-tool-rules.md`; this section shows the grammar element by element, with the completeness list from `plan/research/compile-semantics/key-derivation-model.md` §6 as the checklist.

### `<tool>` — item 1, 2, 13

```xml
<tool name="gcc" match="^(gcc|g\+\+|cc|c\+\+|clang|clang\+\+)(-[0-9.]+)?$" real-match="clang$" 
      syntax="gnu" response-files="gnu" unknown="hash" version="4">
```

- `match=` is a regex over the invoked basename (buildcache's first-line directive, `plan/research/prior-art/buildcache.md`). `real-match=` is an optional second regex over the resolved real tool's basename, so `clang-cl` (a symlink to `clang`) routes to the MSVC-syntax rule by its invoked name while `gcc` invoked through a `cc` symlink still routes here. Two rules matching one invocation is a load error naming both.
- `syntax=` names an engine parser: `gnu`, `msvc`, `rustc`. `response-files=` names an expansion dialect: `gnu` (recursive, shell quoting, unopenable left verbatim), `msvc` (fixpoint with a depth cap, UTF-16LE and UTF-8 BOMs, unopenable is an error), `none`.
- `unknown=` is the policy for an argument no row matches: `bypass` (the correctness default) or `hash` (the ccache default, and the right one for gcc where unknown flags are common and mostly inert). A rule for rustc says `bypass`, following buildcache's rationale that an unknown option may take a separate value that would be misread as the source (`plan/research/compile-semantics/rustc.md` §2).
- `version=` is the rule's own format version, salted into every key with the engine version. Bumping it invalidates the rule's entries without touching anyone else's.

### `<identity>` — item 7

```xml
<identity policy="command" memo="5m">
	<argv><value name="tool.path"/></argv><argv>--version</argv>
</identity>
```

`policy=` is one of `mtime` (size and mtime, no read), `content` (the binary's bytes), `command` (run the child argv and hash its stdout), `string` (a literal, for a pinned CI toolchain image). The engine memoises by `path:size:mtime` for `memo=`. `<extra-file>` children add files whose content joins the identity (rustc's sysroot shared libraries, a toolchain manifest). The invoked name and the rule's `env` allowlist are always part of the identity; the full path never is, so `/usr/bin/gcc` and `/opt/gcc/bin/gcc` with identical content share entries.

### `<env>` — item 8

```xml
<env>
	<hash>COMPILER_PATH GCC_EXEC_PREFIX LANG LC_ALL LC_CTYPE LC_MESSAGES GCC_COLORS</hash>
	<hash mode="direct">CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH</hash>
	<bypass reason="unsupported_environment_variable">DEPENDENCIES_OUTPUT SUNPRO_DEPENDENCIES</bypass>
	<unset>VS_UNICODE_OUTPUT</unset>
</env>
```

An allowlist, never a denylist (`plan/research/compile-semantics/go-and-others.md` §6). `<hash>` names variables whose values enter the key, with `unset` distinguished from empty. `mode=` restricts a group to the direct key. `<bypass>` declines when the variable is present. `<unset>` removes the variable from the child's environment; the engine deletes it rather than blanking it, because cl tests presence (`plan/research/msvc-probes/corrections.md` §11). A rule may also read a variable name out of argv: `/external:env:<var>` is expressed in the args table with role `env-read`, which adds that variable to the direct-mode allowlist at run time.

### `<args>` — items 3, 4, 5, 6

The table. One `<arg>` per flag family. The `value=` vocabulary is the engine's per-syntax set (`c-cxx-gcc-clang.md` §10.1, `msvc.md` §14.1, `rustc.md` §7.1) and the `role=` vocabulary is the engine's (`c-cxx-gcc-clang.md` §10.2).

```xml
<args default-output="{{ .source.base }}.o" output-ext="s={{'.s'}}">
	<arg match="-c"  value="none"   role="mode:compiling"/>
	<arg match="-S"  value="none"   role="mode:compiling mode:asm"/>
	<arg match="-E"  value="none"   role="bypass:called_for_preprocessing"/>
	<arg match="-o"  value="either" role="primary-output"/>
	<arg match="-MD -MMD" value="none" role="mode:generating-deps comp-only"/>
	<arg match="-MF" value="either" role="dep-output"/>
	<arg match="-MT" value="sep"    role="dep-target"/>
	<arg match="-MQ" value="sep"    role="dep-target:quoted"/>
	<arg match="-I -iquote -isystem -idirafter" value="either" role="dir-read cpp-only"/>
	<arg match="-D -U" value="either" role="cpp-only"/>
	<arg match="-include -imacros -include-pch" value="either" role="path-read cpp-only"/>
	<arg match="-Wp," value="comma-list" role="forward"/>
	<arg match="-Xclang" value="sep" role="forward"/>
	<arg match="-gsplit-dwarf" value="none" role="derived-output:.dwo hash-output-path"/>
	<arg match="--coverage -ftest-coverage -fprofile-arcs" value="none" role="mode:coverage derived-output:.gcno"/>
	<arg match="-fprofile-use= -fprofile-instr-use=" value="prefix-rest" role="path-read hash-normalized-path"/>
	<arg match="-march=native -mcpu=native -mtune=native" value="none" role="hash-expanded:native"/>
	<arg match="-fdebug-prefix-map= -ffile-prefix-map= -fmacro-prefix-map=" value="eq" role="prefix-map"/>
	<arg match="-fdiagnostics-color -fcolor-diagnostics" value="eq" role="diagnostics-color"/>
	<arg match="-save-temps" value="prefix-rest" role="bypass:unsupported_compiler_option"/>
	<arg match="-fplugin=" value="eq" role="path-read"/>
	<arg match="*.c *.cc *.cpp *.cxx *.C *.m *.mm *.s *.S *.i *.ii" value="positional" role="source-input"/>
</args>
```

Rules of the table:

- `match=` is a space-separated list of literal flags, or a glob for positionals. A literal matches the flag as the syntax parser reports it, so `-DFOO` and `-D FOO` both match `-D`. A regex is available as `pattern=` and is compiled once at load, failing there.
- Order does not matter for lookup: a flag maps to exactly one row, and two rows claiming one flag is a load error naming both, the way api-cli rejects an ambiguous `<arg pattern=>` (`plan/research/dsl-survey/gaps.md` §3).
- `role=` is a space-separated set. Every role is one of the engine's closed set; an unknown role is a load error listing the set. `bypass:` carries a reason from the closed vocabulary, checked at load. `mode:` sets a flag the verdict predicate reads. `gate:<sloppiness>` marks a row whose effect a named relaxation turns off.
- A row may carry `when=` for the rare conditional meaning (`-Wp,-MD` together with `-MF` declines; `-fpch-preprocess` is added only under `pch-use`). `when=` is a template predicate over the classified state, evaluated after the whole argv is classified.
- The positional row decides the language by extension; `-x` overrides through `role="mode:language"`.
- `default-output=` and `output-ext=` are templates over `.source` and the mode set, for the primary output when `-o` is absent and for the `-S` extension change.

### `<verdict>` — item 4

The engine's fixed predicate covers the universal cases (no source, several sources, output to stdout, a bypass role matched). A rule adds tool-specific conditions:

```xml
<verdict>
	<decline reason="called_for_link" when="{{ not .mode.compiling }}"/>
	<decline reason="autoconf_test" when="{{ and (not .mode.compiling) (contains \"conftest.\" .source.path) }}"/>
	<decline reason="unsupported_dep_output_combination" when="{{ and .flag.Wp-MD .flag.MF }}"/>
</verdict>
```

`reason=` is checked against the closed vocabulary at load. Every decline names the argument that triggered it in the report, because the engine records which row set each mode flag.

### `<discover>` — items 9, 10

```xml
<discover direct="true" report="linemarkers -H">
	<preprocess>
		<argv><value name="tool.path"/></argv>
		<argv><value expr="{{ spread (drop .argv (roles \"primary-output\" \"dep-output\" \"comp-only\" \"mode:generating-deps\")) }}"/></argv>
		<argv>-E</argv>
		<argv><if test="mode.debug-info"><else/>-P</if></argv>
		<argv>-H</argv>
	</preprocess>
	<depend report="depfile"/>
</discover>
```

- `direct="true"` declares direct mode. The direct key adds the `cpp-only` rows, the `mode="direct"` env group, and the source path and content.
- `<preprocess>` is an api-cli command: `<argv>` templates with `spread`, `drop` and `roles` helpers the engine adds. The engine runs it with stdout and stderr captured separately, hashes stdout as the preprocessed text, appends stderr's diagnostics to the key, and reads the include set from `report=` (`linemarkers` from stdout, `-H` from stderr, `showincludes`, `sourcedependencies`, `depfile`). A non-zero exit is `preprocessor_error`.
- `<depend>` declares depend mode: skip the preprocess, run the tool, derive the key from the named report.
- MSVC's rule sets `report="showincludes"` and adds `/showIncludes` to the child argv. The engine parses the English prefix `Note: including file: ` (22 bytes, one extra space per nesting level, measured in `plan/research/msvc-probes/results/p02-showincludes.md`). Localization is out of scope: a compile whose include report carries no recognised prefix declines with `unrecognized_include_report`, loudly, rather than carrying a runtime detection mechanism for a case nobody here has.

### `<outputs>` — items 5, 6, 12

Most output knowledge is in the args table (`primary-output`, `dep-output`, `derived-output:<ext>`). `<outputs>` holds what the table cannot: outputs derived by asking the tool, and the link policy.

```xml
<outputs hard-link="safe" require-primary="{{ not .mode.syntax-only }}">
	<query><argv><value name="tool.path"/></argv><argv>--print</argv><argv>file-names</argv> ...</query>
	<derive from="query" add-when="emit contains metadata" ext=".rmeta"/>
</outputs>
```

`hard-link="safe"` is the one boolean only the rule can know (`key-derivation-model.md` §5). `require-primary=` prevents `compiler_produced_no_output` under `-fsyntax-only` and `/Zs`.

### `<sloppiness>` — item 11

```xml
<sloppiness>
	<allow name="time_macros"/>
	<allow name="file_stat_matches"/>
	<allow name="locale"/>
	<allow name="pch_defines"/>
</sloppiness>
```

The engine's registry is ccache's fourteen (`plan/research/compile-semantics/hashing-and-normalization.md` §3), each named, individually loggable and off by default. A rule lists which apply to this tool; a user turns them on in `<store>` or from the command line. A rule cannot invent a relaxation.

### `<steps>` — the escape hatch

For the irregular cases (`key-derivation-model.md` §5: `/FI` resolving against the source directory, `/Yu`'s three-step `.pch` resolution, rustc's `-l static=` search along `-L`), a rule uses api-cli's steps, unchanged in semantics: `<step name= when= over= until=>` with a command whose stdout becomes `.result.<name>`, plus a binary-safe variant `capture="hash"` that hashes stdout instead of parsing it as JSON (`plan/research/dsl-survey/gaps.md` addendum D: api-cli has the streaming hashed capture on its download path already). A step's cost is visible in `explain` and in the per-invocation log, so a shipped rule that leans on steps is a signal that a primitive is missing.

## Two alternatives, same examples

**A pure api-cli shape.** The gcc rule becomes a passthrough leaf with declared `<flag>`s, `.rest`, `<vars>` and `<steps>`, and the key is a template over them. It exists today and is maximally flexible. Against it: `passthroughParse` knows arity by type only, has no attached-value short form, no roles, no pattern on a flag, and fails silently on an unrecognised flag (`gaps.md` addendum A). Writing the 60-row gcc table as templates makes the rule a program again, which is the buildcache problem in a different syntax. Rejected as the primary shape; kept as the escape hatch.

**A pure table.** Every flag is a row, and the preprocess step is a fixed engine behaviour with attributes. Against it: the three irregular cases above, nvcc's `--dryrun` decomposition, and any future tool with a computed output set need code somewhere, and the choice is between Go (a release per tool) and a template. Rejected as the sole shape; it is the primary shape with steps behind it.

The hybrid's readability claim is tested in `09-tool-rules.md`, which writes gcc, cl and rustc in full. If those three files do not read as a table of meanings with a short computed tail, the shape is wrong and `12-decisions.md` decision 2 reopens.

## Overlays

Shipped rules are files under the binary's rule directory. A user overlay is any `<cache>` document later in the search order (`08-cli-and-ops.md`). Merge happens on the parsed structs:

- A `<tool name=>` that exists in an earlier document is extended: `<arg>` rows are added, a row with the same `match=` replaces the earlier row, and `<env>`, `<sloppiness>` and `<verdict>` lists are unioned. `<identity>`, `<discover>` and `<outputs>` replace whole.
- A `<tool>` with a new name is added.
- `<store>` and `<remote>` attributes override one by one.
- `<tool name="gcc" remove="true"/>` drops a shipped rule.

`explain` shows which document each row came from. The cooked form records the hash of every merged source so a change to any of them invalidates it (`07-cook.md`).

## Validation, the load errors the reviewer should expect

Following api-mirror's standard, every message says what would go wrong and names the fix:

- Two rules match one program name: "invocation `cc` matches rules `gcc` and `tcc`; narrow `match=` with anchors".
- Two rows claim one flag.
- A role, reason, syntax, value form, sloppiness name or policy outside the closed set: the message lists the set.
- A `bypass:` without a reason, or a `<decline>` without `when=`.
- A `<discover direct="true">` on a rule whose args table has no `source-input` row: "direct mode needs a source to hash".
- A rule with `unknown="hash"` and no `primary-output` row: an unknown flag could then be the output.
- A `<preprocess>` that is a request rather than a command (api-cli's transport rule, same message).
- A template that renders `<no value>` for any identity or key fragment at cook time.
- A `<store dir=>` that renders to a relative path.
- A remote with `write="always"` and no credential: "an open write path is how a cache gets poisoned".
- A declaration that would do nothing (`<hash>` with an empty list, a `<sloppiness>` naming an unknown knob, a `<derive>` with no source) is an error, not a no-op.

## Grammar tier

Following `plan/research/dsl-survey/gaps.md` §14: the light tier. One `cache.schema.xsd` at the repository root for editor completion, a name-coverage test that every element and attribute a shipped rule uses is declared in it, and `CheckAttrs` plus the child-switch default for the real enforcement. The resolved-form idea (a checked-in table of effective settings per tool after overlays) is adopted on its own as the `explain --rules` golden test in `10-testing-and-ci.md`.
