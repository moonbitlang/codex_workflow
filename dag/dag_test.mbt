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
  inspect(workflow.render_dag(), content="alpha\n  v\nbeta")
}

///|
test "render_workflow_dag empty" {
  let workflow = Workflow::new([], [])
  inspect(workflow.render_dag(), content="(no workflow nodes)")
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
  let dag = workflow.render_dag()
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
  let dag = workflow.render_dag()
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
  let dag = workflow.render_dag()
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
  let dag = workflow.render_dag()
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
  let dag = workflow.render_dag()
  let plan = render_workflow_plan(workflow)
  inspect(
    plan,
    content="Wave 1: n1\nWave 2: n2\nWave 3: n3\nWave 4: n4\nWave 5: n5",
  )
  inspect(
    dag,
    content=(
      #|n1
      #| v
      #|n2
      #| v
      #|n3
      #| v
      #|n4
      #| v
      #|n5
    ),
  )
  
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
  inspect(workflow.render_dag(), content="p1    p2    p3    p4")
}

///|
test "render_workflow_dag single node" {
  let workflow = Workflow::new([AgentSpec::new("agent", "Role.")], [
    TaskNode::new("only", "Only", [], "agent", "only"),
  ])
  inspect(workflow.render_dag(), content="only")
}

///|
test "render_workflow_plan single node" {
  let workflow = Workflow::new([AgentSpec::new("agent", "Role.")], [
    TaskNode::new("only", "Only", [], "agent", "only"),
  ])
  inspect(render_workflow_plan(workflow), content="Wave 1: only")
}

// --- Complex workflow visualization tests ---

///|
/// Tests a complex multi-layer DAG with branching and merging:
///
/// ```text
///        start
///       /  |  \
///      A   B   C
///       \  |  /
///       merge1
///       /    \
///      D      E
///       \    /
///       final
/// ```
test "render_dag complex multi-layer" {
  let workflow = Workflow::new([AgentSpec::new("agent", "Role.")], [
    TaskNode::new("start", "Start", [], "agent", "start"),
    TaskNode::new("A", "Branch A", [ID::new("start")], "agent", "a"),
    TaskNode::new("B", "Branch B", [ID::new("start")], "agent", "b"),
    TaskNode::new("C", "Branch C", [ID::new("start")], "agent", "c"),
    TaskNode::new("merge1", "Merge 1", [ID::new("A"), ID::new("B"), ID::new("C")], "agent", "merge1"),
    TaskNode::new("D", "Branch D", [ID::new("merge1")], "agent", "d"),
    TaskNode::new("E", "Branch E", [ID::new("merge1")], "agent", "e"),
    TaskNode::new("final", "Final", [ID::new("D"), ID::new("E")], "agent", "final"),
  ])
  let dag = workflow.render_dag()
  // Verify all nodes are present
  inspect(dag.contains("start"), content="true")
  inspect(dag.contains("A"), content="true")
  inspect(dag.contains("B"), content="true")
  inspect(dag.contains("C"), content="true")
  inspect(dag.contains("merge1"), content="true")
  inspect(dag.contains("D"), content="true")
  inspect(dag.contains("E"), content="true")
  inspect(dag.contains("final"), content="true")
  // Verify correct wave structure
  let plan = render_workflow_plan(workflow)
  inspect(
    plan,
    content="Wave 1: start\nWave 2: A, B, C\nWave 3: merge1\nWave 4: D, E\nWave 5: final",
  )
}

///|
/// Tests a wide parallel workflow with multiple independent chains:
///
/// ```text
/// chain1_a    chain2_a    chain3_a
///     |           |           |
/// chain1_b    chain2_b    chain3_b
///     |           |           |
/// chain1_c    chain2_c    chain3_c
///         \       |       /
///          \      |      /
///           collector
/// ```
test "render_dag parallel chains with collector" {
  let workflow = Workflow::new([AgentSpec::new("agent", "Role.")], [
    // Chain 1
    TaskNode::new("c1a", "Chain1 A", [], "agent", "c1a"),
    TaskNode::new("c1b", "Chain1 B", [ID::new("c1a")], "agent", "c1b"),
    TaskNode::new("c1c", "Chain1 C", [ID::new("c1b")], "agent", "c1c"),
    // Chain 2
    TaskNode::new("c2a", "Chain2 A", [], "agent", "c2a"),
    TaskNode::new("c2b", "Chain2 B", [ID::new("c2a")], "agent", "c2b"),
    TaskNode::new("c2c", "Chain2 C", [ID::new("c2b")], "agent", "c2c"),
    // Chain 3
    TaskNode::new("c3a", "Chain3 A", [], "agent", "c3a"),
    TaskNode::new("c3b", "Chain3 B", [ID::new("c3a")], "agent", "c3b"),
    TaskNode::new("c3c", "Chain3 C", [ID::new("c3b")], "agent", "c3c"),
    // Collector
    TaskNode::new("collect", "Collector", [ID::new("c1c"), ID::new("c2c"), ID::new("c3c")], "agent", "collect"),
  ])
  let dag = workflow.render_dag()
  // Verify all nodes present
  for name in ["c1a", "c1b", "c1c", "c2a", "c2b", "c2c", "c3a", "c3b", "c3c", "collect"] {
    inspect(dag.contains(name), content="true")
  }
  // Verify execution plan
  let plan = render_workflow_plan(workflow)
  inspect(
    plan,
    content="Wave 1: c1a, c2a, c3a\nWave 2: c1b, c2b, c3b\nWave 3: c1c, c2c, c3c\nWave 4: collect",
  )
}

///|
/// Tests a workflow with cross-dependencies (non-linear merge points):
///
/// ```text
///   A       B
///   |\     /|
///   | \   / |
///   |  \ /  |
///   |   X   |
///   |  / \  |
///   | /   \ |
///   C       D
///    \     /
///     \   /
///      end
/// ```
test "render_dag cross dependencies" {
  let workflow = Workflow::new([AgentSpec::new("agent", "Role.")], [
    TaskNode::new("A", "A", [], "agent", "a"),
    TaskNode::new("B", "B", [], "agent", "b"),
    // C depends on both A and B
    TaskNode::new("C", "C", [ID::new("A"), ID::new("B")], "agent", "c"),
    // D depends on both A and B
    TaskNode::new("D", "D", [ID::new("A"), ID::new("B")], "agent", "d"),
    TaskNode::new("end", "End", [ID::new("C"), ID::new("D")], "agent", "end"),
  ])
  let dag = workflow.render_dag()
  // Verify all nodes present
  inspect(dag.contains("A"), content="true")
  inspect(dag.contains("B"), content="true")
  inspect(dag.contains("C"), content="true")
  inspect(dag.contains("D"), content="true")
  inspect(dag.contains("end"), content="true")
  // Verify execution plan
  let plan = render_workflow_plan(workflow)
  inspect(plan, content="Wave 1: A, B\nWave 2: C, D\nWave 3: end")
}

///|
/// Tests rendering of a workflow with long node names to verify spacing.
test "render_dag long node names" {
  let workflow = Workflow::new([AgentSpec::new("agent", "Role.")], [
    TaskNode::new("initialization", "Init", [], "agent", "init"),
    TaskNode::new("processing", "Process", [ID::new("initialization")], "agent", "process"),
    TaskNode::new("finalization", "Final", [ID::new("processing")], "agent", "final"),
  ])
  let dag = workflow.render_dag()
  // Verify all nodes are present with their full names
  inspect(dag.contains("initialization"), content="true")
  inspect(dag.contains("processing"), content="true")
  inspect(dag.contains("finalization"), content="true")
  // The DAG should show a vertical chain
  inspect(
    dag,
    content=(
      #|initialization
      #|       v
      #|  processing
      #|       v
      #| finalization
    ),
  )
}
