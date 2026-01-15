///|
/// A unique identifier for agents in a workflow.
///
/// This newtype wrapper around `String` provides type safety when working
/// with agent names, ensuring they are not accidentally mixed with other strings.
pub struct AgentID(String) derive(Eq, Hash, Show)

///|
/// Create a new AgentID from a string.
pub fn AgentID::new(s : String) -> AgentID {
  AgentID(s)
}

///|
/// Get the underlying string value of an AgentID.
pub fn AgentID::to_string(self : AgentID) -> String {
  self.0
}

///|
/// Configuration for a named agent used to execute workflow tasks.
///
/// `name` must be unique within a workflow and is referenced by `TaskNode.agent`.
/// `role` is included in prompts to describe the agent's responsibilities.
/// Optional fields override values from `RunOptions` when they are present.
pub struct AgentSpec {
  name : AgentID
  role : String
  model : String?
  sandbox_mode : @codex.SandboxMode?
  working_directory : String?
}

///|
/// Build an agent profile with optional overrides.
///
/// Omitted optional parameters default to `None`, which means `RunOptions`
/// provides the effective model, sandbox mode, and working directory.
pub fn AgentSpec::new(
  name : String,
  role : String,
  model? : String,
  sandbox_mode? : @codex.SandboxMode,
  working_directory? : String,
) -> AgentSpec {
  AgentSpec::{
    name: AgentID(name),
    role,
    model,
    sandbox_mode,
    working_directory,
  }
}

///|
/// Render a short label for logs.
///
/// When a model override is set, the label becomes `"<name> (<model>)"`.
pub fn AgentSpec::label(agent : AgentSpec) -> String {
  if agent.model is Some(model) {
    "\{agent.name.to_string()} (\{model})"
  } else {
    agent.name.to_string()
  }
}
