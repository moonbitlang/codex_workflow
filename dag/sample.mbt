///|
/// Return the list of built-in sample workflows.
///
/// The current samples are `"kickoff"` (planning + summary) and `"review"`
/// (lightweight repo review).
pub fn sample_workflows() -> Array[(String, Workflow)] {
  [
    ("kickoff", kickoff_workflow()),
    ("review", review_workflow()),
    ("incremental_merge", incremental_merge_workflow()),
  ]
}

///|
/// Lookup a sample workflow by name.
///
/// Returns `None` when the name is not recognized.
pub fn sample_workflow(name : String) -> Workflow? {
  for item in sample_workflows() {
    let (workflow_name, workflow) = item
    if workflow_name == name {
      return Some(workflow)
    }
  }
  None
}

///|
/// Return the sample names for help output.
///
/// The order matches `sample_workflows()`.
pub fn sample_names() -> Array[String] {
  let names : Array[String] = []
  for item in sample_workflows() {
    let (workflow_name, _) = item
    names.push(workflow_name)
  }
  names
}

///|
/// Build the "kickoff" planning workflow.
fn kickoff_workflow() -> Workflow {
  let agents = [
    AgentSpec::new(
      "planner",
      "Break down objectives into steps and risks.",
      sandbox_mode=@codex.SandboxMode::ReadOnly,
    ),
    AgentSpec::new(
      "researcher",
      "Inspect the repo and report facts only.",
      sandbox_mode=@codex.SandboxMode::ReadOnly,
    ),
    AgentSpec::new(
      "writer",
      "Synthesize a concise brief using upstream outputs.",
      sandbox_mode=@codex.SandboxMode::ReadOnly,
    ),
  ]
  let nodes = [
    TaskNode::new(
      "repo_overview",
      "Repository overview",
      [],
      "researcher",
      "List the top-level directories in this repository and summarize each in one short sentence.",
    ),
    TaskNode::new(
      "requirements",
      "Workflow constraints",
      [],
      "planner",
      "List 3 constraints or concerns for a multi-agent Codex workflow runner.",
    ),
    TaskNode::new(
      "workflow_plan",
      "Workflow plan",
      [ID::new("repo_overview"), ID::new("requirements")],
      "planner",
      "Propose a minimal 3-step workflow DAG based on the inputs.",
    ),
    TaskNode::new(
      "final_brief",
      "Final brief",
      [ID::new("workflow_plan")],
      "writer",
      "Summarize the workflow plan in 5 lines for a status update.",
    ),
  ]
  Workflow::new(agents, nodes)
}

///|
/// Build the "review" workflow used for quick repo scans.
fn review_workflow() -> Workflow {
  let agents = [
    AgentSpec::new(
      "reviewer",
      "Review text and suggest focused improvements.",
      sandbox_mode=@codex.SandboxMode::ReadOnly,
    ),
    AgentSpec::new(
      "scribe",
      "Aggregate findings and present a clear summary.",
      sandbox_mode=@codex.SandboxMode::ReadOnly,
    ),
  ]
  let nodes = [
    TaskNode::new(
      "readme_scan",
      "Scan README",
      [],
      "reviewer",
      "Read README.mbt.md and list 3 gaps or missing clarifications.",
    ),
    TaskNode::new(
      "cli_scan",
      "Scan CLI",
      [],
      "reviewer",
      "Read cmd/main/main.mbt and list 2 UX improvements for the CLI.",
    ),
    TaskNode::new(
      "review_summary",
      "Review summary",
      [ID::new("readme_scan"), ID::new("cli_scan")],
      "scribe",
      "Summarize the review findings and suggest one next action.",
    ),
  ]
  Workflow::new(agents, nodes)
}

///|
/// Build the "incremental_merge" workflow used to demo serialized merges.
fn incremental_merge_workflow() -> Workflow {
  let agents = [
    AgentSpec::new(
      "dispatcher",
      "Dispatch work and summarize final results.",
      sandbox_mode=@codex.SandboxMode::ReadOnly,
    ),
    AgentSpec::new(
      "worker",
      "Produce a small result for a single job.",
      sandbox_mode=@codex.SandboxMode::ReadOnly,
    ),
    AgentSpec::new(
      "merger",
      "Merge worker outputs one at a time.",
      sandbox_mode=@codex.SandboxMode::ReadOnly,
      max_concurrency=1,
    ),
  ]
  let nodes = [
    TaskNode::new(
      "dispatch",
      "Dispatch jobs",
      [],
      "dispatcher",
      "List 4 job labels as: job1, job2, job3, job4.",
    ),
    TaskNode::new(
      "job1",
      "Worker job1",
      [ID::new("dispatch")],
      "worker",
      "For job1, return two short sentences describing the result.",
    ),
    TaskNode::new(
      "job2",
      "Worker job2",
      [ID::new("dispatch")],
      "worker",
      "For job2, return two short sentences describing the result.",
    ),
    TaskNode::new(
      "job3",
      "Worker job3",
      [ID::new("dispatch")],
      "worker",
      "For job3, return two short sentences describing the result.",
    ),
    TaskNode::new(
      "job4",
      "Worker job4",
      [ID::new("dispatch")],
      "worker",
      "For job4, return two short sentences describing the result.",
    ),
    TaskNode::new(
      "merge_job1",
      "Merge job1",
      [ID::new("job1")],
      "merger",
      "Merge job1 into the running total. Output one sentence.",
    ),
    TaskNode::new(
      "merge_job2",
      "Merge job2",
      [ID::new("job2")],
      "merger",
      "Merge job2 into the running total. Output one sentence.",
    ),
    TaskNode::new(
      "merge_job3",
      "Merge job3",
      [ID::new("job3")],
      "merger",
      "Merge job3 into the running total. Output one sentence.",
    ),
    TaskNode::new(
      "merge_job4",
      "Merge job4",
      [ID::new("job4")],
      "merger",
      "Merge job4 into the running total. Output one sentence.",
    ),
    TaskNode::new(
      "merge_summary",
      "Merge summary",
      [
        ID::new("merge_job1"),
        ID::new("merge_job2"),
        ID::new("merge_job3"),
        ID::new("merge_job4"),
      ],
      "dispatcher",
      "Summarize the merged work in 3 short bullets.",
    ),
  ]
  Workflow::new(agents, nodes)
}
