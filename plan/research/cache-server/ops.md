# Operations surface

Metrics, dashboard, logging, memory control, config, deployment, tests.
This is the half of go-s3-server that is *not* protocol, and it is where the
highest-confidence reuse lies — none of it assumes Go build caching.

**Framing note:** the org tooling named here (go-toolchain, the fat-APE
autorelease, buildhost, dats) is described because it is what this repo uses,
**not** as a recommendation for api-cache. api-cache is clean-slate; these are
data points about how the reference implementation is operated, to be adopted or
discarded on merit.

## 1. Config file

JSON, one file, `--config` required (`main.go:42-43`). `LoadConfig`
(`config.go:225-305`) validates and defaults.

| Field | Type | Default | Notes |
|---|---|---|---|
| `listen` | string | `":9000"` | cache protocol port |
| `metrics_listen` | string | `""` (off) | Prometheus `/metrics` |
| `dashboard_listen` | `*string` | `":9002"`; explicit `""` disables | pointer so absent ≠ off |
| `bucket` | string | **required** | one fixed string, path segment 1 |
| `data_dir` | string | **required** | |
| `write_once` | object | `{action:"allow", notification:"never"}` | `action`∈{allow,deny}, `notification`∈{never,always,content_differs} |
| `disable_auth` | bool | false | mutually exclusive with `credentials` |
| `credentials` | `[]{username,password}` | required unless `disable_auth` | both fields non-empty or load fails |
| `log_mode` | string | `"normal"` | or `"verbose"` |
| `max_concurrent_requests` | int | 128 | `defaultMaxConcurrentRequests`, `config.go:194` |
| `index_blob_interval` | `*Duration` | 15s | `"0s"` serializes every GET after a PUT |
| `max_object_bytes` | int64 | 1 GiB | `config.go:195` |
| `eviction.max_bytes` | `*int64` | 50 GiB, or `CACHE_MAX_BYTES` | explicit `0` disables |
| `eviction.max_age` | Duration | `0` (off) | negative is a config error |
| `eviction.interval` | Duration | 24h | |

Two type tricks worth stealing:

- **`ConfigString`** (`config.go:14-53`) accepts a literal string **or**
  `{"type":"envvar","name":"VAR"}`, resolved at load. An env var resolving to
  `""` is rejected exactly like a literal empty string, so an unset var cannot
  silently disable auth (`config.go:38-43`, `:297-303`).
- **`Duration`** (`config.go:68-103`) unmarshals from a Go duration string,
  from a JSON number as seconds, or from `null` (= 0). Marshals back canonical.
- **`parseByteSize`** (`config.go:337-361`): `"50GB"`, `"50 GiB"`, `"512M"`,
  or a plain count. **Both KiB and KB spellings mean powers of 1024**, on the
  stated grounds that "nobody writing 50GB for a cache budget means
  50,000,000,000 bytes exactly." A set-but-unparseable `CACHE_MAX_BYTES` fails
  startup rather than reverting to the default (`config.go:311-325`).

CLI overrides: `--listen`, `--bucket`, `--data-dir`, `--metrics-listen`,
`--dashboard-listen` (`off` disables — an unset flag is also empty, so `""`
cannot mean off), `--log-mode` (`main.go:44-49`, `:75-92`).

For api-cache the interesting question is whether the same knobs survive a
translation to declarative XML. They are all scalars and one small object, so
yes — but `credentials` and the env-var indirection are the parts that would
have to be expressed in the XML vocabulary rather than borrowed.

## 2. Metrics

Prometheus, on a **separate listener** (`main.go:124-127`). A metrics listener
that fails to bind **logs and the server runs without metrics** — it never kills
the process (CLAUDE.md).

Prefixes are inconsistent: five are `cache_*`, the rest `s3_*` (kept "until the
repository rename").

**HTTP** (`metrics.go:16-63`)
- `cache_http_requests_total{method,route,status}`
- `cache_http_request_duration_seconds{method,route}` (DefBuckets)
- `cache_http_request_size_bytes{method,route}` (Exponential 256,4,8)
- `cache_http_response_size_bytes{method,route}`
- `cache_http_in_flight_requests`
- `s3_http_rejected_total` — admission-control sheds. "the observable
  backpressure metric."
- `s3_deprecated_requests_total{feature}` — should trend to zero.

**PUT refusals** (`:66-80`)
- `s3_put_refusals_total{reason}` — `reason="module_index"`. The comment is a
  lesson: "a broken guard is indistinguishable from a quiet one", so the
  counter being occasionally non-zero during CI is the guard's **liveness
  proof**; a flat zero across busy periods means it is broken again.

**Batch** (`:83-111`)
- `s3_batch_requests_total`
- `s3_batch_keys_total{kind=requested|found|prefetched|suppressed|streamed}` —
  "A falling found/requested ratio is the earliest 'cache is fickle' indicator."
- `s3_prefetch_scan_exhausted_total` — zero is normal.

**Index** (`:114-140`)
- `s3_index_entries`, `s3_index_hashes`, `s3_index_pending_hashes`
- `s3_index_rebuild_duration_seconds`
- "A post-sweep dip in `s3_index_hashes` that PUT volume does not explain is the
  signature of a rebuild dropping keys."

**Storage** (`:143-172`)
- `cache_storage_operations_total{op,status}` (op ∈ put/get/delete/list)
- `cache_storage_operation_duration_seconds{op}`
- `s3_metadata_xattrs_dropped_total`
- `cache_auth_failures_total`

**Eviction** (`:176-193`)
- `s3_evictions_total`, `s3_evicted_bytes_total`, `s3_cache_bytes`
  (refreshed every 15 min, not only at sweep end)

**Self-heal** (`:205-235`)
- `s3_self_heal_repairs_total`, `s3_self_heal_failures_total`,
  `s3_outputid_mismatch_total`

**GET outcomes / guards** (`:258-292`)
- `s3_get_requests_total{outcome}` — the six outcomes in wire-protocol.md §4.
  `miss_advertised_unservable` is the index/store-divergence tripwire and "must
  stay near zero."
- `s3_module_index_evictions_total`
- `s3_meta_cache_hits_total`, `s3_meta_cache_misses_total` — "On a warm cache
  that ratio IS the read path's CPU story."

**Memory** (`:298-322`)
- `s3_memory_limit_bytes`, `s3_memory_in_use_bytes`, `s3_memory_shrinks_total`,
  `s3_cache_memory_bytes{cache}`, `s3_cache_memory_budget_bytes{cache}`

`statusRecorder` forwards `io.ReaderFrom` so a GET body copy keeps the sendfile
path (CLAUDE.md).

**Assessment:** the *set* of metrics is excellent and mostly generic. The
noteworthy design idea is that several counters exist as **liveness proofs of a
guard**, not as volume counters — a guard nobody can see fail is a guard nobody
knows is broken. That idea transfers regardless of what api-cache's guards are.

## 3. Logging

Two modes (`logagg.go:43-46`, config `log_mode`):

- **`verbose`**: one line per request, and **only one**. A handler with something
  to add attaches it to the *same* line via `auditInfo.note`
  (`server.go:125-130`, `batch.go:370-371`), "so a single request never appears
  twice under two spellings."
- **`normal`** (default): nothing per request. One line per **second in which
  the cache moved objects**: objects stored/served, the batch share, byte rates
  on and off the wire, and which projects the traffic belonged to, capped at
  `maxLoggedProjects = 8` (`logagg.go:49`). Rationale: "A CI fleet issues
  thousands of requests a second, so a per-request log is unreadable exactly when
  it is most needed."

The aggregator distinguishes **wire bytes** (compressed, what crossed the
network) from **raw bytes** (from the `body-size` metadata) — `logagg.go:57-62`,
`rawSizeOf`. A missing `body-size` reports as *unsized*, never as zero.

Project attribution (`projectOf`, `logagg.go:332-347`): the object's `module`
metadata, else the first three segments of `pkg`, else the requesting client's
`X-Cache-Module`. Go-specific in the fields, generic in the idea (attribute
traffic to a unit a human recognizes).

Client side has its own coalescing error logger (`cacheclient/httperrlog.go`)
grouping identical `(op, status, body)` failures on an interval.

**Assessment: the two-mode design is a strong, generic idea** and worth copying
wholesale. A build cache's normal state is "thousands of requests a second, all
fine"; the default log must describe *throughput*, not requests.

## 4. Memory controller

`memlimit.go`. Philosophy in the header (`:15-37`): "it holds less, never serves
less."

- `resolveMemoryBudget()` is called from `run()`, **never** a package
  initializer (`main.go:53-55`, `memlimit.go:82-93`). Reason: go-toolchain
  injects an `init()` that sets `GOMEMLIMIT` from the cgroup, and Go runs
  package-var initializers **before** any `init()` — so detecting early read the
  raw container limit, "a ceiling nothing enforced."
- Discovery order: `debug.SetMemoryLimit(-1)` (reports GOMEMLIMIT or the
  injected guard), then the cgroup files, then zero = unknown.
- Per-cache budget fractions (`:43-46`): metadata 10%, clean memo 3%, prefetch
  tracker 2%. Fixed fallbacks when the ceiling is unknown: 32/16/8 MiB (`:49-51`).
- The loop (`:53-74`) samples every **250 ms** and moves **one number**, the
  scale. Above **85%** in use: `scale *= 0.5`, evict, release memory to the OS.
  Below **65%**: `scale *= 1.25`. The gap is deliberate hysteresis. Shrink
  cooldown 2s, grow cooldown 30s — "Shrink fast (memory pressure is urgent),
  grow slowly (do not re-create the pressure you just relieved)." Floor at
  1/32, where it stops and logs that the container needs more memory.
- **It cannot touch request handling** (`server.go:47-50`).
- An unknown budget disables the controller entirely — "An unknown limit must not
  become an invented one."

**Fully generic and one of the best-argued pieces in the repo.** Any cache
server with reconstructible in-memory state wants this shape.

## 5. Dashboard

`dashboard.go` + embedded `dashboard.html/css/js`. `docs/dashboard.md`.

- Own port, default `:9002`. `--dashboard-listen off` or config `""` disables.
  A bind failure logs and the cache keeps serving.
- Paths: `/`, `/dashboard.css`, `/dashboard.js`, `/api/stats`, `/_health`.
- `/api/stats` **flattens the same Prometheus registry** `/metrics` serves. The
  dashboard keeps no counters of its own, so page and scrape can never disagree.
  A histogram contributes `_count` and `_sum`; buckets stay in `/metrics`.
- Rates are computed **in the browser** from consecutive polls (5s). A counter
  going backwards means a restart, so the page clears history rather than
  drawing a negative rate.
- Cache size comes from `s3_cache_bytes`, written at a sweep and every 15 min;
  before the first measurement the page says "not measured", **never `0 B`**.
- **No authentication, deliberately** — publish through an access proxy.
  `TestDashboardStatsCarryNoCredentials` holds the line that the snapshot
  reports configuration but never credentials.
- `docs/dashboard.md` carries a worked Cloudflare Zero Trust ingress: an Access
  policy on the dashboard hostname **only**, never on the cache port, "because
  the client cannot complete a browser login."

Note api-mirror's CLAUDE.md takes the opposite position for its own dashboard
("With no `<token>` the engine mints one per process and logs the URL carrying
it: on by default, never open by default"). **Two sibling repos disagree on
this; api-cache should pick deliberately.**

## 6. Deployment

- **No Dockerfile, on purpose** (CLAUDE.md). buildhost synthesizes a runnable
  image from the uploaded binary at `oci.pazer.build/v2/go-s3-server`, setting
  entrypoint, WorkingDir, Env and User itself. The build names no `os`/`arch`,
  so it produces one fat APE.
- The deploy bind-mounts a host directory at `/var/lib/go-s3-server` and passes
  its own `--config`. "A restart without that mount costs every client a full
  rebuild."
- Shutdown: SIGINT/SIGTERM → `BeginShutdown()` (flips `/_health` to 503) →
  `httpSrv.Shutdown(ctx)` with `shutdownTimeout = 280s`, kept under
  docker-updater's 300s ContainerStop grace (`main.go:28-32`, `:190-203`).
- HTTP server sets `ReadHeaderTimeout = 15s` (slowloris guard) and
  `IdleTimeout = 120s`, and **no** `ReadTimeout`/`WriteTimeout`
  (`main.go:16-26`).
- `/.well-known/docker-updater/{health,pre-update}` (`server.go:33-36`) are
  aliases of the drain flag so docker-updater discovers them with no label.
  Pre-update never holds an update for in-flight requests: "A cache miss costs a
  rebuild. Nothing here is unrecoverable."
- Startup warnings that matter: eviction disabled (`main.go:121`), auth disabled
  (`main.go:140`), atime not recorded (`main.go:221`), ZFS compression under the
  data_dir (`logCompressionAdvisory`, `main.go:166`), no memory ceiling
  discovered (`main.go:159`).

## 7. Tests and CI

- **`dats/`** — "the executable spec for the HTTP surface." Four suites:
  `api.dats` (roundtrip, not_found, overwrite, sharding, native and legacy
  metadata, `/_index` and its ETag, the unauthenticated health probe, the
  refusals), `writeonce.dats`, `dashboard.dats`, `logmodes.dats`. Each test
  starts **its own server on its own port** through a shared `serve.sh` heredoc
  embedded in the suite (`dats/api.dats:3-40`), so no two tests share a
  resource. `serve.sh` polls `/_health` up to 100×0.1s, and on a check failure
  **dumps the server's log prefixed `server:`** — because "the one process that
  knows why says nothing" otherwise.
- **`cacheclient_wire_test.go`** — the real client↔server round trip, as a Go
  test rather than a dats suite, because "the sandbox has no network, does not
  mount the toolchain cache, and carries only a stock `go`." It uploads through
  the PUT coalescer, then checks a **second, stateless backend** is served every
  body off the server via `s3_batch_keys_total{kind="streamed"}`, and that each
  body hashes to the output ID it came back under.
- **`.github/workflows/ci.yml`** — two jobs, `test` and `cacheclient`, both just
  `actions/checkout` + `wow-look-at-my/go-toolchain@master`. The `test` job first
  installs bubblewrap for the dats sandbox. The `cacheclient` job runs
  go-toolchain with `working-directory: cacheclient` and `autorelease: false`,
  **beside** the server's job, not after it. **No job carries an assertion of its
  own** — every assertion lives in `dats/` or a Go test, "so a contributor runs
  exactly what CI runs."
- Coverage minimum 80% (CLAUDE.md). File size warns at 500 lines, fails at 750.

**The transferable ideas, independent of the org tooling:** (a) an executable
HTTP-surface spec that runs the real binary and starts a fresh server per test;
(b) CI that asserts nothing itself, so `run the tests` locally and `CI` are the
same command; (c) a wire round-trip test that proves a *second, cold* client can
read what a first one wrote — which is the only test that actually proves a
cache works.
