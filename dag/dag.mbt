///|
/// A unique identifier for task nodes in a workflow DAG.
///
/// This newtype wrapper around `String` provides type safety when working
/// with node identifiers, ensuring IDs are not accidentally mixed with
/// other string values.
pub struct ID(String) derive(Eq, Hash, Show)

///|
/// Create a new ID from a string.
pub fn ID::new(s : String) -> ID {
  ID(s)
}

///|
/// Get the underlying string value of an ID.
pub fn ID::to_string(self : ID) -> String {
  self.0
}

///|
/// A single unit of work in a workflow DAG.
///
/// `id` must be unique within the workflow and is used in dependency lists.
/// `deps` lists prerequisite node ids that must finish before this node runs.
/// `agent` must match an `AgentSpec.name` in the workflow.
pub struct TaskNode {
  id : ID
  title : String
  deps : Array[ID]
  agent : AgentID
  prompt : String
}

///|
/// Construct a task node.
///
/// The arguments map directly to `TaskNode` fields; no validation is performed.
/// Accepts string arguments for convenience and wraps them in ID.
pub fn TaskNode::new(
  id : String,
  title : String,
  deps : Array[ID],
  agent : String,
  prompt : String,
) -> TaskNode {
  TaskNode::{ id: ID(id), title, deps, agent: AgentID(agent), prompt }
}

///|
/// A workflow definition containing agents and task nodes.
///
/// Ensure all `TaskNode.agent` values refer to a declared `AgentSpec`, and
/// dependencies form a DAG without cycles.
pub struct Workflow {
  agents : Array[AgentSpec]
  nodes : Array[TaskNode]
}

///|
/// Build a workflow definition from agent and node lists.
///
/// This constructor does not validate agent uniqueness or node dependencies.
pub fn Workflow::new(
  agents : Array[AgentSpec],
  nodes : Array[TaskNode],
) -> Workflow {
  Workflow::{ agents, nodes }
}

///|
/// Describe the workflow structure for humans.
///
/// Returns a multi-line summary including the agent list and node dependencies.
pub fn describe_workflow(workflow : Workflow) -> String {
  let agent_names = workflow.agents
    .map(fn(agent) { agent.name.to_string() })
    .join(", ")
  let mut output = "Agents: \{agent_names}\n"
  output = output + "Workflow nodes:\n"
  for node in workflow.nodes {
    let deps = if node.deps.is_empty() {
      "(no deps)"
    } else {
      node.deps.map(fn(d) { d.to_string() }).join(", ")
    }
    output = output +
      "- \{node.id.to_string()} [\{node.title}] (agent: \{node.agent.to_string()}) <- \{deps}\n"
  }
  output
}

///|
/// Render the workflow DAG as a top-down ASCII graph.
///
/// Uses node ids as labels. If there are no nodes, returns `"(no workflow nodes)"`.
/// Dependencies are assumed to exist; unknown ids may produce a degraded layout.
pub fn Workflow::render_dag(self : Workflow) -> String {
  if self.nodes.is_empty() {
    return "(no workflow nodes)"
  }
  let node_map : Map[ID, TaskNode] = {}
  let children : Map[ID, Array[ID]] = {}
  for node in self.nodes {
    node_map[node.id] = node
  }
  for node in self.nodes {
    for dep in node.deps {
      let list = children.get(dep).unwrap_or([])
      list.push(node.id)
      children[dep] = list
    }
  }
  let indegree : Map[ID, Int] = {}
  for node in self.nodes {
    indegree[node.id] = node.deps.length()
  }
  let queue : Array[ID] = []
  for node in self.nodes {
    if indegree.get(node.id).unwrap_or(0) == 0 {
      queue.push(node.id)
    }
  }
  let topo : Array[ID] = []
  for idx = 0; idx < queue.length(); {
    let node_id = queue[idx]
    topo.push(node_id)
    let kids = children.get(node_id).unwrap_or([])
    for child_id in kids {
      let next = indegree.get(child_id).unwrap_or(0) - 1
      indegree[child_id] = next
      if next == 0 {
        queue.push(child_id)
      }
    }
    continue idx + 1
  } else {

  }
  let level : Map[ID, Int] = {}
  let mut max_level = 0
  for node_id in topo {
    if node_map.get(node_id) is Some(node) {
      let mut best = 0
      for dep in node.deps {
        let candidate = level.get(dep).unwrap_or(0) + 1
        if candidate > best {
          best = candidate
        }
      }
      level[node_id] = best
      if best > max_level {
        max_level = best
      }
    }
  }
  for node in self.nodes {
    if level.get(node.id) is None {
      level[node.id] = 0
    }
    let current = level.get(node.id).unwrap_or(0)
    if current > max_level {
      max_level = current
    }
  }
  let nodes_by_level : Array[Array[ID]] = Array::makei(max_level + 1, fn(_) {
    let ids : Array[ID] = []
    ids
  })
  for node in self.nodes {
    let depth = level.get(node.id).unwrap_or(0)
    nodes_by_level[depth].push(node.id)
  }
  let label_len : Map[ID, Int] = {}
  for node in self.nodes {
    label_len[node.id] = node.id.to_string().length()
  }
  let positions : Map[ID, Int] = {}
  let anchors : Map[ID, Int] = {}
  let gap = 4
  for depth = 0; depth <= max_level; {
    let ids = nodes_by_level[depth]
    let mut prev_start = 0
    let mut prev_len = 0
    let mut first = true
    for node_id in ids {
      let len = label_len.get(node_id).unwrap_or(0)
      let mut parents : Array[ID] = []
      if node_map.get(node_id) is Some(node) {
        parents = node.deps
      }
      let mut base_anchor = 0
      if !parents.is_empty() {
        let mut sum = 0
        for parent in parents {
          sum = sum + anchors.get(parent).unwrap_or(0)
        }
        base_anchor = sum / parents.length()
      } else if !first {
        base_anchor = prev_start + prev_len + gap + len / 2
      } else {
        base_anchor = len / 2
      }
      let mut start = base_anchor - len / 2
      if start < 0 {
        start = 0
      }
      if !first {
        let min_start = prev_start + prev_len + gap
        if start < min_start {
          start = min_start
        }
      }
      positions[node_id] = start
      anchors[node_id] = start + len / 2
      prev_start = start
      prev_len = len
      first = false
    }
    continue depth + 1
  } else {

  }
  let mut width = 0
  for node in self.nodes {
    let start = positions.get(node.id).unwrap_or(0)
    let len = label_len.get(node.id).unwrap_or(0)
    let end = start + len
    if end > width {
      width = end
    }
  }
  if width < 1 {
    width = 1
  }
  let height = max_level * 2 + 1
  let canvas = Canvas::new(width, height)
  for node in self.nodes {
    if node.deps.is_empty() {
      continue
    }
    let depth = level.get(node.id).unwrap_or(0)
    if depth == 0 {
      continue
    }
    let row = depth * 2 - 1
    let child_anchor = anchors.get(node.id).unwrap_or(0)
    for parent in node.deps {
      let parent_anchor = anchors.get(parent).unwrap_or(child_anchor)
      draw_hline(canvas, row, parent_anchor, child_anchor)
      canvas.set(parent_anchor, row, '|')
    }
    canvas.set(child_anchor, row, 'v')
  }
  for node in self.nodes {
    let depth = level.get(node.id).unwrap_or(0)
    let row = depth * 2
    let start = positions.get(node.id).unwrap_or(0)
    draw_label(canvas, start, row, node.id.to_string())
  }
  let lines : Array[String] = []
  for row in canvas.rows {
    let line = String::from_array(row[:])
    lines.push(line.trim_end(chars=" ").to_string())
  }
  lines.join("\n")
}

///|
/// Render the workflow as topological execution waves.
///
/// Returns an error string when node ids are duplicated, dependencies are missing,
/// or the graph contains cycles. Concurrency limits are not considered here.
pub fn render_workflow_plan(workflow : Workflow) -> String {
  if workflow.nodes.is_empty() {
    return "(no workflow nodes)"
  }
  let node_map : Map[ID, TaskNode] = {}
  let dependents : Map[ID, Array[ID]] = {}
  let remaining : Map[ID, Int] = {}
  for node in workflow.nodes {
    if node_map.get(node.id) is Some(_) {
      return "ERROR: Duplicate node id: \{node.id.to_string()}"
    }
    node_map[node.id] = node
    remaining[node.id] = node.deps.length()
  }
  for node in workflow.nodes {
    for dep in node.deps {
      if node_map.get(dep) is None {
        return "ERROR: Unknown dependency: \{dep.to_string()} (required by \{node.id.to_string()})"
      }
      let list = dependents.get(dep).unwrap_or([])
      list.push(node.id)
      dependents[dep] = list
    }
  }
  let mut ready : Array[ID] = []
  for node in workflow.nodes {
    if remaining.get(node.id).unwrap_or(0) == 0 {
      ready.push(node.id)
    }
  }
  let lines : Array[String] = []
  let total = workflow.nodes.length()
  let mut completed = 0
  let mut wave_index = 1
  while !ready.is_empty() {
    let wave = ready
    let wave_label = wave.map(fn(id) { id.to_string() }).join(", ")
    lines.push("Wave \{wave_index}: \{wave_label}")
    wave_index = wave_index + 1
    let next_ready : Array[ID] = []
    for node_id in wave {
      completed = completed + 1
      let children = dependents.get(node_id).unwrap_or([])
      for child in children {
        let next = remaining.get(child).unwrap_or(0) - 1
        remaining[child] = next
        if next == 0 {
          next_ready.push(child)
        }
      }
    }
    ready = next_ready
  }
  if completed != total {
    return "ERROR: Workflow did not complete (\{completed}/\{total}). Check for cycles or missing deps."
  }
  lines.join("\n")
}

///|
/// Internal ASCII canvas for workflow rendering.
priv struct Canvas {
  width : Int
  height : Int
  rows : Array[Array[Char]]
}

///|
/// Allocate a canvas filled with spaces.
fn Canvas::new(width : Int, height : Int) -> Canvas {
  let rows = Array::makei(height, fn(_) { Array::make(width, ' ') })
  Canvas::{ width, height, rows }
}

///|
/// Set a character on the canvas, merging with existing edges when needed.
fn Canvas::set(canvas : Canvas, x : Int, y : Int, ch : Char) -> Unit {
  if x < 0 || y < 0 || x >= canvas.width || y >= canvas.height {
    return
  }
  let current = canvas.rows[y][x]
  let merged = merge_char(current, ch)
  canvas.rows[y][x] = merged
}

///|
/// Merge overlapping line characters to keep ASCII edges readable.
fn merge_char(existing : Char, incoming : Char) -> Char {
  if incoming == ' ' {
    return existing
  }
  if existing == ' ' {
    return incoming
  }
  if existing == 'v' || incoming == 'v' {
    return 'v'
  }
  if (existing == '|' && incoming == '-') ||
    (existing == '-' && incoming == '|') {
    return '+'
  }
  if existing == '+' || incoming == '+' {
    return '+'
  }
  if existing == '-' && incoming == '-' {
    return '-'
  }
  if existing == '|' && incoming == '|' {
    return '|'
  }
  existing
}

///|
/// Draw a horizontal line between two x positions.
fn draw_hline(canvas : Canvas, y : Int, x1 : Int, x2 : Int) -> Unit {
  let start = if x1 < x2 { x1 } else { x2 }
  let end = if x1 < x2 { x2 } else { x1 }
  for x = start; x <= end; {
    canvas.set(x, y, '-')
    continue x + 1
  } else {

  }
}

///|
/// Draw a label string at a fixed row and starting column.
fn draw_label(canvas : Canvas, x : Int, y : Int, label : String) -> Unit {
  if y < 0 || y >= canvas.height {
    return
  }
  for idx, ch in label.to_array() {
    let pos = x + idx
    if pos >= 0 && pos < canvas.width {
      canvas.rows[y][pos] = ch
    }
  }
}
