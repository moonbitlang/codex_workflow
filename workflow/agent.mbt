///|
/// Agent configuration used to run a task node.
pub struct AgentSpec {
  name : String
  role : String
  model : String?
  sandbox_mode : @codex.SandboxMode?
  working_directory : String?
}

///|
/// Construct a new agent profile.
pub fn AgentSpec::new(
  name : String,
  role : String,
  model? : String,
  sandbox_mode? : @codex.SandboxMode,
  working_directory? : String,
) -> AgentSpec {
  AgentSpec::{ name, role, model, sandbox_mode, working_directory }
}

///|
/// Render a short label for logs.
pub fn AgentSpec::label(agent : AgentSpec) -> String {
  if agent.model is Some(model) {
    "\{agent.name} (\{model})"
  } else {
    agent.name
  }
}
