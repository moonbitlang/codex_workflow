///|
fn simple_workflow() -> @dag.Workflow {
  let agents = [
    @dag.AgentSpec::new("planner", "Plans the work."),
    @dag.AgentSpec::new("writer", "Writes the output."),
  ]
  let nodes = [
    @dag.TaskNode::new("step1", "First", [], "planner", "Plan the work."),
    @dag.TaskNode::new(
      "step2",
      "Second",
      [@dag.ID::new("step1")],
      "writer",
      "Write the output.",
    ),
  ]
  @dag.Workflow::new(agents, nodes)
}

///|
test "agent label" {
  let plain = @dag.AgentSpec::new("planner", "Plans")
  inspect(plain.label(), content="planner")
  let with_model = @dag.AgentSpec::new("planner", "Plans", model="o3")
  inspect(with_model.label(), content="planner (o3)")
}

///|
test "describe_workflow formats output" {
  let workflow = simple_workflow()
  let summary = @dag.describe_workflow(workflow)
  inspect(
    summary,
    content="Agents: planner, writer\nWorkflow nodes:\n- step1 [First] (agent: planner) <- (no deps)\n- step2 [Second] (agent: writer) <- step1\n",
  )
}

///|
test "render_workflow_plan returns waves" {
  let workflow = simple_workflow()
  let plan = workflow.render_plan()
  inspect(plan, content="Wave 1: step1\nWave 2: step2")
}

///|
test "render_workflow_plan detects duplicate ids" {
  let workflow = @dag.Workflow::new([@dag.AgentSpec::new("agent", "Role.")], [
    @dag.TaskNode::new("dup", "First", [], "agent", "first"),
    @dag.TaskNode::new("dup", "Second", [], "agent", "second"),
  ])
  inspect(workflow.render_plan(), content="ERROR: Duplicate node id: dup")
}

///|
test "render_workflow_plan detects missing deps" {
  let workflow = @dag.Workflow::new([@dag.AgentSpec::new("agent", "Role.")], [
    @dag.TaskNode::new("only", "Only", [@dag.ID::new("missing")], "agent", "do"),
  ])
  inspect(
    workflow.render_plan(),
    content="ERROR: Unknown dependency: missing (required by only)",
  )
}

///|
test "render_workflow_plan detects cycles" {
  let workflow = @dag.Workflow::new([@dag.AgentSpec::new("agent", "Role.")], [
    @dag.TaskNode::new("a", "A", [@dag.ID::new("b")], "agent", "a"),
    @dag.TaskNode::new("b", "B", [@dag.ID::new("a")], "agent", "b"),
  ])
  inspect(
    workflow.render_plan(),
    content="ERROR: Workflow did not complete (0/2). Check for cycles or missing deps.",
  )
}

///|
test "render_workflow_dag renders chain" {
  let workflow = @dag.Workflow::new([@dag.AgentSpec::new("agent", "Role.")], [
    @dag.TaskNode::new("alpha", "Alpha", [], "agent", "a"),
    @dag.TaskNode::new("beta", "Beta", [@dag.ID::new("alpha")], "agent", "b"),
  ])
  inspect(workflow.render_dag(), content="alpha\n  v\nbeta")
}

///|
test "render_workflow_dag empty" {
  let workflow = @dag.Workflow::new([], [])
  inspect(workflow.render_dag(), content="(no workflow nodes)")
}

// --- Graph building tests ---

///|
test "build_graph creates valid graph" {
  let workflow = @dag.Workflow::new([@dag.AgentSpec::new("agent", "Role.")], [
    @dag.TaskNode::new("a", "A", [], "agent", "a"),
    @dag.TaskNode::new("b", "B", [@dag.ID::new("a")], "agent", "b"),
    @dag.TaskNode::new(
      "c",
      "C",
      [@dag.ID::new("a"), @dag.ID::new("b")],
      "agent",
      "c",
    ),
  ])
  let graph = workflow.build_graph()
  // Check nodes are indexed
  inspect(graph.nodes.length(), content="3")
  inspect(graph.nodes.get(@dag.ID::new("a")) is Some(_), content="true")
  inspect(graph.nodes.get(@dag.ID::new("b")) is Some(_), content="true")
  inspect(graph.nodes.get(@dag.ID::new("c")) is Some(_), content="true")
  // Check dependents (reverse dependencies)
  inspect(
    graph.dependents.get_or_default(@dag.ID::new("a"), []).length(),
    content="2",
  ) // a -> b, c
  inspect(
    graph.dependents.get_or_default(@dag.ID::new("b"), []).length(),
    content="1",
  ) // b -> c
  inspect(
    graph.dependents.get_or_default(@dag.ID::new("c"), []).length(),
    content="0",
  ) // c has no dependents
  // Check remaining counts
  inspect(graph.remaining.get_or_default(@dag.ID::new("a"), -1), content="0") // a has 0 deps
  inspect(graph.remaining.get_or_default(@dag.ID::new("b"), -1), content="1") // b has 1 dep
  inspect(graph.remaining.get_or_default(@dag.ID::new("c"), -1), content="2") // c has 2 deps
}

///|
test "build_graph detects duplicate ids" {
  let workflow = @dag.Workflow::new([@dag.AgentSpec::new("agent", "Role.")], [
    @dag.TaskNode::new("dup", "First", [], "agent", "first"),
    @dag.TaskNode::new("dup", "Second", [], "agent", "second"),
  ])
  let mut error_msg = ""
  try {
    let _ = workflow.build_graph()
  } catch {
    e => error_msg = e.to_string()
  }
  inspect(error_msg.contains("Duplicate node id: dup"), content="true")
}

///|
test "build_graph detects missing deps" {
  let workflow = @dag.Workflow::new([@dag.AgentSpec::new("agent", "Role.")], [
    @dag.TaskNode::new("only", "Only", [@dag.ID::new("missing")], "agent", "do"),
  ])
  let mut error_msg = ""
  try {
    let _ = workflow.build_graph()
  } catch {
    e => error_msg = e.to_string()
  }
  inspect(error_msg.contains("Unknown dependency: missing"), content="true")
}

// --- Sample workflow tests ---

///|
fn has_agent(names : Array[@dag.AgentID], target : @dag.AgentID) -> Bool {
  for name in names {
    if name == target {
      return true
    }
  }
  false
}

///|
test "sample names stable" {
  debug_inspect(
    @dag.sample_names(),
    content="[\"kickoff\", \"review\", \"incremental_merge\"]",
  )
}

///|
test "sample workflow lookup" {
  let kickoff_found = match @dag.sample_workflow("kickoff") {
    Some(_) => true
    None => false
  }
  let unknown_found = match @dag.sample_workflow("unknown") {
    Some(_) => true
    None => false
  }
  inspect(kickoff_found, content="true")
  inspect(unknown_found, content="false")
}

///|
test "sample workflow count" {
  inspect(@dag.sample_workflows().length(), content="3")
}

///|
test "sample workflows reference declared agents" {
  let mut ok = true
  for item in @dag.sample_workflows() {
    let (_, workflow) = item
    let agent_names : Array[@dag.AgentID] = []
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
  match @dag.sample_workflow("kickoff") {
    Some(workflow) => kickoff_plan = workflow.render_plan()
    None => ()
  }
  inspect(
    kickoff_plan,
    content="Wave 1: repo_overview, requirements\nWave 2: workflow_plan\nWave 3: final_brief",
  )
  let mut review_plan = "<missing>"
  match @dag.sample_workflow("review") {
    Some(workflow) => review_plan = workflow.render_plan()
    None => ()
  }
  inspect(
    review_plan,
    content="Wave 1: readme_scan, cli_scan\nWave 2: review_summary",
  )
  let mut merge_plan = "<missing>"
  match @dag.sample_workflow("incremental_merge") {
    Some(workflow) => merge_plan = workflow.render_plan()
    None => ()
  }
  inspect(
    merge_plan,
    content="Wave 1: dispatch\nWave 2: job1, job2, job3, job4\nWave 3: merge_job1, merge_job2, merge_job3, merge_job4\nWave 4: merge_summary",
  )
}

// --- Additional visualization tests ---

///|
test "render_workflow_dag diamond pattern" {
  // Tests a diamond DAG: A -> B, A -> C, B -> D, C -> D
  let workflow = @dag.Workflow::new([@dag.AgentSpec::new("agent", "Role.")], [
    @dag.TaskNode::new("A", "Start", [], "agent", "start"),
    @dag.TaskNode::new("B", "Left", [@dag.ID::new("A")], "agent", "left"),
    @dag.TaskNode::new("C", "Right", [@dag.ID::new("A")], "agent", "right"),
    @dag.TaskNode::new(
      "D",
      "End",
      [@dag.ID::new("B"), @dag.ID::new("C")],
      "agent",
      "end",
    ),
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
  let workflow = @dag.Workflow::new([@dag.AgentSpec::new("agent", "Role.")], [
    @dag.TaskNode::new("root1", "First root", [], "agent", "r1"),
    @dag.TaskNode::new("root2", "Second root", [], "agent", "r2"),
    @dag.TaskNode::new("root3", "Third root", [], "agent", "r3"),
  ])
  let dag = workflow.render_dag()
  inspect(dag.contains("root1"), content="true")
  inspect(dag.contains("root2"), content="true")
  inspect(dag.contains("root3"), content="true")
}

///|
test "render_workflow_dag wide fan-in" {
  // Tests a node with many dependencies (fan-in)
  let workflow = @dag.Workflow::new([@dag.AgentSpec::new("agent", "Role.")], [
    @dag.TaskNode::new("a", "A", [], "agent", "a"),
    @dag.TaskNode::new("b", "B", [], "agent", "b"),
    @dag.TaskNode::new("c", "C", [], "agent", "c"),
    @dag.TaskNode::new(
      "merge",
      "Merge",
      [@dag.ID::new("a"), @dag.ID::new("b"), @dag.ID::new("c")],
      "agent",
      "merge",
    ),
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
  let workflow = @dag.Workflow::new([@dag.AgentSpec::new("agent", "Role.")], [
    @dag.TaskNode::new("root", "Root", [], "agent", "root"),
    @dag.TaskNode::new("child1", "C1", [@dag.ID::new("root")], "agent", "c1"),
    @dag.TaskNode::new("child2", "C2", [@dag.ID::new("root")], "agent", "c2"),
    @dag.TaskNode::new("child3", "C3", [@dag.ID::new("root")], "agent", "c3"),
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
  let workflow = @dag.Workflow::new([@dag.AgentSpec::new("agent", "Role.")], [
    @dag.TaskNode::new("n1", "N1", [], "agent", "1"),
    @dag.TaskNode::new("n2", "N2", [@dag.ID::new("n1")], "agent", "2"),
    @dag.TaskNode::new("n3", "N3", [@dag.ID::new("n2")], "agent", "3"),
    @dag.TaskNode::new("n4", "N4", [@dag.ID::new("n3")], "agent", "4"),
    @dag.TaskNode::new("n5", "N5", [@dag.ID::new("n4")], "agent", "5"),
  ])
  let dag = workflow.render_dag()
  let plan = workflow.render_plan()
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
  let workflow = @dag.Workflow::new([@dag.AgentSpec::new("agent", "Role.")], [
    @dag.TaskNode::new("p1", "P1", [], "agent", "1"),
    @dag.TaskNode::new("p2", "P2", [], "agent", "2"),
    @dag.TaskNode::new("p3", "P3", [], "agent", "3"),
    @dag.TaskNode::new("p4", "P4", [], "agent", "4"),
  ])
  let plan = workflow.render_plan()
  inspect(plan, content="Wave 1: p1, p2, p3, p4")
  inspect(workflow.render_dag(), content="p1    p2    p3    p4")
}

///|
test "render_workflow_dag single node" {
  let workflow = @dag.Workflow::new([@dag.AgentSpec::new("agent", "Role.")], [
    @dag.TaskNode::new("only", "Only", [], "agent", "only"),
  ])
  inspect(workflow.render_dag(), content="only")
}

///|
test "render_workflow_plan single node" {
  let workflow = @dag.Workflow::new([@dag.AgentSpec::new("agent", "Role.")], [
    @dag.TaskNode::new("only", "Only", [], "agent", "only"),
  ])
  inspect(workflow.render_plan(), content="Wave 1: only")
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
  let workflow = @dag.Workflow::new([@dag.AgentSpec::new("agent", "Role.")], [
    @dag.TaskNode::new("start", "Start", [], "agent", "start"),
    @dag.TaskNode::new("A", "Branch A", [@dag.ID::new("start")], "agent", "a"),
    @dag.TaskNode::new("B", "Branch B", [@dag.ID::new("start")], "agent", "b"),
    @dag.TaskNode::new("C", "Branch C", [@dag.ID::new("start")], "agent", "c"),
    @dag.TaskNode::new(
      "merge1",
      "Merge 1",
      [@dag.ID::new("A"), @dag.ID::new("B"), @dag.ID::new("C")],
      "agent",
      "merge1",
    ),
    @dag.TaskNode::new("D", "Branch D", [@dag.ID::new("merge1")], "agent", "d"),
    @dag.TaskNode::new("E", "Branch E", [@dag.ID::new("merge1")], "agent", "e"),
    @dag.TaskNode::new(
      "final",
      "Final",
      [@dag.ID::new("D"), @dag.ID::new("E")],
      "agent",
      "final",
    ),
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
  let plan = workflow.render_plan()
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
  let workflow = @dag.Workflow::new([@dag.AgentSpec::new("agent", "Role.")], [
    // Chain 1
    @dag.TaskNode::new("c1a", "Chain1 A", [], "agent", "c1a"),
    @dag.TaskNode::new("c1b", "Chain1 B", [@dag.ID::new("c1a")], "agent", "c1b"),
    @dag.TaskNode::new("c1c", "Chain1 C", [@dag.ID::new("c1b")], "agent", "c1c"),
    // Chain 2
    @dag.TaskNode::new("c2a", "Chain2 A", [], "agent", "c2a"),
    @dag.TaskNode::new("c2b", "Chain2 B", [@dag.ID::new("c2a")], "agent", "c2b"),
    @dag.TaskNode::new("c2c", "Chain2 C", [@dag.ID::new("c2b")], "agent", "c2c"),
    // Chain 3
    @dag.TaskNode::new("c3a", "Chain3 A", [], "agent", "c3a"),
    @dag.TaskNode::new("c3b", "Chain3 B", [@dag.ID::new("c3a")], "agent", "c3b"),
    @dag.TaskNode::new("c3c", "Chain3 C", [@dag.ID::new("c3b")], "agent", "c3c"),
    // Collector
    @dag.TaskNode::new(
      "collect",
      "Collector",
      [@dag.ID::new("c1c"), @dag.ID::new("c2c"), @dag.ID::new("c3c")],
      "agent",
      "collect",
    ),
  ])
  let dag = workflow.render_dag()
  // Verify all nodes present
  for
    name in [
      "c1a", "c1b", "c1c", "c2a", "c2b", "c2c", "c3a", "c3b", "c3c", "collect",
    ] {
    inspect(dag.contains(name), content="true")
  }
  inspect(
    dag,
    content=(
      #|c1a    c2a    c3a
      #| v      v      v
      #|c1b    c2b    c3b
      #| v      v      v
      #|c1c    c2c    c3c
      #| +------v------+
      #|     collect
    ),
  )
  // Verify execution plan
  let plan = workflow.render_plan()
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
  let workflow = @dag.Workflow::new([@dag.AgentSpec::new("agent", "Role.")], [
    @dag.TaskNode::new("A", "A", [], "agent", "a"),
    @dag.TaskNode::new("B", "B", [], "agent", "b"),
    // C depends on both A and B
    @dag.TaskNode::new(
      "C",
      "C",
      [@dag.ID::new("A"), @dag.ID::new("B")],
      "agent",
      "c",
    ),
    // D depends on both A and B
    @dag.TaskNode::new(
      "D",
      "D",
      [@dag.ID::new("A"), @dag.ID::new("B")],
      "agent",
      "d",
    ),
    @dag.TaskNode::new(
      "end",
      "End",
      [@dag.ID::new("C"), @dag.ID::new("D")],
      "agent",
      "end",
    ),
  ])
  let dag = workflow.render_dag()
  // Verify all nodes present
  inspect(dag.contains("A"), content="true")
  inspect(dag.contains("B"), content="true")
  inspect(dag.contains("C"), content="true")
  inspect(dag.contains("D"), content="true")
  inspect(dag.contains("end"), content="true")
  inspect(
    dag,
    content=(
      #|A    B
      #|+-v--+-v
      #|  C    D
      #|  +-v--+
      #|   end
    ),
  )
  // Verify execution plan
  let plan = workflow.render_plan()
  inspect(plan, content="Wave 1: A, B\nWave 2: C, D\nWave 3: end")
}

///|
/// Tests rendering of a workflow with long node names to verify spacing.
test "render_dag long node names" {
  let workflow = @dag.Workflow::new([@dag.AgentSpec::new("agent", "Role.")], [
    @dag.TaskNode::new("initialization", "Init", [], "agent", "init"),
    @dag.TaskNode::new(
      "processing",
      "Process",
      [@dag.ID::new("initialization")],
      "agent",
      "process",
    ),
    @dag.TaskNode::new(
      "finalization",
      "Final",
      [@dag.ID::new("processing")],
      "agent",
      "final",
    ),
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
