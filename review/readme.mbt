/// # README Review Module
///
/// This module prepares README improvement workflows for MoonBit packages.
/// It creates dedicated Git worktrees per package plus a merge worktree,
/// then builds a workflow DAG that ends with a merge step.

///|
/// Configuration options for the README review process.
pub struct ReadmeReviewOptions {
  priv repo_path : String
  priv worktrees_root : String
  priv base_ref : String
  priv model : String?
  priv merge_branch : String
}

///|
/// Represents a single README review task with its associated Git branch and worktree.
priv struct ReadmeReview {
  package_dir : String
  branch : String
  worktree_path : String
  agent_name : String
  task_id : String
}

///|
/// Result of the prepare phase, containing ready reviews and the workflow.
pub struct PreparedReadmeReview {
  priv reviews : Array[ReadmeReview]
  priv workflow : @dag.Workflow
  priv repo : String
  priv base_ref : String
  priv merge_worktree : String
  priv merge_branch : String
  priv options : ReadmeReviewOptions
}

///|
/// Returns the workflow DAG for execution or inspection.
pub fn PreparedReadmeReview::workflow(
  self : PreparedReadmeReview,
) -> @dag.Workflow {
  self.workflow
}

///|
/// Returns the normalized repository path.
pub fn PreparedReadmeReview::repo_path(self : PreparedReadmeReview) -> String {
  self.repo
}

///|
/// Returns the model override if specified.
pub fn PreparedReadmeReview::model(self : PreparedReadmeReview) -> String? {
  self.options.model
}

///|
/// Returns the base ref for merge context.
pub fn PreparedReadmeReview::base_ref(self : PreparedReadmeReview) -> String {
  self.base_ref
}

///|
/// Returns the package directories included in the review.
pub fn PreparedReadmeReview::package_dirs(
  self : PreparedReadmeReview,
) -> Array[String] {
  let output : Array[String] = []
  for review in self.reviews {
    output.push(review.package_dir)
  }
  output
}

///|
/// Returns the merge worktree path.
pub fn PreparedReadmeReview::merge_worktree(
  self : PreparedReadmeReview,
) -> String {
  self.merge_worktree
}

///|
/// Returns the merge branch name.
pub fn PreparedReadmeReview::merge_branch(
  self : PreparedReadmeReview,
) -> String {
  self.merge_branch
}

///|
/// Creates default options with sensible defaults.
pub fn ReadmeReviewOptions::new(
  repo_path : String,
  base_ref? : String = "origin/main",
  worktrees_root? : String = "",
  model? : String? = None,
  merge_branch? : String = "readme/merge",
) -> ReadmeReviewOptions {
  { repo_path, worktrees_root, base_ref, model, merge_branch }
}

///|
/// Prepares README reviews without executing them.
/// Use this for preview/dry-run to inspect the workflow DAG before running.
///
/// Returns `None` if the repository is invalid or no packages are found.
pub async fn prepare_readme_reviews(
  options : ReadmeReviewOptions,
) -> PreparedReadmeReview? {
  let repo = normalize_path(expand_home(options.repo_path))
  if !is_git_repo(repo) {
    return None
  }
  let base = options.base_ref
  let worktrees = if options.worktrees_root.is_empty() {
    default_worktrees_root(repo)
  } else {
    normalize_path(expand_home(options.worktrees_root))
  }
  let packages = discover_packages(repo)
  if packages.is_empty() {
    @stdio.stdout.write("No MoonBit packages found in \{repo}\n")
    return None
  }
  ensure_directory(worktrees)
  let reviews = build_readme_reviews(packages, worktrees)
  let ready : Array[ReadmeReview] = []
  for review in reviews {
    if ensure_readme_worktree(repo, review, base) {
      ready.push(review)
    }
  }
  if ready.is_empty() {
    @stdio.stderr.write("No worktrees available to review.\n")
    return None
  }
  let merge_worktree = join_path(worktrees, "readme-merge")
  let merge_branch = options.merge_branch
  if !ensure_worktree_path(
      repo,
      merge_worktree,
      merge_branch,
      base,
      "merge",
    ) {
    @stdio.stderr.write("Failed to create merge worktree.\n")
    return None
  }
  let workflow = build_readme_workflow(
    ready,
    merge_worktree,
    merge_branch,
    options.model,
    repo,
    base,
  )
  Some(PreparedReadmeReview::{
    reviews: ready,
    workflow,
    repo,
    base_ref: base,
    merge_worktree,
    merge_branch,
    options,
  })
}

///|
/// Creates ReadmeReview entries for each discovered package.
fn build_readme_reviews(
  packages : Array[String],
  worktrees_root : String,
) -> Array[ReadmeReview] {
  let output : Array[ReadmeReview] = []
  for package_dir in packages {
    let slug = slugify_package(package_dir)
    let branch = "readme/\{slug}"
    let worktree_path = join_path(worktrees_root, slug)
    let agent_name = "readme_\{slug}"
    let task_id = "readme_\{slug}"
    output.push(ReadmeReview::{
      package_dir,
      branch,
      worktree_path,
      agent_name,
      task_id,
    })
  }
  output
}

///|
/// Creates a Git worktree for the README review, or reuses an existing one.
async fn ensure_readme_worktree(
  repo : String,
  review : ReadmeReview,
  base_ref : String,
) -> Bool {
  ensure_worktree_path(
    repo,
    review.worktree_path,
    review.branch,
    base_ref,
    review.package_dir,
  )
}

///|
/// Creates a Git worktree for the requested branch and path.
async fn ensure_worktree_path(
  repo : String,
  worktree_path : String,
  branch : String,
  base_ref : String,
  label : String,
) -> Bool {
  if @fs.path_exists(worktree_path) {
    return true
  }
  let args = [
    "-C",
    repo,
    "worktree",
    "add",
    "-b",
    branch,
    worktree_path,
    base_ref,
  ]
  let (code, output) = run_command_output("git", args)
  if code == 0 {
    return true
  }
  let fallback = [
    "-C",
    repo,
    "worktree",
    "add",
    worktree_path,
    branch,
  ]
  let (fallback_code, _) = run_command_output("git", fallback)
  if fallback_code == 0 {
    return true
  }
  @stdio.stderr.write(
    "Failed to create worktree for \{label}: \{output}\n",
  )
  false
}

///|
/// Builds a workflow DAG with one agent and task per package plus a merge task.
fn build_readme_workflow(
  reviews : Array[ReadmeReview],
  merge_worktree : String,
  merge_branch : String,
  model : String?,
  repo : String,
  base_ref : String,
) -> @dag.Workflow {
  let agents : Array[@dag.AgentSpec] = []
  let nodes : Array[@dag.TaskNode] = []
  let deps : Array[@dag.ID] = []
  for review in reviews {
    let role =
      "Review and improve README docs for package \{review.package_dir}."
    let agent = match model {
      Some(value) =>
        @dag.AgentSpec::new(
          review.agent_name,
          role,
          model=value,
          sandbox_mode=@codex.SandboxMode::WorkspaceWrite,
          working_directory=review.worktree_path,
        )
      None =>
        @dag.AgentSpec::new(
          review.agent_name,
          role,
          sandbox_mode=@codex.SandboxMode::WorkspaceWrite,
          working_directory=review.worktree_path,
        )
    }
    agents.push(agent)
    nodes.push(
      @dag.TaskNode::new(
        review.task_id,
        "Update README for \{review.package_dir}",
        [],
        review.agent_name,
        build_readme_prompt(review.package_dir, repo, base_ref),
      ),
    )
    deps.push(@dag.ID::new(review.task_id))
  }
  let merge_agent = match model {
    Some(value) =>
      @dag.AgentSpec::new(
        "readme_merger",
        "Merge README updates and ensure moon check passes.",
        model=value,
        sandbox_mode=@codex.SandboxMode::WorkspaceWrite,
        working_directory=merge_worktree,
        max_concurrency=1,
      )
    None =>
      @dag.AgentSpec::new(
        "readme_merger",
        "Merge README updates and ensure moon check passes.",
        sandbox_mode=@codex.SandboxMode::WorkspaceWrite,
        working_directory=merge_worktree,
        max_concurrency=1,
      )
  }
  agents.push(merge_agent)
  nodes.push(
    @dag.TaskNode::new(
      "merge_readmes",
      "Merge README updates",
      deps,
      "readme_merger",
      build_merge_prompt(reviews, merge_branch, merge_worktree, repo, base_ref),
    ),
  )
  @dag.Workflow::new(agents, nodes)
}

///|
/// Generates the AI agent prompt for updating a specific package README.
fn build_readme_prompt(
  package_dir : String,
  repo : String,
  base_ref : String,
) -> String {
  let pkg = if package_dir == "." { "." } else { package_dir }
  let label = package_label(package_dir)
  let (readme_mbt, readme_md) = readme_paths(package_dir)
  let lines : Array[String] = []
  lines.push(
    "You are improving the README for the MoonBit package at \"\{pkg}\" in repo \"\{repo}\".",
  )
  lines.push("")
  lines.push("Rules:")
  lines.push("- Only touch README files inside \"\{pkg}\".")
  lines.push(
    "- Prefer editing \"\{readme_mbt}\" if it exists; keep \"\{readme_md}\" in sync (symlink or identical content).",
  )
  lines.push(
    "- If no README exists, create \"\{readme_mbt}\" and \"\{readme_md}\" (symlink or copy).",
  )
  lines.push(
    "- Keep examples accurate; use `mbt nocheck` unless the snippet is verified.",
  )
  lines.push("- Do not edit source code files.")
  lines.push(
    "- Commit changes with message \"readme(\{label}): improve README\".",
  )
  lines.push(
    "- If no changes are needed, leave the worktree clean and note that in Summary.",
  )
  lines.push("")
  lines.push("Return a concise summary in this format:")
  lines.push("Title: readme(\{label}): improve README")
  lines.push("Summary:")
  lines.push("- bullet 1")
  lines.push("Tests:")
  lines.push("- Not run (docs-only)")
  lines.push("")
  lines.push("Base ref for context: \{base_ref}")
  lines.join("\n")
}

///|
/// Generates the AI agent prompt for merging README branches.
fn build_merge_prompt(
  reviews : Array[ReadmeReview],
  merge_branch : String,
  merge_worktree : String,
  repo : String,
  base_ref : String,
) -> String {
  let lines : Array[String] = []
  lines.push("You are the merger agent for README updates.")
  lines.push("Repo: \{repo}")
  lines.push("Worktree: \{merge_worktree}")
  lines.push("Target branch: \{merge_branch}")
  lines.push("Base ref: \{base_ref}")
  lines.push("")
  lines.push("Branches to merge (in order):")
  for review in reviews {
    lines.push("- \{review.branch} (package: \{review.package_dir})")
  }
  lines.push("")
  lines.push("Rules:")
  lines.push("- Ensure the worktree is clean and on the target branch.")
  lines.push("- Merge each branch with `git merge --no-ff --no-edit <branch>`.")
  lines.push("- Resolve conflicts by keeping the best README content per package.")
  lines.push("- After all merges, run `moon check` from repo root.")
  lines.push("- Fix README issues if `moon check` fails, then re-run.")
  lines.push("")
  lines.push("Return a concise summary in this format:")
  lines.push("Summary:")
  lines.push("- bullet 1")
  lines.push("Tests:")
  lines.push("- moon check")
  lines.join("\n")
}

///|
/// Returns a stable label for human-facing messages.
fn package_label(package_dir : String) -> String {
  if package_dir == "." {
    "root"
  } else {
    package_dir
  }
}

///|
/// Returns README.mbt.md and README.md paths for a package.
fn readme_paths(package_dir : String) -> (String, String) {
  let prefix = if package_dir == "." { "" } else { package_dir + "/" }
  (prefix + "README.mbt.md", prefix + "README.md")
}
