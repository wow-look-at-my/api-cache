# 09 — The shipped tool rules

The rule files the first release ships, written in the grammar of `02-language.md`. These are the readability test the language has to pass: if a rule does not read as a table of meanings with a short computed tail, the surface is wrong. The per-flag content is `plan/research/compile-semantics/c-cxx-gcc-clang.md` §10, `msvc.md` §14 as corrected by `plan/research/msvc-probes/corrections.md`, and `rustc.md` §7.

## gcc and clang (`rules/gcc.xml`)

```xml
<?xml version="1.1" encoding="UTF-8"?>
<cache format="1">
<tool name="gcc" match="^(gcc|g\+\+|cc|c\+\+|clang|clang\+\+|.*-gcc|.*-g\+\+)(-[0-9.]+)?$"
      syntax="gnu" response-files="gnu" unknown="hash" version="1">

	<identity policy="command" memo="5m">
		<argv><value name="tool.path"/></argv><argv>--version</argv>
	</identity>

	<env>
		<hash>COMPILER_PATH GCC_EXEC_PREFIX GCC_COMPARE_DEBUG LANG LC_ALL LC_CTYPE LC_MESSAGES GCC_COLORS SOURCE_DATE_EPOCH</hash>
		<hash mode="direct">CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH OBJCPLUS_INCLUDE_PATH CLANG_CONFIG_FILE_SYSTEM_DIR CLANG_CONFIG_FILE_USER_DIR</hash>
		<hash os="darwin">DEVELOPER_DIR MACOSX_DEPLOYMENT_TARGET</hash>
		<bypass reason="unsupported_environment_variable">DEPENDENCIES_OUTPUT SUNPRO_DEPENDENCIES</bypass>
	</env>

	<args default-output="{{ .source.base }}{{ .mode.ext }}">
		<!-- what kind of invocation this is -->
		<arg match="-c --compile" value="none" role="mode:compiling"/>
		<arg match="-S" value="none" role="mode:compiling mode:ext=.s"/>
		<arg match="-fsyntax-only" value="none" role="mode:compiling mode:no-primary-output"/>
		<arg match="-E -EP" value="none" role="bypass:called_for_preprocessing"/>
		<arg match="-M -MM" value="none" role="bypass:called_for_preprocessing"/>
		<arg match="-analyze" value="none" role="bypass:unsupported_compiler_option"/>
		<arg match="-o" value="either" role="primary-output"/>
		<arg match="-x" value="sep" role="mode:language"/>
		<arg pattern="\.(c|cc|cp|cpp|cxx|c\+\+|C|m|mm|M|s|S|i|ii|mi|mii)$" value="positional" role="source-input"/>

		<!-- dependency output -->
		<arg match="-MD -MMD" value="none" role="mode:generating-deps comp-only"/>
		<arg match="-MF" value="either" role="dep-output"/>
		<arg match="-MT" value="sep" role="dep-target"/>
		<arg match="-MQ" value="sep" role="dep-target:quoted"/>
		<arg match="-MP -MG" value="none" role="hash-verbatim"/>
		<arg match="-MJ" value="either" role="bypass:unsupported_compiler_option"/>

		<!-- forwarding -->
		<arg match="-Wp," value="comma-list" role="forward"/>
		<arg match="-Xpreprocessor" value="sep" role="forward cpp-only"/>
		<arg match="-Xclang" value="sep" role="forward"/>
		<arg match="-Xassembler -Xlinker" value="either" role="hash-verbatim comp-only"/>

		<!-- preprocessing inputs: in the direct key, out of the cpp key -->
		<arg match="-I -iquote -isystem -idirafter -iprefix -iwithprefix -iwithprefixbefore -imultilib -iframework -imsvc" value="either" role="dir-read cpp-only"/>
		<arg match="-isysroot --sysroot= --gcc-toolchain= -gcc-toolchain" value="either" role="dir-read"/>
		<arg match="-B" value="either" role="dir-read"/>
		<arg match="-D -U" value="either" role="cpp-only"/>
		<arg match="-include -imacros --include" value="either" role="path-read cpp-only"/>
		<arg match="-include-pch -include-pth" value="either" role="path-read cpp-only mode:pch-use"/>
		<arg match="-nostdinc -nostdinc++ -trigraphs -remap -fworking-directory -fno-working-directory" value="none" role="cpp-only"/>
		<arg match="-stdlib=" value="eq" role="cpp-only"/>
		<arg match="-finput-charset=" value="eq" role="hash-verbatim comp-only"/>

		<!-- debug, coverage, split dwarf, profiles -->
		<arg pattern="^-g(gdb|dwarf|stabs|xcoff|vms|coff)?[0-9]*$" value="none" role="mode:debug-info"/>
		<arg match="-g0 -ggdb0" value="none" role="mode:no-debug-info"/>
		<arg match="-gz" value="prefix-rest" role="hash-verbatim"/>
		<arg match="-gsplit-dwarf" value="none" role="derived-output:.dwo hash-output-path"/>
		<arg match="--coverage -coverage -ftest-coverage -fprofile-arcs" value="none" role="mode:coverage derived-output:.gcno"/>
		<arg match="-fprofile-instr-generate" value="prefix-rest" role="mode:coverage hash-normalized-path"/>
		<arg match="-fstack-usage" value="none" role="derived-output:.su"/>
		<arg match="-fcallgraph-info" value="prefix-rest" role="derived-output:.ci"/>
		<arg match="--serialize-diagnostics" value="sep" role="secondary-output"/>
		<arg match="-fprofile-use -fprofile-instr-use -fprofile-sample-use -fauto-profile" value="prefix-rest" role="path-read hash-normalized-path" when="{{ ne .value \"\" }}"/>
		<arg match="-fprofile-use -fprofile-instr-use -fprofile-sample-use -fauto-profile -fbranch-probabilities" value="none" role="bypass:unsupported_compiler_option" when="{{ eq .value \"\" }}"/>
		<arg match="-fprofile-generate -fprofile-dir=" value="prefix-rest" role="hash-normalized-path"/>
		<arg match="-fprofile-abs-path" value="none" role="hash-verbatim mode:force-cwd" gate="gcno_cwd"/>
		<arg match="-fprofile-prefix-path=" value="eq" role="hash-normalized-path"/>
		<arg match="-fsanitize-ignorelist= -fsanitize-blacklist=" value="eq" role="path-read hash-normalized-path"/>

		<!-- things the compiler reads that ccache forgets to hash -->
		<arg match="-fplugin=libcc1plugin" value="none" role="bypass:unsupported_compiler_option"/>
		<arg match="-fplugin=" value="eq" role="path-read"/>
		<arg match="-specs=" value="eq" role="path-read"/>
		<arg match="-specs" value="sep" role="path-read"/>
		<arg match="--config" value="sep" role="path-read"/>

		<!-- modules and PCH -->
		<arg match="-fmodules" value="none" role="bypass:could_not_use_modules" gate="modules"/>
		<arg match="-fmodule-file=" value="eq" role="path-read"/>
		<arg match="-fmodule-map-file= -fmodules-cache-path=" value="eq" role="hash-normalized-path"/>
		<arg match="-fmodule-header -fmodules-ts" value="none" role="bypass:could_not_use_modules"/>
		<arg match="-fpch-preprocess" value="none" role="mode:pch-use"/>
		<arg match="-fno-pch-timestamp" value="none" role="hash-verbatim mode:pch-no-timestamp"/>
		<arg pattern="\.(gch|pch)$" value="positional-output" role="mode:pch-create" gate="pch_defines"/>

		<!-- machine-dependent expansion -->
		<arg match="-march=native -mcpu=native -mtune=native" value="none" role="hash-expanded:native"/>

		<!-- path normalization -->
		<arg match="-fdebug-prefix-map= -ffile-prefix-map= -fmacro-prefix-map= -fcoverage-prefix-map=" value="eq" role="prefix-map"/>
		<arg match="-fdebug-compilation-dir= -fcoverage-compilation-dir=" value="eq" role="set-compilation-dir"/>
		<arg match="-fdebug-compilation-dir" value="sep" role="set-compilation-dir"/>

		<!-- diagnostics -->
		<arg match="-fdiagnostics-color -fcolor-diagnostics -fno-diagnostics-color -fno-color-diagnostics" value="eq" role="diagnostics-color"/>
		<arg match="-Werror -Wno-error" value="prefix-rest" role="hash-verbatim comp-only"/>

		<!-- inert, but in the key -->
		<arg match="-frecord-gcc-switches" value="none" role="hash-full-argv"/>
		<arg match="-frandom-seed=" value="eq" role="hash-verbatim" gate="random_seed"/>
		<arg match="-flto -fno-lto" value="prefix-rest" role="mode:lto hash-verbatim"/>
		<arg match="-fbuild-session-file=" value="eq" role="hash-normalized-path"/>
		<arg match="-ivfsoverlay -ivfsstatcache" value="sep" role="path-read" gate="ivfsoverlay"/>
		<arg match="-index-store-path" value="sep" role="hash-normalized-path" gate="clang_index_store"/>

		<!-- never cacheable -->
		<arg match="-save-temps --save-temps" value="prefix-rest" role="bypass:unsupported_compiler_option"/>
		<arg match="-ftime-trace -gen-cdb-fragment-path -frepo -gtoggle -wrapper -ast-view -ast-merge --analyzer-output -ast-dump" value="either" role="bypass:unsupported_compiler_option"/>

		<!-- link-only, hashed so they cannot silently differ -->
		<arg match="-L -l -Wl, -shared -pie -rdynamic -bundle -all_load -install_name -arch" value="either" role="hash-verbatim comp-only"/>
	</args>

	<verdict>
		<decline reason="autoconf_test" when="{{ and (not .mode.compiling) (contains \"conftest.\" .source.path) }}"/>
		<decline reason="called_for_link" when="{{ not .mode.compiling }}"/>
		<decline reason="unsupported_dep_output_combination" when="{{ and .seen.Wp-MD .seen.MF }}"/>
		<decline reason="unsupported_compiler_option" when="{{ gt (len .roles.path-read.profile) 1 }}"/>
		<decline reason="could_not_use_precompiled_header" when="{{ and .mode.pch-create (not (sloppy \"pch_defines\")) }}"/>
	</verdict>

	<discover direct="true" report="linemarkers">
		<preprocess>
			<argv><value name="tool.path"/></argv>
			<argv><value expr="{{ spread (argsWithout .argv \"primary-output\" \"dep-output\" \"comp-only\" \"mode:generating-deps\" \"mode:compiling\") }}"/></argv>
			<argv>-E</argv>
			<argv><if test="mode.debug-info"><else/><if test="mode.coverage"><else/>-P</if></if></argv>
			<argv><if test="mode.pch-use">-fpch-preprocess</if></argv>
		</preprocess>
		<depend report="depfile"/>
		<expand name="native"><argv><value name="tool.path"/></argv><argv>-###</argv><argv>-E</argv><argv>-</argv><argv><value expr="{{ spread .roles.hash-expanded }}"/></argv>
			<extract pattern="(cc1|cc1plus|-cc1) .*"/>
		</expand>
	</discover>

	<outputs hard-link="safe" require-primary="{{ not .mode.no-primary-output }}"/>

	<sloppiness>
		<allow name="time_macros"/><allow name="file_stat_matches"/><allow name="file_stat_matches_ctime"/>
		<allow name="include_file_mtime"/><allow name="include_file_ctime"/><allow name="locale"/>
		<allow name="pch_defines"/><allow name="random_seed"/><allow name="system_headers"/>
		<allow name="gcno_cwd"/><allow name="incbin"/><allow name="ivfsoverlay"/>
		<allow name="clang_index_store"/><allow name="modules"/><allow name="pragma_once_dedup"/>
	</sloppiness>
</tool>
</cache>
```

What the engine adds without a row: the `@file` expansion, the `-Wp,`/`-Xclang` re-dispatch, `.d` parsing and rewriting, the temporal-macro scan, `-fdiagnostics-color` forcing and stripping, the too-new check, the `#pragma once` guard, and the reverse-order prefix maps. The rule is ~90 rows and reads top to bottom as "what each flag means"; the computed tail is one preprocess argv and one expansion query.

**Clang-specific differences** (`-fcolor-diagnostics`, `-fdebug-compilation-dir`, `--config`, the `-cc1` extraction) are rows in the same file because gcc and clang share the CLI shape; the `real-match` tie-break sends `clang-cl` to the MSVC-syntax rule instead.

## MSVC (`rules/cl.xml`)

```xml
<tool name="cl" match="^cl(\.exe)?$" syntax="msvc" response-files="msvc" unknown="hash" version="1">
	<identity policy="command" memo="5m"><argv><value name="tool.path"/></argv></identity>   <!-- bare cl: banner on stderr, exit 0 -->
	<env>
		<hash>INCLUDE EXTERNAL_INCLUDE VCToolsVersion VCToolsInstallDir</hash>
		<bypass reason="unsupported_environment_variable">CL _CL_</bypass>
		<unset>VS_UNICODE_OUTPUT</unset>
	</env>
	<args default-output="{{ .source.base }}.obj" cwd-in-key="true">
		<arg match="/c" value="flag" role="mode:compiling"/>
		<arg match="/Zs" value="flag" role="mode:compiling mode:no-primary-output"/>
		<arg match="/E /EP /P" value="flag" role="bypass:called_for_preprocessing"/>
		<arg match="/link" value="flag" role="bypass:called_for_link"/>
		<arg match="/Fo" value="concat-colon" role="primary-output"/>            <!-- trailing \ = directory; separated form silently ignored by cl -->
		<arg match="/Fd" value="concat-colon" role="path-write-untracked"/>
		<arg match="/Fp" value="concat-colon" role="pch-path"/>
		<arg match="/Fe /Fm" value="concat" role="ignore"/>                       <!-- silently ignored under /c, measured -->
		<arg match="/Fa /FA /Fi /Fr /FR /Ft /Fx" value="concat" role="bypass:unsupported_compiler_option"/>
		<arg match="/Tc /Tp" value="either" role="source-input mode:language"/>
		<arg match="/TC /TP" value="flag" role="mode:language"/>
		<arg pattern="\.(c|cc|cpp|cxx)$" value="positional" role="source-input"/>
		<arg match="/Z7" value="flag" role="mode:debug-info"/>
		<arg match="/Zi /ZI" value="flag" role="bypass:unsupported_output_kind"/>  <!-- shared vc140.pdb accumulator; remedy /Z7 -->
		<arg match="/FS /MP" value="suffix" role="ignore"/>
		<arg match="/Gm" value="flag" role="bypass:unsupported_compiler_option"/>
		<arg match="/showIncludes" value="suffix" role="mode:include-report"/>
		<arg match="/sourceDependencies" value="either" role="dep-output:json"/>
		<arg match="/I" value="concat-colon" role="dir-read cpp-only"/>
		<arg match="/external:I" value="either" role="dir-read cpp-only"/>
		<arg match="/external:env:" value="suffix" role="env-read"/>
		<arg match="/external:W /external:anglebrackets" value="suffix" role="hash-verbatim"/>
		<arg match="/AI" value="concat" role="dir-read"/>
		<arg match="/D /U /u" value="concat" role="cpp-only"/>
		<arg match="/FI" value="either" role="path-read cpp-only resolve:source-dir"/>
		<arg match="/FU" value="either" role="bypass:unsupported_compiler_option"/>
		<arg match="/Yc" value="concat-colon" role="mode:pch-create"/>
		<arg match="/Yu" value="concat-colon" role="mode:pch-use"/>
		<arg match="/YI /Y-" value="concat" role="hash-verbatim"/>
		<arg match="/nologo /utf-8 /FC" value="flag" role="hash-verbatim"/>
		<arg match="/WX /WX-" value="flag" role="hash-verbatim comp-only"/>
		<arg pattern="^/W[0-4]$|^/w$" value="flag" role="hash-verbatim comp-only"/>
		<arg match="/Brepro" value="flag" role="hash-verbatim"/>                  <!-- does not make the object reproducible, measured -->
		<arg match="/experimental:module /interface /internalPartition /ifcOnly /ifcOutput /ifcSearchDir /ifcMap /stdIfcDir /reference /doc /experimental:log /dynamicdeopt" value="either" role="bypass:unsupported_compiler_option"/>
	</args>
	<verdict>
		<decline reason="called_for_link" when="{{ not .mode.compiling }}"/>
		<decline reason="unsupported_source_encoding" when="{{ .preprocess.stderr | contains \"C4828\" }}"/>
	</verdict>
	<discover direct="true" report="showincludes">
		<preprocess>
			<argv><value name="tool.path"/></argv>
			<argv><value expr="{{ spread (argsWithout .argv \"primary-output\" \"dep-output\" \"comp-only\" \"mode:compiling\") }}"/></argv>
			<argv>/E</argv><argv>/nologo</argv><argv>/showIncludes</argv><argv>/utf-8</argv><argv>/WX-</argv>
		</preprocess>
		<depend report="showincludes"/>
	</discover>
	<steps>
		<!-- the .pch content is a key input: cl does not detect a stale one (measured, exit 0 with old contents) -->
		<step name="pch" when="{{ .mode.pch-use }}" capture="hash">
			<run><argv>api-cache</argv><argv>internal</argv><argv>resolve-pch</argv><argv><value name="roles.pch-path"/></argv><argv><value name="roles.pch-use"/></argv><argv><value name="source.base"/></argv></run>
		</step>
	</steps>
	<outputs hard-link="unsafe" require-primary="{{ not .mode.no-primary-output }}"/>
	<sloppiness><allow name="time_macros"/><allow name="file_stat_matches"/><allow name="pch_defines"/></sloppiness>
</tool>
```

Notes the measurements forced (`plan/research/msvc-probes/README.md`): `/showIncludes` notes move to stderr under `/E`, so the preprocess reads the report from stderr; the source-name line on stdout is always the basename, so replayed stdout leaks no path; `cwd-in-key="true"` because cl objects embed their directory even without debug flags; the `/Yu` resolution (three steps: `/Fp`, the header with `.pch`, the source basename with `.pch`) is the one computed piece and lives in a step that hashes the resolved file, which is the escape hatch used as intended. `clang-cl` gets its own file with `real-match="clang$"`, stderr diagnostics, relative `/showIncludes` paths, `/Zi` cacheable (it writes no PDB), and `/clang:-MD /clang:-MF` for the dep file instead of `/sourceDependencies`, which it ignores silently.

## rustc (`rules/rustc.xml`)

```xml
<tool name="rustc" match="^rustc$" syntax="rustc" response-files="gnu" unknown="bypass" version="1">
	<identity policy="command" memo="5m">
		<argv><value name="tool.path"/></argv><argv>-vV</argv>
		<extra-file glob="{{ .sysroot }}/lib/*.so {{ .sysroot }}/lib/*.dylib {{ .sysroot }}/bin/*.dll"/>
	</identity>
	<env>
		<hash glob="CARGO_*" except="CARGO_MAKEFLAGS CARGO_REGISTRIES_* CARGO_BUILD_JOBS CARGO_ENCODED_RUSTFLAGS"/>
		<hash from-depinfo="true"/>       <!-- every # env-dep: record, unset distinct from empty -->
		<ignore>RUSTC_COLOR</ignore>
		<unset>LD_PRELOAD RUNNING_UNDER_RR HOSTNAME PWD HOST RPM_BUILD_ROOT SOURCE_DATE_EPOCH RPM_PACKAGE_RELEASE RPM_PACKAGE_VERSION MINICOM</unset>
	</env>
	<args cwd-in-key="true">
		<arg pattern="\.rs$" value="positional" role="source-input"/>
		<arg match="-" value="bare-dash" role="passthrough"/>                       <!-- cargo's --print=file-names probe -->
		<arg match="-vV -V --version -h --help --explain --print --test" value="long-eq-or-sep" role="passthrough"/>
		<arg match="--crate-name" value="long-eq-or-sep" role="hash-verbatim mode:crate-name"/>
		<arg match="--crate-type" value="comma-list" role="hash-verbatim mode:crate-type"/>
		<arg match="--edition" value="long-eq-or-sep" role="hash-verbatim"/>
		<arg match="--emit" value="comma-list" role="mode:emit"/>
		<arg match="--out-dir" value="long-eq-or-sep" role="output-dir"/>
		<arg match="-o" value="short-concat-or-sep" role="bypass:unsupported_compiler_option"/>
		<arg match="-C extra-filename" value="kv" role="hash-verbatim mode:extra-filename"/>
		<arg match="-C metadata" value="kv" role="hash-verbatim"/>
		<arg match="-C incremental" value="kv" role="bypass:incremental_state"/>
		<arg match="-C profile-use" value="kv" role="path-read"/>
		<arg match="-C" value="kv" role="hash-verbatim"/>
		<arg match="-g -O" value="none" role="hash-verbatim"/>
		<arg match="--cfg" value="long-eq-or-sep" role="hash-verbatim sort"/>
		<arg match="--check-cfg" value="long-eq-or-sep" role="ignore"/>
		<arg match="--extern" value="kv" role="path-read hash-binding sort"/>
		<arg match="-L" value="kinded-path" role="dir-read"/>
		<arg match="-l" value="kinded-name" role="hash-verbatim resolve:static-archive"/>
		<arg match="--target" value="long-eq-or-sep" role="hash-verbatim" when="{{ not (hasSuffix \".json\" .value) }}"/>
		<arg match="--target" value="long-eq-or-sep" role="path-read" when="{{ hasSuffix \".json\" .value }}"/>
		<arg match="--sysroot" value="long-eq-or-sep" role="bypass:unsupported_compiler_option"/>
		<arg match="--remap-path-prefix" value="long-eq-or-sep" role="prefix-map"/>
		<arg match="--error-format --json --color" value="long-eq-or-sep" role="hash-verbatim"/>
		<arg match="--diagnostic-width" value="long-eq-or-sep" role="ignore"/>
		<arg match="-A -W -D -F --allow --warn --force-warn --deny --forbid --cap-lints" value="short-concat-or-sep" role="hash-verbatim"/>
		<arg match="-Z" value="short-concat-or-sep" role="hash-verbatim"/>
		<arg match="-Zprofile" value="none" role="derived-output:.gcno"/>
	</args>
	<verdict>
		<decline reason="no_input_file" when="{{ eq (len .roles.source-input) 0 }}"/>
		<decline reason="unsupported_compiler_option" when="{{ or (not .mode.emit) (gt .seen.emit 1) (not (subset .mode.emit (list \"link\" \"metadata\" \"dep-info\"))) (eq (join .mode.emit) \"dep-info\") }}"/>
		<decline reason="unsupported_compiler_option" when="{{ or (not .mode.crate-name) (not .roles.output-dir) (eq .mode.extra-filename \"\") }}"/>
	</verdict>
	<discover direct="true" report="depinfo">
		<preprocess>
			<argv><value name="tool.path"/></argv>
			<argv><value expr="{{ spread (argsWithout .argv \"mode:emit\" \"output-dir\") }}"/></argv>
			<argv>--emit=dep-info</argv><argv>-o</argv><argv><value name="run.tmpdir"/>/dep.d</argv>
		</preprocess>
	</discover>
	<outputs hard-link="unsafe" require-primary="true">
		<query><argv><value name="tool.path"/></argv><argv><value expr="{{ spread (argsWithout .argv \"mode:emit\") }}"/></argv><argv>--print</argv><argv>file-names</argv></query>
		<derive from="query" ext=".rmeta" for-ext=".rlib" when="{{ has \"metadata\" .mode.emit }}"/>
		<derive name="{{ .mode.crate-name }}{{ .mode.extra-filename }}.d" when="{{ has \"dep-info\" .mode.emit }}"/>
		<prune from="query" kind="binary" when="{{ not (has \"link\" .mode.emit) }}"/>
	</outputs>
</tool>
```

The `-l static=` resolution along `-L native` paths and the archive-aware digest are engine roles (`resolve:static-archive`, with `unresolvable_input` as the decline). The two passthrough rows keep cargo's probes fast. Plain `cargo build` in the dev profile emits `-C incremental` and is declined with a reason whose message says `CARGO_INCREMENTAL=0`; that is the single most common "it never hits" report for sccache and the reason is now loud.

## Go: `api-cache gocacheprog`

Go needs no wrapper and no rule file. `GOCACHEPROG=api-cache gocacheprog` starts one process per `go` invocation that speaks the JSON-lines protocol (`plan/research/compile-semantics/go-and-others.md` §1): the `ID == 0` handshake with `KnownCommands`, `get`, `put` and `close`, the body on its own base64 line, and `DiskPath` for every hit and put. The go command derives `ActionID` itself; api-cache does storage only:

- A `put` writes the body to the local store under namespace `go/<ActionID hex>` as a one-block entry with `OutputID` in the directory, and spools the remote upload.
- A `get` answers from the local store, then the remote, and materialises the body as a file under the store's `go/` tree whose path survives until `close`.
- `OutputID` is `sha256(body)` by the protocol's definition, verified on every remote fetch, which is the one place SHA-256 is used.
- stderr is silent by default because it is the go command's stderr.

## Generic actions (`rules/generic.xml`)

For protoc, clang-tidy, codegen and anything Bazel-shaped where the inputs are stated rather than discovered:

```xml
<tool name="protoc" match="^protoc$" syntax="gnu" unknown="hash" version="1">
	<identity policy="content"/>
	<env><hash>PROTOC_INCLUDE</hash></env>
	<args>
		<arg match="-I --proto_path" value="either" role="dir-read"/>
		<arg match="--dependency_out" value="eq" role="dep-output"/>
		<arg pattern="^--[a-z_]+_out$" value="eq" role="output-dir:derived"/>
		<arg pattern="\.proto$" value="positional" role="source-input"/>
	</args>
	<discover direct="true"><depend report="depfile"/></discover>
	<outputs>
		<derive name="{{ .source.stem }}.pb.cc" in="cpp_out"/>
		<derive name="{{ .source.stem }}.pb.h" in="cpp_out"/>
	</outputs>
</tool>
```

The generic mode's key is `hash(identity, classified argv, sorted (relpath, digest) of every declared input, env allowlist, normalised cwd)`, Bazel's Action model without the Merkle tree (`go-and-others.md` §6). A `<inputs>` element with `<glob>` children covers tools with no dep output, and `<extra-file>` covers implicit inputs found by search such as `.clang-tidy`. clang-tidy's rule has no file outputs; its stdout, stderr and exit code are the whole result, which the engine already treats as first-class.

## Out of the first release

nvcc (a driver that fans out into several sub-commands in two working directories; sccache decomposes it with `--dryrun`, and a rule could express that with `<step over=>`, but nobody here needs it), Swift and javac (their build systems own caching), linkers (near-zero hit rate for a wrapper; the generic mode can express one), and C++20 modules beyond a stated bypass.
