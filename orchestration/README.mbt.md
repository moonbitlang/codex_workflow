# bobzhang/codex_workflow/orchestration

Workflow execution helpers that bind `@dag` to Codex runtime.

## Overview

This package executes DAGs by running nodes in dependency waves, applying
concurrency limits, and collecting each node's final response.

## Public API

- `run_workflow` executes a workflow and returns node outputs.

## Example: running a workflow

```mbt nocheck
async fn run {
  match @dag.sample_workflow("kickoff") {
    Some(workflow) => {
      let options = @dag.RunOptions::new(".", 2)
      let codex = @codex.Codex::new()
      let outputs = @orchestration.run_workflow(
        workflow,
        codex,
        options,
      ) await
      ignore(outputs)
    }
    None => ()
  }
}
```

## Notes

- `run_workflow` logs progress to stdout/stderr.
- Individual node failures become `"ERROR: ..."` outputs instead of halting the run.
- Sample workflows are now in the `dag` package (`@dag.sample_workflow`, `@dag.sample_names`).
