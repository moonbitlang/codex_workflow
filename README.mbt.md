# codex_workflow

Multi-agent workflow runner for Codex, built in MoonBit.

## Overview

This library provides a DAG-based workflow execution engine for orchestrating multiple Codex agents. Each workflow consists of **agents** (with specific roles and configurations) and **task nodes** (units of work with dependencies). The runner executes tasks in waves, respecting dependencies and concurrency limits.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Workflow                             │
│  ┌─────────────┐    ┌──────────────────────────────────┐   │
│  │   Agents    │    │           Task Nodes             │   │
│  │  - planner  │    │  repo_overview ─┐                │   │
│  │  - researcher│   │  requirements ──┼─> workflow_plan │   │
│  │  - writer   │    │                 └─> final_brief  │   │
│  └─────────────┘    └──────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                        Runner                               │
│  Wave 1: [repo_overview, requirements]  (parallel)         │
│  Wave 2: [workflow_plan]                                    │
│  Wave 3: [final_brief]                                      │
└─────────────────────────────────────────────────────────────┘
```

## Project Layout

- `workflow/` — Library package containing core types and runner
  - `agent.mbt` — `AgentSpec` type for agent configuration
  - `dag.mbt` — `TaskNode`, `Workflow`, `RunOptions` types and DAG utilities
  - `runner.mbt` — Async workflow execution engine
  - `sample.mbt` — Built-in sample workflows
- `cmd/main/` — CLI entrypoint

## Core Concepts

### AgentSpec

An agent configuration that defines how a task should be executed:

```moonbit
pub struct AgentSpec {
  name : String              // Unique identifier
  role : String              // Role description for the agent prompt
  model : String?            // Optional model override (e.g., "o3")
  sandbox_mode : @codex.SandboxMode?  // Optional sandbox mode override
  working_directory : String?         // Optional working directory override
}
```

### TaskNode

A single unit of work in the workflow DAG:

```moonbit
pub struct TaskNode {
  id : String           // Unique identifier for this task
  title : String        // Human-readable title
  deps : Array[String]  // IDs of tasks this depends on
  agent : String        // Name of the agent to execute this task
  prompt : String       // The prompt to send to the agent
}
```

### Workflow

A complete workflow definition combining agents and tasks:

```moonbit
pub struct Workflow {
  agents : Array[AgentSpec]  // Available agents
  nodes : Array[TaskNode]    // Tasks to execute
}
```

### RunOptions

Configuration for workflow execution:

```moonbit
pub struct RunOptions {
  concurrency : Int                    // Max parallel tasks per wave
  working_directory : String           // Default working directory
  default_sandbox : @codex.SandboxMode // Default sandbox mode
  default_model : String?              // Default model for all agents
}
```

## API Reference

### Workflow Execution

```moonbit
/// Execute a workflow DAG using the configured agents.
/// Returns a map of task IDs to their output strings.
pub async fn run_workflow(
  workflow : Workflow,
  codex : @codex.Codex,
  options : RunOptions,
) -> Map[String, String]
```

### Workflow Utilities

```moonbit
/// Describe the workflow structure for humans.
pub fn describe_workflow(workflow : Workflow) -> String

/// Render the workflow DAG as a top-down ASCII graph.
pub fn render_workflow_dag(workflow : Workflow) -> String
```

### Sample Workflows

```moonbit
/// Return the list of built-in sample workflows.
pub fn sample_workflows() -> Array[(String, Workflow)]

/// Lookup a sample workflow by name.
pub fn sample_workflow(name : String) -> Workflow?

/// Return the sample names for help output.
pub fn sample_names() -> Array[String]
```

## CLI Usage

```bash
# Show help
moon run cmd/main -- --help

# List available sample workflows
moon run cmd/main -- --list

# Run the default "kickoff" sample
moon run cmd/main -- --sample kickoff

# View the DAG structure without running
moon run cmd/main -- --sample kickoff --dag

# Run with custom concurrency
moon run cmd/main -- --sample kickoff --concurrency 4

# Run in a specific directory
moon run cmd/main -- --sample review --workdir /path/to/repo

# Use a specific model
moon run cmd/main -- --sample kickoff --model o3
```

### CLI Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--sample <name>` | `-s` | Sample workflow name | `kickoff` |
| `--concurrency <num>` | `-c` | Max concurrent tasks | `2` |
| `--dag` | `-g` | Print DAG as ASCII and exit | — |
| `--workdir <path>` | — | Working directory for agents | `.` |
| `--model <name>` | — | Model override for all agents | — |
| `--list` | `-l` | List built-in samples | — |
| `--help` | `-h` | Show help | — |

## Built-in Samples

### kickoff

A 4-task workflow demonstrating parallel execution and dependencies:

```
repo_overview    requirements
      |               |
      └───────┬───────┘
              ▼
        workflow_plan
              |
              ▼
         final_brief
```

**Agents:** planner, researcher, writer

### review

A 3-task workflow for reviewing project documentation:

```
readme_scan    cli_scan
      |            |
      └─────┬──────┘
            ▼
      review_summary
```

**Agents:** reviewer, scribe

## Creating Custom Workflows

```moonbit
let my_workflow = Workflow::{
  agents: [
    AgentSpec::new(
      "analyzer",
      "Analyze code and identify patterns.",
      sandbox_mode=@codex.SandboxMode::ReadOnly,
    ),
    AgentSpec::new(
      "reporter",
      "Summarize findings in a structured format.",
      sandbox_mode=@codex.SandboxMode::ReadOnly,
    ),
  ],
  nodes: [
    TaskNode::{
      id: "scan_code",
      title: "Scan source code",
      deps: [],
      agent: "analyzer",
      prompt: "List all public functions in the src/ directory.",
    },
    TaskNode::{
      id: "generate_report",
      title: "Generate report",
      deps: ["scan_code"],
      agent: "reporter",
      prompt: "Create a summary of the code analysis.",
    },
  ],
}
```

## Execution Model

1. **Graph Construction**: The runner builds an internal dependency graph from the workflow definition, validating that all dependencies exist and detecting duplicate IDs.

2. **Wave Execution**: Tasks are executed in waves. Each wave contains all tasks whose dependencies have been satisfied. Within a wave, tasks run concurrently up to the configured concurrency limit.

3. **Result Propagation**: Each task receives the outputs of its dependencies in its prompt, enabling context flow through the DAG.

4. **Error Handling**: If a task fails, the error is captured and the workflow continues. The runner reports if not all tasks completed successfully.

## License

Apache-2.0
