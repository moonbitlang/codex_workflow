/// # Package Review Module
///
/// This module provides automated, parallel code review functionality for MoonBit packages
/// using AI-powered agents (Codex). It creates isolated Git worktrees for each package,
/// runs formatting/linting/testing, applies minimal fixes, and opens draft Pull Requests.
///
/// ## Architecture
///
/// The review process follows these steps:
/// 1. **Discovery**: Scans the repository for MoonBit packages (`moon.pkg` or `moon.pkg.json`)
/// 2. **Worktree Setup**: Creates isolated Git worktrees for each package (one branch per package)
/// 3. **Parallel Review**: Spawns AI agents to review each package concurrently
/// 4. **PR Creation**: Commits changes, pushes branches, and opens draft PRs via `gh` CLI
///
/// ## Prerequisites
///
/// - Git repository with MoonBit packages
/// - `gh` CLI installed and authenticated (for PR creation)
/// - `rg` (ripgrep) or `find` available for package discovery
/// - MoonBit toolchain (`moon` command)
///
/// ## Usage
///
/// ```moonbit
/// @review.run_package_reviews(
///   repo_path="~/my-moonbit-repo",
///   worktrees_root="",
///   base_ref="origin/main",
///   concurrency=4,
///   model=None,
///   draft=true,
///   cleanup=false,
/// )
/// ```

///|
/// Configuration options for the package review process.
pub struct PackageReviewOptions {
  /// Path to the Git repository (supports `~` expansion)
  repo_path : String
  /// Directory to store worktrees (default: `<repo>.worktrees`)
  worktrees_root : String
  /// Base Git ref for branching (e.g., "origin/main")
  base_ref : String
  /// Maximum number of concurrent review agents
  concurrency : Int
  /// Optional AI model name override
  model : String?
  /// If true, creates draft PRs; otherwise ready-for-review
  draft : Bool
  /// If true, removes worktrees that have no changes
  cleanup : Bool
} derive(Show)

///|
/// Represents a single package review task with its associated Git branch and worktree.
priv struct PackageReview {
  /// Relative path to the package directory (e.g., "workflow" or "." for root)
  package_dir : String
  /// Git branch name for this review (e.g., "review/workflow")
  branch : String
  /// Absolute path to the Git worktree for isolated changes
  worktree_path : String
  /// Unique name for the AI agent handling this package
  agent_name : String
  /// Unique task identifier in the workflow DAG
  task_id : String
}

///|
/// Result of the prepare phase, containing ready reviews and the workflow.
/// Use `workflow()` to access the workflow DAG for preview/inspection.
pub struct PreparedReview {
  priv reviews : Array[PackageReview]
  priv workflow : @workflow.Workflow
  priv repo : String
  priv base_ref : String
}

///|
/// Returns the workflow DAG for inspection (e.g., rendering with `render_workflow_dag`).
pub fn PreparedReview::workflow(self : PreparedReview) -> @workflow.Workflow {
  self.workflow
}

///|
/// Returns the number of packages that will be reviewed.
pub fn PreparedReview::package_count(self : PreparedReview) -> Int {
  self.reviews.length()
}

///|
/// Creates default options with sensible defaults.
pub fn PackageReviewOptions::new(
  repo_path : String,
  base_ref~ : String = "origin/main",
  worktrees_root~ : String = "",
  concurrency~ : Int = 4,
  model~ : String? = None,
  draft~ : Bool = true,
  cleanup~ : Bool = false,
) -> PackageReviewOptions {
  { repo_path, worktrees_root, base_ref, concurrency, model, draft, cleanup }
}

///|
/// Prepares package reviews without executing them.
/// Use this for preview/dry-run to inspect the workflow DAG before running.
///
/// Returns `None` if the repository is invalid or no packages are found.
pub async fn prepare_package_reviews(
  options : PackageReviewOptions
) -> PreparedReview? {
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
  let reviews = build_package_reviews(packages, worktrees)
  let ready : Array[PackageReview] = []
  for review in reviews {
    if ensure_worktree(repo, review, base) {
      ready.push(review)
    }
  }
  if ready.is_empty() {
    @stdio.stderr.write("No worktrees available to review.\n")
    return None
  }
  let workflow = build_review_workflow(ready, options.model, repo, base)
  Some(PreparedReview::{ reviews: ready, workflow, repo, base_ref: base })
}

///|
/// Executes a prepared review workflow.
/// Call `prepare_package_reviews` first to get the `PreparedReview`.
pub async fn execute_prepared_review(
  prepared : PreparedReview,
  options : PackageReviewOptions,
) -> Unit {
  let codex = @codex.Codex::new()
  let run_options = @workflow.RunOptions::new(
    prepared.repo,
    options.concurrency,
    default_sandbox=@codex.SandboxMode::WorkspaceWrite,
    default_model?=options.model,
  )
  @stdio.stdout.write(
    "Reviewing \{prepared.reviews.length()} packages with concurrency \{run_options.concurrency}...\n",
  )
  let results = @workflow.run_workflow(prepared.workflow, codex, run_options) catch {
    e => {
      @stdio.stderr.write("Package review failed: \{e}\n")
      return
    }
  }
  let base_branch = pr_base_branch(prepared.base_ref)
  for review in prepared.reviews {
    let output = results.get(review.task_id).unwrap_or("")
    let changed_files = list_changed_files(review.worktree_path)
    if changed_files.is_empty() {
      @stdio.stdout.write(
        "Package \{review.package_dir}: no changes detected.\n",
      )
      if options.cleanup {
        remove_worktree(prepared.repo, review.worktree_path)
      }
      continue
    }
    if !all_in_package(changed_files, review.package_dir) {
      @stdio.stderr.write(
        "Package \{review.package_dir}: changes outside package scope; skipping PR.\n",
      )
      continue
    }
    let title = default_review_title(review.package_dir)
    let tests = default_tests(review.package_dir)
    let body = build_review_body(output, review.package_dir, tests)
    if !commit_package_changes(review.worktree_path, review.package_dir, title) {
      continue
    }
    if !push_branch(review.worktree_path, review.branch) {
      continue
    }
    if !create_pr(
      review.worktree_path,
      review.branch,
      base_branch,
      title,
      body,
      options.draft,
    ) {
      continue
    }
    @stdio.stdout.write(
      "Package \{review.package_dir}: draft PR created on \{review.branch}.\n",
    )
  }
}

///|
/// Main entry point for parallel package reviews.
///
/// This function orchestrates the entire review process:
/// 1. Validates the repository and discovers MoonBit packages
/// 2. Creates Git worktrees for isolated package reviews
/// 3. Builds a workflow DAG with one agent per package
/// 4. Executes reviews in parallel (respecting concurrency limit)
/// 5. Creates draft PRs for packages with changes
pub async fn run_package_reviews(options : PackageReviewOptions) -> Unit {
  match prepare_package_reviews(options) {
    Some(prepared) => execute_prepared_review(prepared, options)
    None => ()
  }
}

///|
/// Expands `~` to the user's home directory in a path string.
fn expand_home(path : String) -> String {
  if path.has_prefix("~") {
    let home = @sys.get_env_var("HOME").unwrap_or("")
    if home.is_empty() {
      return path
    }
    if path == "~" {
      return home
    }
    if path.strip_prefix("~/") is Some(rest) {
      return home + "/" + rest.to_string()
    }
  }
  path
}

///|
/// Normalizes a path by resolving `.` and `..` components.
fn normalize_path(path : String) -> String {
  @path.Path(path).normalize().to_string()
}

///|
/// Computes the default worktrees directory: `<repo-name>.worktrees` in the parent folder.
fn default_worktrees_root(repo_path : String) -> String {
  let repo = @path.Path(repo_path)
  let parent = repo.dirname()
  let name = repo.basename().to_string()
  let root = "\{name}.worktrees"
  parent.join(@path.Path(root)).to_string()
}

///|
/// Checks if the given path is inside a valid Git repository.
async fn is_git_repo(repo : String) -> Bool {
  let (code, output) = run_command_output(
    "git",
    ["-C", repo, "rev-parse", "--show-toplevel"],
  )
  if code != 0 {
    @stdio.stderr.write("Not a git repo at \{repo}: \{output}\n")
    return false
  }
  true
}

///|
/// Creates a directory (and parents) if it doesn't exist.
async fn ensure_directory(path : String) -> Unit {
  let _ = @process.run("mkdir", ["-p", path], inherit_env=true)
}

///|
/// Discovers all MoonBit packages in a repository by finding `moon.pkg` files.
/// Ignores `_build/`, `target/`, `.git/`, and `.worktrees/` directories.
async fn discover_packages(repo : String) -> Array[String] {
  let packages : Map[String, Bool] = {}
  let files = find_package_files(repo)
  for file in files {
    let trimmed = trim_prefix(file, "./")
    if should_ignore_path(trimmed) {
      continue
    }
    let dir = @path.Path(trimmed).dirname().to_string()
    let key = if dir == "" { "." } else { dir }
    packages[key] = true
  }
  let output : Array[String] = []
  for dir, _ in packages {
    output.push(dir)
  }
  output.sort()
  output
}

///|
/// Finds all `moon.pkg` and `moon.pkg.json` files using ripgrep (or find as fallback).
async fn find_package_files(repo : String) -> Array[String] {
  let (code, output) = run_command_output(
    "rg",
    ["--files", "-g", "moon.pkg", "-g", "moon.pkg.json"],
    cwd=repo,
  )
  let lines = split_lines(output)
  if code == 0 && !lines.is_empty() {
    return lines
  }
  let (_, fallback) = run_command_output(
    "find",
    [".", "-name", "moon.pkg", "-o", "-name", "moon.pkg.json"],
    cwd=repo,
  )
  split_lines(fallback)
}

///|
/// Returns true if the path should be ignored (build artifacts, git internals, etc.).
fn should_ignore_path(path : String) -> Bool {
  path.has_prefix("_build/") ||
  path.has_prefix("target/") ||
  path.has_prefix(".git/") ||
  path.has_prefix(".worktrees/")
}

///|
fn trim_prefix(path : String, prefix : String) -> String {
  match path.strip_prefix(prefix) {
    Some(rest) => rest.to_string()
    None => path
  }
}

///|
/// Creates PackageReview entries for each discovered package.
/// Each review gets a unique branch, worktree path, agent name, and task ID.
fn build_package_reviews(
  packages : Array[String],
  worktrees_root : String,
) -> Array[PackageReview] {
  let output : Array[PackageReview] = []
  for package_dir in packages {
    let slug = slugify_package(package_dir)
    let branch = "review/\{slug}"
    let worktree_path = join_path(worktrees_root, slug)
    let agent_name = "reviewer_\{slug}"
    let task_id = "review_\{slug}"
    output.push(PackageReview::{
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
/// Converts a package path to a URL/branch-safe slug (e.g., "src/lib" -> "src-lib").
fn slugify_package(package_dir : String) -> String {
  if package_dir == "." {
    return "root"
  }
  let builder = StringBuilder::new()
  for ch in package_dir {
    match ch {
      '/' | '\\' => builder.write_char('-')
      'a'..='z' | 'A'..='Z' | '0'..='9' | '-' | '_' | '.' => builder.write_char(ch)
      _ => builder.write_char('-')
    }
  }
  let slug = builder.to_string()
  if slug.is_empty() { "root" } else { slug }
}

///|
fn join_path(left : String, right : String) -> String {
  @path.Path(left).join(@path.Path(right)).to_string()
}

///|
/// Creates a Git worktree for the package review, or reuses an existing one.
/// Returns false if worktree creation fails.
async fn ensure_worktree(
  repo : String,
  review : PackageReview,
  base_ref : String,
) -> Bool {
  if @fs.path_exists(review.worktree_path) {
    return true
  }
  let args = [
    "-C",
    repo,
    "worktree",
    "add",
    "-b",
    review.branch,
    review.worktree_path,
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
    review.worktree_path,
    review.branch,
  ]
  let (fallback_code, _) = run_command_output("git", fallback)
  if fallback_code == 0 {
    return true
  }
  @stdio.stderr.write(
    "Failed to create worktree for \{review.package_dir}: \{output}\n",
  )
  false
}

///|
/// Builds a workflow DAG with one agent and task per package.
/// All tasks are independent (no dependencies), enabling full parallelism.
fn build_review_workflow(
  reviews : Array[PackageReview],
  model : String?,
  repo : String,
  base_ref : String,
) -> @workflow.Workflow {
  let agents : Array[@workflow.AgentSpec] = []
  let nodes : Array[@workflow.TaskNode] = []
  for review in reviews {
    let role =
      "Review package \{review.package_dir} with minimal fixes and tests."
    let agent = match model {
      Some(value) =>
        @workflow.AgentSpec::new(
          review.agent_name,
          role,
          model=value,
          sandbox_mode=@codex.SandboxMode::WorkspaceWrite,
          working_directory=review.worktree_path,
        )
      None =>
        @workflow.AgentSpec::new(
          review.agent_name,
          role,
          sandbox_mode=@codex.SandboxMode::WorkspaceWrite,
          working_directory=review.worktree_path,
        )
    }
    agents.push(agent)
    let deps : Array[String] = []
    nodes.push(
      @workflow.TaskNode::new(
        review.task_id,
        "Review \{review.package_dir}",
        deps,
        review.agent_name,
        build_review_prompt(review.package_dir, repo, base_ref),
      ),
    )
  }
  @workflow.Workflow::new(agents, nodes)
}

///|
/// Generates the AI agent prompt for reviewing a specific package.
/// Instructs the agent to run `moon fmt`, `moon check`, and `moon test`.
fn build_review_prompt(
  package_dir : String,
  repo : String,
  base_ref : String,
) -> String {
  let pkg = if package_dir == "." { "." } else { package_dir }
  let prompt =
    $|You are reviewing the MoonBit package at "\{pkg}" in repo "\{repo}".
    $|
    $|Rules:
    $|- Only change files under "\{pkg}".
    $|- Keep changes small and reviewable.
    $|- Do not commit or open PRs.
    $|
    $|Run these commands from the repo root:
    $|- moon fmt \{pkg}
    $|- moon check
    $|- moon test \{pkg}
    $|
    $|If fixes are needed, apply them in this package only and re-run the commands.
    $|
    $|Return a concise summary in this format:
    $|Title: <short PR title suggestion>
    $|Summary:
    $|- bullet 1
    $|- bullet 2
    $|Tests:
    $|- moon fmt \{pkg}
    $|- moon check
    $|- moon test \{pkg}
    $|
    $|Base ref for context: \{base_ref}
  prompt
}

///|
fn default_tests(package_dir : String) -> Array[String] {
  [
    "moon fmt \{package_dir}",
    "moon check",
    "moon test \{package_dir}",
  ]
}

///|
/// Lists all changed files (staged, unstaged, and untracked) in a worktree.
async fn list_changed_files(worktree_path : String) -> Array[String] {
  let (code, output) = run_command_output(
    "git",
    ["-C", worktree_path, "diff", "--name-only"],
  )
  let tracked = if code == 0 { split_lines(output) } else { [] }
  let (other_code, other_output) = run_command_output(
    "git",
    ["-C", worktree_path, "ls-files", "--others", "--exclude-standard"],
  )
  let untracked =
    if other_code == 0 { split_lines(other_output) } else { [] }
  let seen : Map[String, Bool] = {}
  for file in tracked {
    if !file.is_empty() {
      seen[file] = true
    }
  }
  for file in untracked {
    if !file.is_empty() {
      seen[file] = true
    }
  }
  let files : Array[String] = []
  for file, _ in seen {
    files.push(file)
  }
  files.sort()
  files
}

///|
/// Validates that all changed files are within the specified package directory.
fn all_in_package(files : Array[String], package_dir : String) -> Bool {
  if package_dir == "." {
    return true
  }
  let prefix = package_dir + "/"
  for file in files {
    if file == package_dir || file.has_prefix(prefix) {
      continue
    }
    return false
  }
  true
}

///|
/// Generates a default PR title for a package review.
fn default_review_title(package_dir : String) -> String {
  "review(\{package_dir}): updates"
}

///|
/// Builds the PR body from the agent's summary output and test commands.
fn build_review_body(
  raw : String,
  package_dir : String,
  tests : Array[String],
) -> String {
  let summary = raw.trim(char_set=" \t\r\n").to_string()
  let lines : Array[String] = []
  lines.push("Package: \{package_dir}")
  if !summary.is_empty() {
    lines.push("")
    lines.push("Summary:")
    lines.push(summary)
  }
  if !tests.is_empty() {
    lines.push("")
    lines.push("Tests:")
    for test_cmd in tests {
      lines.push("- " + test_cmd)
    }
  }
  lines.join("\n")
}

///|
/// Stages and commits changes in the package directory.
async fn commit_package_changes(
  worktree_path : String,
  package_dir : String,
  title : String,
) -> Bool {
  let (add_code, add_output) = run_command_output(
    "git",
    ["-C", worktree_path, "add", package_dir],
  )
  if add_code != 0 {
    @stdio.stderr.write(
      "Failed to stage changes in \{package_dir}: \{add_output}\n",
    )
    return false
  }
  let (commit_code, commit_output) = run_command_output(
    "git",
    ["-C", worktree_path, "commit", "-m", title],
  )
  if commit_code != 0 {
    @stdio.stderr.write(
      "Failed to commit changes in \{package_dir}: \{commit_output}\n",
    )
    return false
  }
  true
}

///|
/// Pushes the review branch to the remote repository.
async fn push_branch(worktree_path : String, branch : String) -> Bool {
  let (code, output) = run_command_output(
    "git",
    ["-C", worktree_path, "push", "-u", "origin", branch],
  )
  if code != 0 {
    @stdio.stderr.write("Failed to push \{branch}: \{output}\n")
    return false
  }
  true
}

///|
/// Creates a Pull Request using the `gh` CLI tool.
async fn create_pr(
  worktree_path : String,
  branch : String,
  base_branch : String,
  title : String,
  body : String,
  draft : Bool,
) -> Bool {
  let body_path = join_path(worktree_path, ".codex_pr_body.md")
  let write_result : Result[Unit, @fs.IOError] =
    try? @fs.write_string_to_file(body_path, body)
  if write_result is Err(err) {
    @stdio.stderr.write("Failed to write PR body: \{err}\n")
    return false
  }
  let args : Array[String] = [
    "-C",
    worktree_path,
    "pr",
    "create",
    "--base",
    base_branch,
    "--head",
    branch,
    "--title",
    title,
    "--body-file",
    body_path,
  ]
  if draft {
    args.push("--draft")
  }
  let (code, output) = run_command_output("gh", args)
  if code != 0 {
    @stdio.stderr.write("Failed to open PR for \{branch}: \{output}\n")
    return false
  }
  true
}

///|
/// Extracts the branch name from a ref (e.g., "origin/main" -> "main").
fn pr_base_branch(base_ref : String) -> String {
  let mut last = base_ref
  for part in base_ref.split("/") {
    last = part.to_string()
  }
  last
}

///|
/// Removes a Git worktree (cleanup when no changes detected).
async fn remove_worktree(repo : String, worktree_path : String) -> Unit {
  let _ = run_command_output(
    "git",
    ["-C", repo, "worktree", "remove", worktree_path],
  )
}

///|
/// Runs a shell command and captures both stdout and stderr.
/// Returns (exit_code, combined_output).
async fn run_command_output(
  command : String,
  args : Array[String],
  cwd? : String,
) -> (Int, String) {
  let (stdout_path, stderr_path) = temp_output_paths()
  let tmp_dir = @path.Path(stdout_path).dirname().to_string()
  ensure_directory(tmp_dir)
  let stdout = @process.redirect_to_file(
    stdout_path,
    create=420,
    truncate=true,
  )
  let stderr = @process.redirect_to_file(
    stderr_path,
    create=420,
    truncate=true,
  )
  let code = @process.run(
    command,
    args,
    inherit_env=true,
    stdout=stdout,
    stderr=stderr,
    cwd?=cwd,
  )
  let out_text = read_file_safe(stdout_path)
  let err_text = read_file_safe(stderr_path)
  let text = if err_text.is_empty() {
    out_text
  } else if out_text.is_empty() {
    err_text
  } else {
    out_text + "\n" + err_text
  }
  (code, text.trim_end(chars=" \t\r\n").to_string())
}

///|
fn temp_output_paths() -> (String, String) {
  let home = @sys.get_env_var("HOME").unwrap_or(".")
  let tmp_dir = join_path(home, ".codex_workflow_tmp")
  (
    join_path(tmp_dir, "codex_workflow_cmd_out.txt"),
    join_path(tmp_dir, "codex_workflow_cmd_err.txt"),
  )
}

///|
fn read_file_safe(path : String) -> String {
  let result : Result[String, @fs.IOError] = try? @fs.read_file_to_string(path)
  match result {
    Ok(text) => text
    Err(_) => ""
  }
}

///|
fn split_lines(text : String) -> Array[String] {
  let output : Array[String] = []
  for line in text.split("\n") {
    let value = line.trim_end(chars="\r")
    if !value.is_empty() {
      output.push(value.to_string())
    }
  }
  output
}
