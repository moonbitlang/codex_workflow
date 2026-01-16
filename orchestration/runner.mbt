///|
/// Options that control workflow execution.
///
/// `concurrency` caps how many nodes can run in parallel.
/// `working_directory` is the default repo root for all agents.
/// `default_sandbox` and `default_model` apply when agents do not override them.
pub struct RunOptions {
  concurrency : Int
  working_directory : String
  default_sandbox : @codex.SandboxMode
  default_model : String?
}

///|
/// Create run options with defaults for sandbox and model.
///
/// `default_sandbox` defaults to `ReadOnly` when not provided.
pub fn RunOptions::new(
  working_directory : String,
  concurrency : Int,
  default_sandbox? : @codex.SandboxMode = @codex.SandboxMode::ReadOnly,
  default_model? : String,
) -> RunOptions {
  RunOptions::{ concurrency, working_directory, default_sandbox, default_model }
}

///|
/// Execute a workflow DAG using the configured agents.
///
/// Nodes run as soon as dependencies complete, using the concurrency cap from
/// `RunOptions` plus any per-agent caps from `AgentSpec`. Returns a map of node
/// ids to their final response strings.
///
/// Raises on duplicate agent names, duplicate node ids, missing dependencies,
/// or if the graph cannot complete (cycles). Per-node execution failures are
/// captured as `"ERROR: ..."` outputs and logged to stderr.
pub async fn run_workflow(
  workflow : @dag.Workflow,
  codex : @codex.Codex,
  options : RunOptions,
) -> Map[@dag.ID, String] {
  if workflow.nodes.is_empty() {
    return {}
  }
  let agent_map = build_agent_map(workflow)
  let agent_semaphores = build_agent_semaphores(workflow)
  let graph = workflow.build_graph()
  let ready : Array[@dag.ID] = workflow.nodes.filter_map(node => if node.deps.is_empty() {
    Some(node.id)
  } else {
    None
  })
  let results : Map[@dag.ID, String] = {}
  let total = workflow.nodes.length()
  let concurrency = if options.concurrency < 1 {
    1
  } else {
    options.concurrency
  }
  let done_queue : @aqueue.Queue[(@dag.ID, String)] = @aqueue.Queue::new(kind=Unbounded)
  let mut completed = 0
  let mut in_flight = 0
  @async.with_task_group(fn(task_group) {
    let semaphore = @semaphore.Semaphore::new(concurrency)
    let spawn_node = fn(
      node_id : @dag.ID,
      node : @dag.TaskNode,
      agent : @dag.AgentSpec,
    ) -> Unit {
      in_flight = in_flight + 1
      task_group.spawn_bg(allow_failure=true, () => {
        let agent_limit = agent_semaphores.get(node.agent)
        match agent_limit {
          Some(agent_semaphore) => {
            agent_semaphore.acquire()
            defer agent_semaphore.release()
          }
          None => ()
        }
        semaphore.acquire()
        defer semaphore.release()
        @stdio.stdout.write(
          "info [\{node_id.to_string()}] start - \{node.title} via \{agent.label()}\n",
        )
        let output = run_node(node, agent, results, codex, options) catch {
          e => {
            @stdio.stderr.write(
              "error [\{node_id.to_string()}] failed: \{e}\n",
            )
            "ERROR: \{e}"
          }
        }
        guard done_queue.try_put((node_id, output)) else {
          @stdio.stderr.write(
            "error [\{node_id.to_string()}] completion queue full\n",
          )
          abort("Completion queue is full")
        }
        @stdio.stdout.write("info [\{node_id.to_string()}] done\n")
      })
    }
    for node_id in ready {
      let node = require_node(graph.nodes, node_id)
      let agent = require_agent(agent_map, node.agent)
      spawn_node(node_id, node, agent)
    }
    while completed < total {
      if in_flight == 0 {
        break
      }
      let (node_id, output) = done_queue.get()
      in_flight = in_flight - 1
      completed = completed + 1
      results[node_id] = output
      let children = graph.dependents.get_or_default(node_id, [])
      for child in children {
        let remaining = graph.remaining.get_or_default(child, 0) - 1
        graph.remaining[child] = remaining
        if remaining == 0 {
          let node = require_node(graph.nodes, child)
          let agent = require_agent(agent_map, node.agent)
          spawn_node(child, node, agent)
        }
      }
    }
  })
  if completed != total {
    @error.fail(
      "Workflow did not complete (\{completed}/\{total}). Check for cycles or missing deps.",
    )
  }
  results
}

///|
/// Execute a single node using agent overrides and dependency outputs.
async fn run_node(
  node : @dag.TaskNode,
  agent : @dag.AgentSpec,
  results : Map[@dag.ID, String],
  codex : @codex.Codex,
  options : RunOptions,
) -> String {
  let work_dir = agent.working_directory.unwrap_or(options.working_directory)
  let sandbox_mode = agent.sandbox_mode.unwrap_or(options.default_sandbox)
  let model = match agent.model {
    Some(value) => Some(value)
    None => options.default_model
  }
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      working_directory=work_dir,
      model?,
      sandbox_mode~,
    ),
  )
  let prompt = build_prompt(node, agent, results)
  let response = thread.run(prompt)
  response.final_response.trim().to_string()
}

///|
/// Build the prompt text for a node, including dependency outputs when present.
fn build_prompt(
  node : @dag.TaskNode,
  agent : @dag.AgentSpec,
  results : Map[@dag.ID, String],
) -> String {
  let mut prompt =
    $|You are agent \{agent.name.to_string()}.
    $|Role: \{agent.role}
    $|
    $|Task: \{node.prompt}
    $|Constraints:
    $|- Keep the response concise and actionable.
    $|- Do not modify files unless explicitly instructed.
  if node.deps.is_empty() {
    return prompt
  }
  prompt += "\n\nDependency outputs:\n"
  for dep in node.deps {
    let dep_output = results.get(dep).unwrap_or("<missing output>")
    prompt += "- \{dep}:\{dep_output}\n"
  }
  prompt
}

///|
/// Index agents by name and fail fast on duplicates.
fn build_agent_map(
  workflow : @dag.Workflow,
) -> Map[@dag.AgentID, @dag.AgentSpec] raise {
  let agent_map : Map[@dag.AgentID, @dag.AgentSpec] = {}
  for agent in workflow.agents {
    if agent_map.get(agent.name) is Some(_) {
      @error.fail("Duplicate agent name: \{agent.name.to_string()}")
    }
    agent_map[agent.name] = agent
  }
  agent_map
}

///|
/// Build per-agent semaphores from concurrency limits.
fn build_agent_semaphores(
  workflow : @dag.Workflow,
) -> Map[@dag.AgentID, @semaphore.Semaphore] {
  let semaphores : Map[@dag.AgentID, @semaphore.Semaphore] = {}
  for agent in workflow.agents {
    match agent.max_concurrency {
      Some(limit) => {
        let cap = if limit < 1 { 1 } else { limit }
        semaphores[agent.name] = @semaphore.Semaphore::new(cap)
      }
      None => ()
    }
  }
  semaphores
}

///|
/// Retrieve a node by id or raise a descriptive error.
fn require_node(
  nodes : Map[@dag.ID, @dag.TaskNode],
  node_id : @dag.ID,
) -> @dag.TaskNode raise {
  match nodes.get(node_id) {
    Some(node) => node
    None => @error.fail("Missing node for id: \{node_id.to_string()}")
  }
}

///|
/// Retrieve an agent by name or raise a descriptive error.
fn require_agent(
  agents : Map[@dag.AgentID, @dag.AgentSpec],
  name : @dag.AgentID,
) -> @dag.AgentSpec raise {
  match agents.get(name) {
    Some(agent) => agent
    None => @error.fail("Missing agent for name: \{name.to_string()}")
  }
}
