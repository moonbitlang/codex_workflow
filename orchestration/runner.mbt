///|
priv struct Graph {
  nodes : Map[String, @dag.TaskNode]
  dependents : Map[String, Array[String]]
  remaining : Map[String, Int]
}

///|
/// Execute a workflow DAG using the configured agents.
pub async fn run_workflow(
  workflow : @dag.Workflow,
  codex : @codex.Codex,
  options : @dag.RunOptions,
) -> Map[String, String] {
  if workflow.nodes.is_empty() {
    return {}
  }
  let agent_map = build_agent_map(workflow)
  let graph = build_graph(workflow)
  let mut ready : Array[String] = []
  for node in workflow.nodes {
    if node.deps.is_empty() {
      ready.push(node.id)
    }
  }
  let results : Map[String, String] = {}
  let total = workflow.nodes.length()
  let mut completed = 0
  let mut wave = 0
  let concurrency = if options.concurrency < 1 {
    1
  } else {
    options.concurrency
  }
  while !ready.is_empty() {
    wave = wave + 1
    let ready_list = ready.join(", ")
    @stdio.stdout.write("Wave \{wave} ready: \{ready_list}\n")
    let wave_results : Array[(String, String)] = []
    @async.with_task_group(fn(task_group) {
      let semaphore = @semaphore.Semaphore::new(concurrency)
      for node_id in ready {
        let node = require_node(graph.nodes, node_id)
        let agent = require_agent(agent_map, node.agent)
        task_group.spawn_bg(allow_failure=true, fn() {
          semaphore.acquire()
          defer semaphore.release()
          @stdio.stdout.write(
            "info [\{node_id}] start - \{node.title} via \{agent.label()}\n",
          )
          let output = run_node(node, agent, results, codex, options) catch {
            e => {
              @stdio.stderr.write("error [\{node_id}] failed: \{e}\n")
              "ERROR: \{e}"
            }
          }
          wave_results.push((node_id, output))
          @stdio.stdout.write("info [\{node_id}] done\n")
        })
      }
    })
    let next_ready : Array[String] = []
    for node_result in wave_results {
      let (node_id, output) = node_result
      results[node_id] = output
      completed = completed + 1
      let children = graph.dependents.get(node_id).unwrap_or([])
      for child in children {
        let remaining = graph.remaining.get(child).unwrap_or(0) - 1
        graph.remaining[child] = remaining
        if remaining == 0 {
          next_ready.push(child)
        }
      }
    }
    ready = next_ready
  }
  if completed != total {
    @error.fail(
      "Workflow did not complete (\{completed}/\{total}). Check for cycles or missing deps.",
    )
  }
  results
}

///|
async fn run_node(
  node : @dag.TaskNode,
  agent : @dag.AgentSpec,
  results : Map[String, String],
  codex : @codex.Codex,
  options : @dag.RunOptions,
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
  response.final_response.trim(char_set=" \t\r\n").to_string()
}

///|
fn build_prompt(
  node : @dag.TaskNode,
  agent : @dag.AgentSpec,
  results : Map[String, String],
) -> String {
  let mut prompt =
    $|You are agent \{agent.name}.
    $|Role: \{agent.role}
    $|
    $|Task: \{node.prompt}
    $|Constraints:
    $|- Keep the response concise and actionable.
    $|- Do not modify files unless explicitly instructed.
  if node.deps.is_empty() {
    return prompt
  }
  prompt = prompt + "\n\nDependency outputs:\n"
  for dep in node.deps {
    let dep_output = results.get(dep).unwrap_or("<missing output>")
    prompt = prompt + "- " + dep + ":\n" + dep_output + "\n"
  }
  prompt
}

///|
fn build_agent_map(workflow : @dag.Workflow) -> Map[String, @dag.AgentSpec] raise {
  let agent_map : Map[String, @dag.AgentSpec] = {}
  for agent in workflow.agents {
    if agent_map.get(agent.name) is Some(_) {
      @error.fail("Duplicate agent name: \{agent.name}")
    }
    agent_map[agent.name] = agent
  }
  agent_map
}

///|
fn build_graph(workflow : @dag.Workflow) -> Graph raise {
  let nodes : Map[String, @dag.TaskNode] = {}
  let dependents : Map[String, Array[String]] = {}
  let remaining : Map[String, Int] = {}
  for node in workflow.nodes {
    if nodes.get(node.id) is Some(_) {
      @error.fail("Duplicate node id: \{node.id}")
    }
    nodes[node.id] = node
    remaining[node.id] = node.deps.length()
  }
  for node in workflow.nodes {
    for dep in node.deps {
      if nodes.get(dep) is None {
        @error.fail("Unknown dependency: \{dep} (required by \{node.id})")
      }
      let list = dependents.get(dep).unwrap_or([])
      list.push(node.id)
      dependents[dep] = list
    }
  }
  { nodes, dependents, remaining }
}

///|
fn require_node(
  nodes : Map[String, @dag.TaskNode],
  node_id : String,
) -> @dag.TaskNode raise {
  match nodes.get(node_id) {
    Some(node) => node
    None => @error.fail("Missing node for id: \{node_id}")
  }
}

///|
fn require_agent(
  agents : Map[String, @dag.AgentSpec],
  name : String,
) -> @dag.AgentSpec raise {
  match agents.get(name) {
    Some(agent) => agent
    None => @error.fail("Missing agent for name: \{name}")
  }
}
