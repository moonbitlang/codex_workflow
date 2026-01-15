///|
/// Return the list of built-in sample workflows.
///
/// The current samples are `"kickoff"` (planning + summary) and `"review"`
/// (lightweight repo review).
pub fn sample_workflows() -> Array[(String, Workflow)] {
  [("kickoff", kickoff_workflow()), ("review", review_workflow())]
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
      ["repo_overview", "requirements"],
      "planner",
      "Propose a minimal 3-step workflow DAG based on the inputs.",
    ),
    TaskNode::new(
      "final_brief",
      "Final brief",
      ["workflow_plan"],
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
      ["readme_scan", "cli_scan"],
      "scribe",
      "Summarize the review findings and suggest one next action.",
    ),
  ]
  Workflow::new(agents, nodes)
}
