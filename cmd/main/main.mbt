///|
async fn main {
  let args = @args.parse(
    @sys.get_cli_args()[1:],
    flags=[
      "help", "list", "dag", "plan", "review-packages", "draft", "no-draft", "cleanup",
    ],
    options=[
      "sample", "concurrency", "workdir", "model", "repo", "worktrees", "base",
    ],
    aliases={
      "h": "help",
      "l": "list",
      "g": "dag",
      "p": "plan",
      "r": "review-packages",
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
    let names = @dag.sample_names().join(", ")
    @stdio.stdout.write("Samples: \{names}\n")
    return
  }
  let wants_review = args.flags.get("review-packages") is Some(true)
  let model = args.options.get("model")
  if wants_review {
    let repo = args.options.get("repo").unwrap_or(".")
    let worktrees = args.options.get("worktrees").unwrap_or("")
    let base = args.options.get("base").unwrap_or("origin/main")
    let concurrency = parse_concurrency(args.options.get("concurrency"), 4)
    let draft = !(args.flags.get("no-draft") is Some(true))
    let cleanup = args.flags.get("cleanup") is Some(true)
    let options = @review.PackageReviewOptions::new(
      repo,
      base_ref=base,
      worktrees_root=worktrees,
      model~,
      draft~,
      cleanup~,
    )
    let wants_dag = args.flags.get("dag") is Some(true)
    let wants_plan = args.flags.get("plan") is Some(true)
    match @review.prepare_package_reviews(options) {
      Some(prepared) => {
        if wants_plan {
          @stdio.stdout.write("Plan for package reviews:\n")
          @stdio.stdout.write(@dag.render_workflow_plan(prepared.workflow()))
          @stdio.stdout.write("\n")
        }
        if wants_dag {
          @stdio.stdout.write("DAG for package reviews:\n")
          @stdio.stdout.write(prepared.workflow().render_dag())
          @stdio.stdout.write("\n")
        }
        if wants_dag || wants_plan {
          return
        }
        // Run the workflow
        let codex = @codex.Codex::new()
        let run_options = @orchestration.RunOptions::new(
          prepared.repo_path(),
          concurrency,
          default_sandbox=@codex.SandboxMode::WorkspaceWrite,
          default_model?=prepared.model(),
        )
        @stdio.stdout.write(
          "Reviewing packages with concurrency \{concurrency}...\n",
        )
        let results = @orchestration.run_workflow(
          prepared.workflow(),
          codex,
          run_options,
        ) catch {
          e => {
            @stdio.stderr.write("Package review failed: \{e}\n")
            return
          }
        }
        // Process results (commit, push, create PRs)
        @review.process_review_results(prepared, results)
      }
      None => @stdio.stderr.write("Failed to prepare package reviews.\n")
    }
    return
  }
  let sample = args.options.get("sample").unwrap_or("kickoff")
  let wants_dag = args.flags.get("dag") is Some(true)
  let wants_plan = args.flags.get("plan") is Some(true)
  if wants_dag || wants_plan {
    match @dag.sample_workflow(sample) {
      Some(workflow) => {
        if wants_plan {
          @stdio.stdout.write("Plan for '\{sample}':\n")
          @stdio.stdout.write(@dag.render_workflow_plan(workflow))
          @stdio.stdout.write("\n")
        }
        if wants_dag {
          @stdio.stdout.write("DAG for '\{sample}':\n")
          @stdio.stdout.write(workflow.render_dag())
          @stdio.stdout.write("\n")
        }
        return
      }
      None => {
        let names = @dag.sample_names().join(", ")
        @stdio.stderr.write("Unknown sample '\{sample}'. Available: \{names}\n")
        @stdio.stderr.write(help_message())
        return
      }
    }
  }
  let concurrency = parse_concurrency(args.options.get("concurrency"), 2)
  let workdir = args.options.get("workdir").unwrap_or(".")
  let options = @orchestration.RunOptions::new(
    workdir,
    concurrency,
    default_sandbox=@codex.SandboxMode::ReadOnly,
    default_model?=model,
  )
  let codex = @codex.Codex::new()
  match @dag.sample_workflow(sample) {
    Some(workflow) => {
      @stdio.stdout.write("Running sample '\{sample}'\n\n")
      @stdio.stdout.write(@dag.describe_workflow(workflow))
      @stdio.stdout.write(
        "\nRunning with concurrency \{options.concurrency} in \{options.working_directory}\n\n",
      )
      let results = @orchestration.run_workflow(workflow, codex, options) catch {
        e => {
          @stdio.stderr.write("Workflow failed: \{e}\n")
          return
        }
      }
      @stdio.stdout.write("\nResults:\n")
      for node in workflow.nodes {
        let output = results.get(node.id).unwrap_or("<missing output>")
        @stdio.stdout.write(
          "\n=== \{node.id.to_string()}: \{node.title} ===\n\{output}\n",
        )
      }
    }
    None => {
      let names = @dag.sample_names().join(", ")
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
    #|  -p, --plan                Print topological execution waves and exit
    #|  -r, --review-packages     Review MoonBit packages in parallel
    #|  --workdir <path>          Working directory for agents (default: .)
    #|  --model <name>            Optional model override
    #|  --repo <path>             Repo path for package reviews (default: .)
    #|  --worktrees <path>        Worktree root (default: <repo>.worktrees)
    #|  --base <ref>              Base ref for reviews (default: origin/main)
    #|  --draft                   Create draft PRs (default for reviews)
    #|  --no-draft                Create ready-for-review PRs
    #|  --cleanup                 Remove worktrees with no changes
    #|  -l, --list                List built-in samples
    #|  -h, --help                Show help
    #|
  message
}

///|
async fn parse_concurrency(value : String?, default_value : Int) -> Int {
  match value {
    Some(text) =>
      @strconv.parse_int(text) catch {
        _ => {
          @stdio.stderr.write(
            "warning: invalid concurrency '\{text}', using \{default_value}\n",
          )
          default_value
        }
      }
    None => default_value
  }
}
