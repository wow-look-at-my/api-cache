# config load cost: Darwin arm64

> Measured on a GitHub Actions hosted runner. Not a development machine.

- runner label: `macos-latest`
- commit: `9b08f713116e98c791d5c07099188657b1704fbd`
- run: https://github.com/wow-look-at-my/api-cache/actions/runs/34728781892
- cpu cores: 3
- go: go version go1.24.13 darwin/arm64
- method: in-process, median of 400 iterations per stage

# xml load cost

- file: `/Users/runner/work/api-cache/api-cache/plan/research/startup-perf/probes/fixtures/github.xml`
- size: 30749 bytes, 663 lines
- DOM nodes: 528
- compiled templates (elements whose content holds a placeholder): 76
- iterations per stage: 400

- serialized sizes: xml 30749 B, gob 28737 B, flat 31202 B, cooked-templates 2862 B

| stage | min us | p50 us | p90 us | mean us | note |
|---|---|---|---|---|---|
| read file | 11.0 | 15.1 | 60.4 | 26.8 | os.ReadFile, warm page cache |
| parse (ParseDOM) | 619.8 | 766.0 | 1314.3 | 879.1 | encoding/xml into the DOM, file already in memory |
| parse + compile | 664.4 | 755.5 | 1074.2 | 830.2 | ParseDOM then CompileContent over every element |
| apidsl.FuncMap() | 4.7 | 5.9 | 11.7 | 8.8 | sprig TxtFuncMap plus the language's own helpers |
| template.Parse x20 | 621.8 | 824.0 | 1317.1 | 919.7 | text/template.Parse of 20 compiled sources, func map attached |
| template.Execute x20 | 9.5 | 10.3 | 11.2 | 10.6 | executing the 20 already-parsed templates |
| FULL: read+parse+compile+tparse | 1345.4 | 1754.9 | 2353.0 | 1897.3 | everything a naive per-exec load does, minus Execute |
| gob decode (DOM mirror) | 234.2 | 281.1 | 630.3 | 366.6 | encoding/gob of the whole DOM |
| flat decode (DOM) | 15.9 | 18.9 | 23.7 | 25.6 | hand-rolled string table + node array |
| cooked decode (templates only) | 1.1 | 1.4 | 2.0 | 1.9 | length-prefixed compiled template sources, no DOM |
| cooked decode + tparse x20 | 652.0 | 846.9 | 1406.0 | 949.7 | the cooked form still pays text/template.Parse |
| template.Parse x1 (largest) | 33.4 | 43.3 | 88.9 | 58.1 | one template, 436 bytes of source |
| template.Parse x1 (smallest) | 30.3 | 39.9 | 79.4 | 56.3 | one template, 13 bytes of source |
| template.Parse xALL (76) | 2664.6 | 3298.0 | 4260.3 | 3493.5 | every placeholder-bearing element in the config |
| template.Parse x20, NO func map | 56.3 | 73.7 | 172.9 | 96.4 | same sources, Funcs() never called: isolates the map copy |
| LAZY: cooked decode + 1 parse + 1 exec | 39.2 | 53.5 | 92.3 | 62.6 | what a wrapper pays when it parses only the template it reaches |
| shared-root Parse x20 (full func map) | 71.8 | 144.1 | 228.2 | 157.3 | one root carries the 214-entry map, 20 associated templates |
| shared-root Parse xALL (full func map) | 180.9 | 223.8 | 509.5 | 288.3 | one root, 76 associated templates |
| Parse x20, 5-entry func map | 49.2 | 62.5 | 149.0 | 93.9 | per-template Funcs() but with sprig dropped |
| BEST: cooked decode + shared-root Parse xALL | 178.2 | 206.7 | 486.8 | 258.8 | cooked form plus a single func-map copy: the whole per-exec config cost |

