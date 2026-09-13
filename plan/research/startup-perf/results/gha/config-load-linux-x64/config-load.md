# config load cost: Linux x86_64

> Measured on a GitHub Actions hosted runner. Not a development machine.

- runner label: `ubuntu-latest`
- commit: `9f959561cc090a9621816566731bcc36457e3d05`
- run: https://github.com/wow-look-at-my/api-cache/actions/runs/34728324912
- cpu cores: 4
- go: go version go1.24.13 linux/amd64
- method: in-process, median of 400 iterations per stage

# xml load cost

- file: `/home/runner/work/api-cache/api-cache/plan/research/startup-perf/probes/fixtures/github.xml`
- size: 30749 bytes, 663 lines
- DOM nodes: 528
- compiled templates (elements whose content holds a placeholder): 76
- iterations per stage: 400

- serialized sizes: xml 30749 B, gob 28737 B, flat 31202 B, cooked-templates 2862 B

| stage | min us | p50 us | p90 us | mean us | note |
|---|---|---|---|---|---|
| read file | 9.8 | 10.8 | 19.1 | 15.8 | os.ReadFile, warm page cache |
| parse (ParseDOM) | 812.2 | 897.5 | 1243.1 | 957.1 | encoding/xml into the DOM, file already in memory |
| parse + compile | 972.3 | 993.2 | 1364.1 | 1069.5 | ParseDOM then CompileContent over every element |
| apidsl.FuncMap() | 7.0 | 7.6 | 11.0 | 9.2 | sprig TxtFuncMap plus the language's own helpers |
| template.Parse x20 | 777.9 | 808.8 | 1225.7 | 917.1 | text/template.Parse of 20 compiled sources, func map attached |
| template.Execute x20 | 15.3 | 15.8 | 19.8 | 18.2 | executing the 20 already-parsed templates |
| FULL: read+parse+compile+tparse | 1687.9 | 2268.6 | 3251.1 | 2438.6 | everything a naive per-exec load does, minus Execute |
| gob decode (DOM mirror) | 332.5 | 344.4 | 389.0 | 371.7 | encoding/gob of the whole DOM |
| flat decode (DOM) | 20.5 | 21.6 | 24.8 | 26.8 | hand-rolled string table + node array |
| cooked decode (templates only) | 1.6 | 1.7 | 2.1 | 2.5 | length-prefixed compiled template sources, no DOM |
| cooked decode + tparse x20 | 731.2 | 822.9 | 1207.4 | 925.8 | the cooked form still pays text/template.Parse |
| template.Parse x1 (largest) | 40.7 | 42.9 | 55.2 | 50.1 | one template, 436 bytes of source |
| template.Parse x1 (smallest) | 36.0 | 38.4 | 58.6 | 45.9 | one template, 13 bytes of source |
| template.Parse xALL (76) | 3038.6 | 3416.6 | 4191.8 | 3584.5 | every placeholder-bearing element in the config |
| template.Parse x20, NO func map | 48.6 | 50.2 | 65.1 | 58.9 | same sources, Funcs() never called: isolates the map copy |
| LAZY: cooked decode + 1 parse + 1 exec | 45.1 | 47.9 | 65.0 | 56.2 | what a wrapper pays when it parses only the template it reaches |
| shared-root Parse x20 (full func map) | 91.0 | 94.7 | 118.3 | 109.1 | one root carries the 214-entry map, 20 associated templates |
| shared-root Parse xALL (full func map) | 251.9 | 276.1 | 388.7 | 312.8 | one root, 76 associated templates |
| Parse x20, 5-entry func map | 74.3 | 75.9 | 87.5 | 84.7 | per-template Funcs() but with sprig dropped |
| BEST: cooked decode + shared-root Parse xALL | 270.3 | 279.1 | 463.6 | 321.8 | cooked form plus a single func-map copy: the whole per-exec config cost |

