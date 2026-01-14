///|
/// Return the list of built-in sample workflows.
pub fn sample_workflows() -> Array[(String, Workflow)] {
  [("kickoff", kickoff_workflow()), ("review", review_workflow())]
}

///|
/// Lookup a sample workflow by name.
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
pub fn sample_names() -> Array[String] {
  let names : Array[String] = []
  for item in sample_workflows() {
    let (workflow_name, _) = item
    names.push(workflow_name)
  }
  names
}

///|
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
    TaskNode::{
      id: "repo_overview",
      title: "Repository overview",
      deps: [],
      agent: "researcher",
      prompt: "List the top-level directories in this repository and summarize each in one short sentence.",
    },
    TaskNode::{
      id: "requirements",
      title: "Workflow constraints",
      deps: [],
      agent: "planner",
      prompt: "List 3 constraints or concerns for a multi-agent Codex workflow runner.",
    },
    TaskNode::{
      id: "workflow_plan",
      title: "Workflow plan",
      deps: ["repo_overview", "requirements"],
      agent: "planner",
      prompt: "Propose a minimal 3-step workflow DAG based on the inputs.",
    },
    TaskNode::{
      id: "final_brief",
      title: "Final brief",
      deps: ["workflow_plan"],
      agent: "writer",
      prompt: "Summarize the workflow plan in 5 lines for a status update.",
    },
  ]
  Workflow::{ agents, nodes }
}

///|
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
    TaskNode::{
      id: "readme_scan",
      title: "Scan README",
      deps: [],
      agent: "reviewer",
      prompt: "Read README.mbt.md and list 3 gaps or missing clarifications.",
    },
    TaskNode::{
      id: "cli_scan",
      title: "Scan CLI",
      deps: [],
      agent: "reviewer",
      prompt: "Read cmd/main/main.mbt and list 2 UX improvements for the CLI.",
    },
    TaskNode::{
      id: "review_summary",
      title: "Review summary",
      deps: ["readme_scan", "cli_scan"],
      agent: "scribe",
      prompt: "Summarize the review findings and suggest one next action.",
    },
  ]
  Workflow::{ agents, nodes }
}
