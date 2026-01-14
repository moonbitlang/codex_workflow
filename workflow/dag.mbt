///|
/// A single task in a workflow DAG.
pub struct TaskNode {
  id : String
  title : String
  deps : Array[String]
  agent : String
  prompt : String
}

///|
/// A workflow definition with agents and nodes.
pub struct Workflow {
  agents : Array[AgentSpec]
  nodes : Array[TaskNode]
}

///|
/// Options for running a workflow.
pub struct RunOptions {
  concurrency : Int
  working_directory : String
  default_sandbox : @codex.SandboxMode
  default_model : String?
}

///|
pub fn RunOptions::new(
  working_directory : String,
  concurrency : Int,
  default_sandbox? : @codex.SandboxMode = @codex.SandboxMode::ReadOnly,
  default_model? : String,
) -> RunOptions {
  RunOptions::{ concurrency, working_directory, default_sandbox, default_model }
}

///|
/// Describe the workflow structure for humans.
pub fn describe_workflow(workflow : Workflow) -> String {
  let agent_names = workflow.agents.map(fn(agent) { agent.name }).join(", ")
  let mut output = "Agents: \{agent_names}\n"
  output = output + "Workflow nodes:\n"
  for node in workflow.nodes {
    let deps = if node.deps.is_empty() {
      "(no deps)"
    } else {
      node.deps.join(", ")
    }
    output = output +
      "- \{node.id} [\{node.title}] (agent: \{node.agent}) <- \{deps}\n"
  }
  output
}
