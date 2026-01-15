fn has_name(names : Array[String], target : String) -> Bool {
  for name in names {
    if name == target {
      return true
    }
  }
  false
}

test "sample names stable" {
  inspect(sample_names(), content="[\"kickoff\", \"review\"]")
}

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

test "sample workflow count" {
  inspect(sample_workflows().length(), content="2")
}

test "sample workflows reference declared agents" {
  let mut ok = true
  for item in sample_workflows() {
    let (_, workflow) = item
    let agent_names : Array[String] = []
    for agent in workflow.agents {
      agent_names.push(agent.name)
    }
    for node in workflow.nodes {
      if !has_name(agent_names, node.agent) {
        ok = false
      }
    }
  }
  inspect(ok, content="true")
}

test "sample workflow plans" {
  let mut kickoff_plan = "<missing>"
  match sample_workflow("kickoff") {
    Some(workflow) => kickoff_plan = @dag.render_workflow_plan(workflow)
    None => ()
  }
  inspect(
    kickoff_plan,
    content="Wave 1: repo_overview, requirements\nWave 2: workflow_plan\nWave 3: final_brief",
  )

  let mut review_plan = "<missing>"
  match sample_workflow("review") {
    Some(workflow) => review_plan = @dag.render_workflow_plan(workflow)
    None => ()
  }
  inspect(
    review_plan,
    content="Wave 1: readme_scan, cli_scan\nWave 2: review_summary",
  )
}
