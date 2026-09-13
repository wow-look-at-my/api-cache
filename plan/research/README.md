# Research workers

Each subdirectory holds one worker's raw findings for the api-cache plan.
The synthesized plan lives one level up in `plan/*.md`.
Nothing here is a decision. It is evidence, measurements, and options.

## Workflow convention for workers

- Benchmarks run on GitHub Actions runners, never in the shared sandbox. Local runs only prove a probe starts.
- Each worker owns its workflow file(s), named after the worker (`<worker>.yml`, extra files `<worker>-<topic>.yml`), so runs are found by name.
- A workflow's push trigger is scoped with `paths:` to that workflow file and the worker's own directory, and nothing else. No `concurrency:` block at all. Keep `workflow_dispatch`.
- Timing uses hyperfine (`--shell=none`, warmup, 300+ runs, markdown and JSON export). Results are copied from the run's artifacts into `plan/research/<worker>/results/` with the runner label and run URL.
- **Never allow silent failure.** No `continue-on-error`, no `if: steps.x.outcome`, no `|| true` on a probe, no "skip when unavailable" branch, no partial result written as if complete. A missing prerequisite fails the job loudly, and the worker reports it to the coordinator, who tells the user. A wrong or incomplete result is worse than no result.
- **Any repository a probe or a plan depends on is a git submodule under `refs/`** (`git submodule add <url> refs/<name>`), never a CI-time checkout of a second repository and never a clone outside the tree. Workflows check out with `submodules: true`. A Go probe reaches a submodule through a relative `replace` directive.
- **Filenames must be valid on Windows.** No `\`, `:`, `*`, `?`, `"`, `<`, `>` or `|` in a committed path. A probe that needs such a name creates it at run time.
