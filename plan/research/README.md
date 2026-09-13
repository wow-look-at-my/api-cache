# Research workers

Each subdirectory holds one worker's raw findings for the api-cache plan.
The synthesized plan lives one level up in `plan/*.md`.
Nothing here is a decision. It is evidence, measurements, and options.

## Workflow convention for workers

- Benchmarks run on GitHub Actions runners, never in the shared sandbox. Local runs only prove a probe starts.
- Each worker owns its workflow file(s), named after the worker (`<worker>.yml`, extra files `<worker>-<topic>.yml`), so runs are found by name.
- A workflow's push trigger is scoped with `paths:` to exactly two files: the workflow file itself and `plan/research/<worker>/TRIGGER`. A worker starts a run by writing the current timestamp into its TRIGGER file and pushing; ordinary progress commits never start a run. Every workflow has exactly this concurrency block, keyed on its own filename: `concurrency: { group: <workflow-name>, cancel-in-progress: true }`. A new run of a workflow cancels that workflow's previous run. Keep `workflow_dispatch`.
- Timing uses hyperfine (`--shell=none`, warmup, 300+ runs, markdown and JSON export). Results are copied from the run's artifacts into `plan/research/<worker>/results/` with the runner label and run URL.
- **Never allow silent failure.** No `continue-on-error`, no `if: steps.x.outcome`, no `|| true` on a probe, no "skip when unavailable" branch, no partial result written as if complete. A missing prerequisite fails the job loudly, and the worker reports it to the coordinator, who tells the user. A wrong or incomplete result is worse than no result.
- **Any repository a probe or a plan depends on is a git submodule under `refs/`** (`git submodule add <url> refs/<name>`), never a CI-time checkout of a second repository and never a clone outside the tree. Workflows check out with `submodules: true`. A Go probe reaches a submodule through a relative `replace` directive.
- **Filenames must be valid on Windows.** No `\`, `:`, `*`, `?`, `"`, `<`, `>` or `|` in a committed path. A probe that needs such a name creates it at run time.
- **Waiting for a run uses gh-wait-ci** (wow-look-at-my/gh-wait-ci, built from source at `/home/user/tools/bin/gh-wait-ci`, with `gh` beside it): `gh-wait-ci --repo wow-look-at-my/api-cache <run-id> --timeout 30m`. Never poll, never sleep-loop.
