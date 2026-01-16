///|
/// Options that control workflow execution.
///
/// `concurrency` caps how many nodes can run in parallel per wave.
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
/// Nodes run in dependency waves. Each wave runs with a concurrency cap from
/// `RunOptions`. Returns a map of node ids to their final response strings.
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
  let completed = for ready = ready, wave = 1, completed = 0; !ready.is_empty(); {
    let ready_list = ready.map(id => id.to_string()).join(", ")
    @stdio.stdout.write("Wave \{wave} ready: \{ready_list}\n")
    let wave_results : Array[(@dag.ID, String)] = []
    @async.with_task_group(fn(task_group) {
      let semaphore = @semaphore.Semaphore::new(concurrency)
      for node_id in ready {
        let node = require_node(graph.nodes, node_id)
        let agent = require_agent(agent_map, node.agent)
        task_group.spawn_bg(allow_failure=true, () => {
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
          wave_results.push((node_id, output))
          @stdio.stdout.write("info [\{node_id.to_string()}] done\n")
        })
      }
    })
    let next_ready : Array[@dag.ID] = []
    for node_result in wave_results {
      let (node_id, output) = node_result
      results[node_id] = output
      let children = graph.dependents.get_or_default(node_id, [])
      for child in children {
        let remaining = graph.remaining.get_or_default(child, 0) - 1
        graph.remaining[child] = remaining
        if remaining == 0 {
          next_ready.push(child)
        }
      }
    }
    continue next_ready, wave + 1, completed + wave_results.length()
  } else {
    completed
  }
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
