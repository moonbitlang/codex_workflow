fn simple_workflow() -> Workflow {
  let agents = [
    AgentSpec::new("planner", "Plans the work."),
    AgentSpec::new("writer", "Writes the output."),
  ]
  let nodes = [
    TaskNode::new(
      "step1",
      "First",
      [],
      "planner",
      "Plan the work.",
    ),
    TaskNode::new(
      "step2",
      "Second",
      ["step1"],
      "writer",
      "Write the output.",
    ),
  ]
  Workflow::new(agents, nodes)
}

test "agent label" {
  let plain = AgentSpec::new("planner", "Plans")
  inspect(plain.label(), content="planner")
  let with_model = AgentSpec::new("planner", "Plans", model="o3")
  inspect(with_model.label(), content="planner (o3)")
}

test "describe_workflow formats output" {
  let workflow = simple_workflow()
  let summary = describe_workflow(workflow)
  inspect(
    summary,
    content="Agents: planner, writer\nWorkflow nodes:\n- step1 [First] (agent: planner) <- (no deps)\n- step2 [Second] (agent: writer) <- step1\n",
  )
}

test "render_workflow_plan returns waves" {
  let workflow = simple_workflow()
  let plan = render_workflow_plan(workflow)
  inspect(plan, content="Wave 1: step1\nWave 2: step2")
}

test "render_workflow_plan detects duplicate ids" {
  let workflow = Workflow::new(
    [AgentSpec::new("agent", "Role.")],
    [
      TaskNode::new("dup", "First", [], "agent", "first"),
      TaskNode::new("dup", "Second", [], "agent", "second"),
    ],
  )
  inspect(render_workflow_plan(workflow), content="ERROR: Duplicate node id: dup")
}

test "render_workflow_plan detects missing deps" {
  let workflow = Workflow::new(
    [AgentSpec::new("agent", "Role.")],
    [TaskNode::new("only", "Only", ["missing"], "agent", "do")],
  )
  inspect(
    render_workflow_plan(workflow),
    content="ERROR: Unknown dependency: missing (required by only)",
  )
}

test "render_workflow_plan detects cycles" {
  let workflow = Workflow::new(
    [AgentSpec::new("agent", "Role.")],
    [
      TaskNode::new("a", "A", ["b"], "agent", "a"),
      TaskNode::new("b", "B", ["a"], "agent", "b"),
    ],
  )
  inspect(
    render_workflow_plan(workflow),
    content="ERROR: Workflow did not complete (0/2). Check for cycles or missing deps.",
  )
}

test "render_workflow_dag renders chain" {
  let workflow = Workflow::new(
    [AgentSpec::new("agent", "Role.")],
    [
      TaskNode::new("alpha", "Alpha", [], "agent", "a"),
      TaskNode::new("beta", "Beta", ["alpha"], "agent", "b"),
    ],
  )
  inspect(render_workflow_dag(workflow), content="alpha\n  v\nbeta")
}

test "render_workflow_dag empty" {
  let workflow = Workflow::new([], [])
  inspect(render_workflow_dag(workflow), content="(no workflow nodes)")
}
