///|
async fn main {
  let args = @args.parse(
    @sys.get_cli_args()[1:],
    flags=["help", "list", "dag"],
    options=["sample", "concurrency", "workdir", "model"],
    aliases={
      "h": "help",
      "l": "list",
      "g": "dag",
      "s": "sample",
      "c": "concurrency",
    },
  ) catch {
    e => {
      @stdio.stderr.write("Failed to parse arguments: \{e}\n")
      @stdio.stderr.write(help_message())
      return
    }
  }
  if args.flags.get("help") is Some(true) {
    @stdio.stdout.write(help_message())
    return
  }
  if args.flags.get("list") is Some(true) {
    let names = @workflow.sample_names().join(", ")
    @stdio.stdout.write("Samples: \{names}\n")
    return
  }
  let sample = args.options.get("sample").unwrap_or("kickoff")
  if args.flags.get("dag") is Some(true) {
    match @workflow.sample_workflow(sample) {
      Some(workflow) => {
        @stdio.stdout.write("DAG for '\{sample}':\n")
        @stdio.stdout.write(@workflow.render_workflow_dag(workflow))
        @stdio.stdout.write("\n")
        return
      }
      None => {
        let names = @workflow.sample_names().join(", ")
        @stdio.stderr.write("Unknown sample '\{sample}'. Available: \{names}\n")
        @stdio.stderr.write(help_message())
        return
      }
    }
  }
  let concurrency = match args.options.get("concurrency") {
    Some(text) =>
      @strconv.parse_int(text) catch {
        _ => {
          @stdio.stderr.write(
            "warning: invalid concurrency '\{text}', using 2\n",
          )
          2
        }
      }
    None => 2
  }
  let workdir = args.options.get("workdir").unwrap_or(".")
  let model = args.options.get("model")
  let options = @workflow.RunOptions::new(
    workdir,
    concurrency,
    default_sandbox=@codex.SandboxMode::ReadOnly,
    default_model?=model,
  )
  let codex = @codex.Codex::new()
  match @workflow.sample_workflow(sample) {
    Some(workflow) => {
      @stdio.stdout.write("Running sample '\{sample}'\n\n")
      @stdio.stdout.write(@workflow.describe_workflow(workflow))
      @stdio.stdout.write(
        "\nRunning with concurrency \{options.concurrency} in \{options.working_directory}\n\n",
      )
      let results = @workflow.run_workflow(workflow, codex, options) catch {
        e => {
          @stdio.stderr.write("Workflow failed: \{e}\n")
          return
        }
      }
      @stdio.stdout.write("\nResults:\n")
      for node in workflow.nodes {
        let output = results.get(node.id).unwrap_or("<missing output>")
        @stdio.stdout.write("\n=== \{node.id}: \{node.title} ===\n\{output}\n")
      }
    }
    None => {
      let names = @workflow.sample_names().join(", ")
      @stdio.stderr.write("Unknown sample '\{sample}'. Available: \{names}\n")
      @stdio.stderr.write(help_message())
    }
  }
}

///|
fn help_message() -> String {
  let message =
    #|Usage: moon run cmd/main -- [options]
    #|Run a sample multi-agent workflow.
    #|
    #|Options:
    #|  -s, --sample <name>       Sample workflow name (default: kickoff)
    #|  -c, --concurrency <num>   Max concurrent tasks (default: 2)
    #|  -g, --dag                 Print the workflow DAG as ASCII and exit
    #|  --workdir <path>          Working directory for agents (default: .)
    #|  --model <name>            Optional model override
    #|  -l, --list                List built-in samples
    #|  -h, --help                Show help
    #|
  message
}
