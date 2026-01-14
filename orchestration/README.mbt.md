# codex_worfkow/orchestration

Workflow execution helpers that bind `@codex_worfkow/dag` to Codex runtime.

## Overview

This package executes DAGs by running nodes in dependency waves, applying
concurrency limits, and collecting each node's final response. It also ships
small sample workflows for demos and CLI help output.

## Public API

- `run_workflow` executes a workflow and returns node outputs.
- `sample_workflows` provides built-in workflows (`kickoff`, `review`).
- `sample_workflow` looks up a workflow by name.
- `sample_names` returns the sample names in display order.

## Example: querying samples

```mbt check
test {
  let names = @codex_worfkow/orchestration.sample_names()
  inspect(names, content="[\"kickoff\", \"review\"]")
}

test {
  let label = match @codex_worfkow/orchestration.sample_workflow("kickoff") {
    Some(_) => "some"
    None => "none"
  }
  inspect(label, content="some")
}
```

## Example: running a workflow

```mbt nocheck
async fn run {
  match @codex_worfkow/orchestration.sample_workflow("kickoff") {
    Some(workflow) => {
      let options = @codex_worfkow/dag.RunOptions::new(".", 2)
      let codex = @codex.Codex::new()
      let outputs = @codex_worfkow/orchestration.run_workflow(
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
