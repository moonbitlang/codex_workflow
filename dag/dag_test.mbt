///|
fn simple_workflow() -> Workflow {
  let agents = [
    AgentSpec::new("planner", "Plans the work."),
    AgentSpec::new("writer", "Writes the output."),
  ]
  let nodes = [
    TaskNode::new("step1", "First", [], "planner", "Plan the work."),
    TaskNode::new("step2", "Second", [ID::new("step1")], "writer", "Write the output."),
  ]
  Workflow::new(agents, nodes)
}

///|
test "agent label" {
  let plain = AgentSpec::new("planner", "Plans")
  inspect(plain.label(), content="planner")
  let with_model = AgentSpec::new("planner", "Plans", model="o3")
  inspect(with_model.label(), content="planner (o3)")
}

///|
test "describe_workflow formats output" {
  let workflow = simple_workflow()
  let summary = describe_workflow(workflow)
  inspect(
    summary,
    content="Agents: planner, writer\nWorkflow nodes:\n- step1 [First] (agent: planner) <- (no deps)\n- step2 [Second] (agent: writer) <- step1\n",
  )
}

///|
test "render_workflow_plan returns waves" {
  let workflow = simple_workflow()
  let plan = render_workflow_plan(workflow)
  inspect(plan, content="Wave 1: step1\nWave 2: step2")
}

///|
test "render_workflow_plan detects duplicate ids" {
  let workflow = Workflow::new([AgentSpec::new("agent", "Role.")], [
    TaskNode::new("dup", "First", [], "agent", "first"),
    TaskNode::new("dup", "Second", [], "agent", "second"),
  ])
  inspect(
    render_workflow_plan(workflow),
    content="ERROR: Duplicate node id: dup",
  )
}

///|
test "render_workflow_plan detects missing deps" {
  let workflow = Workflow::new([AgentSpec::new("agent", "Role.")], [
    TaskNode::new("only", "Only", [ID::new("missing")], "agent", "do"),
  ])
  inspect(
    render_workflow_plan(workflow),
    content="ERROR: Unknown dependency: missing (required by only)",
  )
}

///|
test "render_workflow_plan detects cycles" {
  let workflow = Workflow::new([AgentSpec::new("agent", "Role.")], [
    TaskNode::new("a", "A", [ID::new("b")], "agent", "a"),
    TaskNode::new("b", "B", [ID::new("a")], "agent", "b"),
  ])
  inspect(
    render_workflow_plan(workflow),
    content="ERROR: Workflow did not complete (0/2). Check for cycles or missing deps.",
  )
}

///|
test "render_workflow_dag renders chain" {
  let workflow = Workflow::new([AgentSpec::new("agent", "Role.")], [
    TaskNode::new("alpha", "Alpha", [], "agent", "a"),
    TaskNode::new("beta", "Beta", [ID::new("alpha")], "agent", "b"),
  ])
  inspect(render_workflow_dag(workflow), content="alpha\n  v\nbeta")
}

///|
test "render_workflow_dag empty" {
  let workflow = Workflow::new([], [])
  inspect(render_workflow_dag(workflow), content="(no workflow nodes)")
}

// --- Sample workflow tests ---

///|
fn has_agent(names : Array[AgentID], target : AgentID) -> Bool {
  for name in names {
    if name == target {
      return true
    }
  }
  false
}

///|
test "sample names stable" {
  inspect(sample_names(), content="[\"kickoff\", \"review\"]")
}

///|
test "sample workflow lookup" {
  let kickoff_found = match sample_workflow("kickoff") {
    Some(_) => true
    None => false
  }
  let unknown_found = match sample_workflow("unknown") {
    Some(_) => true
    None => false
  }
  inspect(kickoff_found, content="true")
  inspect(unknown_found, content="false")
}

///|
test "sample workflow count" {
  inspect(sample_workflows().length(), content="2")
}

///|
test "sample workflows reference declared agents" {
  let mut ok = true
  for item in sample_workflows() {
    let (_, workflow) = item
    let agent_names : Array[AgentID] = []
    for agent in workflow.agents {
      agent_names.push(agent.name)
    }
    for node in workflow.nodes {
      if !has_agent(agent_names, node.agent) {
        ok = false
      }
    }
  }
  inspect(ok, content="true")
}

///|
test "sample workflow plans" {
  let mut kickoff_plan = "<missing>"
  match sample_workflow("kickoff") {
    Some(workflow) => kickoff_plan = render_workflow_plan(workflow)
    None => ()
  }
  inspect(
    kickoff_plan,
    content="Wave 1: repo_overview, requirements\nWave 2: workflow_plan\nWave 3: final_brief",
  )
  let mut review_plan = "<missing>"
  match sample_workflow("review") {
    Some(workflow) => review_plan = render_workflow_plan(workflow)
    None => ()
  }
  inspect(
    review_plan,
    content="Wave 1: readme_scan, cli_scan\nWave 2: review_summary",
  )
}

// --- Additional visualization tests ---

///|
test "render_workflow_dag diamond pattern" {
  // Tests a diamond DAG: A -> B, A -> C, B -> D, C -> D
  let workflow = Workflow::new([AgentSpec::new("agent", "Role.")], [
    TaskNode::new("A", "Start", [], "agent", "start"),
    TaskNode::new("B", "Left", [ID::new("A")], "agent", "left"),
    TaskNode::new("C", "Right", [ID::new("A")], "agent", "right"),
    TaskNode::new("D", "End", [ID::new("B"), ID::new("C")], "agent", "end"),
  ])
  let dag = render_workflow_dag(workflow)
  // Verify it contains the expected node labels
  inspect(dag.contains("A"), content="true")
  inspect(dag.contains("B"), content="true")
  inspect(dag.contains("C"), content="true")
  inspect(dag.contains("D"), content="true")
}

///|
test "render_workflow_dag parallel roots" {
  // Tests multiple independent root nodes
  let workflow = Workflow::new([AgentSpec::new("agent", "Role.")], [
    TaskNode::new("root1", "First root", [], "agent", "r1"),
    TaskNode::new("root2", "Second root", [], "agent", "r2"),
    TaskNode::new("root3", "Third root", [], "agent", "r3"),
  ])
  let dag = render_workflow_dag(workflow)
  inspect(dag.contains("root1"), content="true")
  inspect(dag.contains("root2"), content="true")
  inspect(dag.contains("root3"), content="true")
}

///|
test "render_workflow_dag wide fan-in" {
  // Tests a node with many dependencies (fan-in)
  let workflow = Workflow::new([AgentSpec::new("agent", "Role.")], [
    TaskNode::new("a", "A", [], "agent", "a"),
    TaskNode::new("b", "B", [], "agent", "b"),
    TaskNode::new("c", "C", [], "agent", "c"),
    TaskNode::new("merge", "Merge", [ID::new("a"), ID::new("b"), ID::new("c")], "agent", "merge"),
  ])
  let dag = render_workflow_dag(workflow)
  inspect(dag.contains("merge"), content="true")
  inspect(dag.contains("a"), content="true")
  inspect(dag.contains("b"), content="true")
  inspect(dag.contains("c"), content="true")
}

///|
test "render_workflow_dag fan-out" {
  // Tests a node with many dependents (fan-out)
  let workflow = Workflow::new([AgentSpec::new("agent", "Role.")], [
    TaskNode::new("root", "Root", [], "agent", "root"),
    TaskNode::new("child1", "C1", [ID::new("root")], "agent", "c1"),
    TaskNode::new("child2", "C2", [ID::new("root")], "agent", "c2"),
    TaskNode::new("child3", "C3", [ID::new("root")], "agent", "c3"),
  ])
  let dag = render_workflow_dag(workflow)
  inspect(dag.contains("root"), content="true")
  inspect(dag.contains("child1"), content="true")
  inspect(dag.contains("child2"), content="true")
  inspect(dag.contains("child3"), content="true")
}

///|
test "render_workflow_dag deep chain" {
  // Tests a long linear chain
  let workflow = Workflow::new([AgentSpec::new("agent", "Role.")], [
    TaskNode::new("n1", "N1", [], "agent", "1"),
    TaskNode::new("n2", "N2", [ID::new("n1")], "agent", "2"),
    TaskNode::new("n3", "N3", [ID::new("n2")], "agent", "3"),
    TaskNode::new("n4", "N4", [ID::new("n3")], "agent", "4"),
    TaskNode::new("n5", "N5", [ID::new("n4")], "agent", "5"),
  ])
  let dag = render_workflow_dag(workflow)
  let plan = render_workflow_plan(workflow)
  inspect(
    plan,
    content="Wave 1: n1\nWave 2: n2\nWave 3: n3\nWave 4: n4\nWave 5: n5",
  )
  inspect(dag.contains("n1"), content="true")
  inspect(dag.contains("n5"), content="true")
}

///|
test "render_workflow_plan parallel wide" {
  // Tests many parallel nodes in single wave
  let workflow = Workflow::new([AgentSpec::new("agent", "Role.")], [
    TaskNode::new("p1", "P1", [], "agent", "1"),
    TaskNode::new("p2", "P2", [], "agent", "2"),
    TaskNode::new("p3", "P3", [], "agent", "3"),
    TaskNode::new("p4", "P4", [], "agent", "4"),
  ])
  let plan = render_workflow_plan(workflow)
  inspect(plan, content="Wave 1: p1, p2, p3, p4")
}

///|
test "render_workflow_dag single node" {
  let workflow = Workflow::new([AgentSpec::new("agent", "Role.")], [
    TaskNode::new("only", "Only", [], "agent", "only"),
  ])
  inspect(render_workflow_dag(workflow), content="only")
}

///|
test "render_workflow_plan single node" {
  let workflow = Workflow::new([AgentSpec::new("agent", "Role.")], [
    TaskNode::new("only", "Only", [], "agent", "only"),
  ])
  inspect(render_workflow_plan(workflow), content="Wave 1: only")
}
