# Research workers

Each subdirectory holds one worker's raw findings for the api-cache plan.
The synthesized plan lives one level up in `plan/*.md`.
Nothing here is a decision. It is evidence, measurements, and options.

## Workflow convention for workers

- Benchmarks run on GitHub Actions runners, never in the shared sandbox. Local runs only prove a probe starts.
- Each worker owns its workflow file(s), named after the worker (`<worker>.yml`, extra files `<worker>-<topic>.yml`), so runs are found by name.
- A workflow's push trigger is scoped with `paths:` to that workflow file and the worker's own directory, and nothing else. No `cancel-in-progress`. Keep `workflow_dispatch`.
- Timing uses hyperfine (`--shell=none`, warmup, 300+ runs, markdown and JSON export). Results are copied from the run's artifacts into `plan/research/<worker>/results/` with the runner label and run URL.
