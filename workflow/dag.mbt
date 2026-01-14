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

///|
/// Render the workflow DAG as a top-down ASCII graph.
pub fn render_workflow_dag(workflow : Workflow) -> String {
  if workflow.nodes.is_empty() {
    return "(no workflow nodes)"
  }
  let node_map : Map[String, TaskNode] = {}
  let children : Map[String, Array[String]] = {}
  for node in workflow.nodes {
    node_map[node.id] = node
  }
  for node in workflow.nodes {
    for dep in node.deps {
      let list = children.get(dep).unwrap_or([])
      list.push(node.id)
      children[dep] = list
    }
  }
  let indegree : Map[String, Int] = {}
  for node in workflow.nodes {
    indegree[node.id] = node.deps.length()
  }
  let queue : Array[String] = []
  for node in workflow.nodes {
    if indegree.get(node.id).unwrap_or(0) == 0 {
      queue.push(node.id)
    }
  }
  let topo : Array[String] = []
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
  let level : Map[String, Int] = {}
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
  for node in workflow.nodes {
    if level.get(node.id) is None {
      level[node.id] = 0
    }
    let current = level.get(node.id).unwrap_or(0)
    if current > max_level {
      max_level = current
    }
  }
  let nodes_by_level : Array[Array[String]] =
    Array::makei(max_level + 1, fn(_) {
      let ids : Array[String] = []
      ids
    })
  for node in workflow.nodes {
    let depth = level.get(node.id).unwrap_or(0)
    nodes_by_level[depth].push(node.id)
  }
  let label_len : Map[String, Int] = {}
  for node in workflow.nodes {
    label_len[node.id] = node.id.length()
  }
  let positions : Map[String, Int] = {}
  let anchors : Map[String, Int] = {}
  let gap = 4
  for depth = 0; depth <= max_level; {
    let ids = nodes_by_level[depth]
    let mut prev_start = 0
    let mut prev_len = 0
    let mut first = true
    for node_id in ids {
      let len = label_len.get(node_id).unwrap_or(0)
      let mut parents : Array[String] = []
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
  for node in workflow.nodes {
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
  for node in workflow.nodes {
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
  for node in workflow.nodes {
    let depth = level.get(node.id).unwrap_or(0)
    let row = depth * 2
    let start = positions.get(node.id).unwrap_or(0)
    draw_label(canvas, start, row, node.id)
  }
  let lines : Array[String] = []
  for row in canvas.rows {
    let line = String::from_array(row[:])
    lines.push(line.trim_end(chars=" ").to_string())
  }
  lines.join("\n")
}

///|
priv struct Canvas {
  width : Int
  height : Int
  rows : Array[Array[Char]]
}

///|
fn Canvas::new(width : Int, height : Int) -> Canvas {
  let rows =
    Array::makei(height, fn(_) {
      Array::make(width, ' ')
    })
  Canvas::{ width, height, rows }
}

///|
fn Canvas::set(canvas : Canvas, x : Int, y : Int, ch : Char) -> Unit {
  if x < 0 || y < 0 || x >= canvas.width || y >= canvas.height {
    return
  }
  let current = canvas.rows[y][x]
  let merged = merge_char(current, ch)
  canvas.rows[y][x] = merged
}

///|
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
