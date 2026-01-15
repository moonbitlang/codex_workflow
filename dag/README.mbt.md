# codex_worfkow/dag

Workflow DAG types plus lightweight rendering helpers.

## Overview

This package defines the data model for a workflow: agent profiles, task nodes,
and execution options. It also includes formatting helpers that describe the
workflow in human-readable form for logs, plans, or quick inspections.

## Core types

- `AgentSpec` configures a named agent (role, model override, sandbox mode, and working directory).
- `TaskNode` defines a unit of work with dependencies and a prompt.
- `Workflow` bundles agents and nodes into a DAG definition.
- `RunOptions` provides execution defaults for orchestration runners.

## Rendering helpers

- `describe_workflow` prints a summary of agents and node dependencies.
- `render_workflow_dag` draws an ASCII DAG using node ids.
- `render_workflow_plan` produces topological "waves" and reports obvious graph errors.

## Example

```mbt check
///|
test {
  let agent = @dag.AgentSpec::new(
    "planner", "Break down the request into actionable steps.",
  )
  let nodes = [
    @dag.TaskNode::new(
      "prep",
      "Preparation",
      [],
      "planner",
      "List the inputs needed to proceed.",
    ),
    @dag.TaskNode::new(
      "ship",
      "Delivery",
      [@dag.ID::new("prep")],
      "planner",
      "Summarize the planned work in 3 bullets.",
    ),
  ]
  let workflow = @dag.Workflow::new([agent], nodes)
  let plan = @dag.render_workflow_plan(workflow)
  inspect(plan, content="Wave 1: prep\nWave 2: ship")
}
```

## Notes

- `render_workflow_plan` returns an error string on duplicate ids, missing deps, or cycles.
- `render_workflow_dag` assumes dependencies exist and does not validate the graph.
