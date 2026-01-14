///|
priv struct PackageReviewOptions {
  repo_path : String
  worktrees_root : String
  base_ref : String
  concurrency : Int
  model : String?
  draft : Bool
  cleanup : Bool
}

///|
priv struct PackageReview {
  package_dir : String
  branch : String
  worktree_path : String
  agent_name : String
  task_id : String
}

///|
pub async fn run_package_reviews(
  repo_path : String,
  worktrees_root : String,
  base_ref : String,
  concurrency : Int,
  model : String?,
  draft : Bool,
  cleanup : Bool,
) -> Unit {
  let options = PackageReviewOptions::{
    repo_path,
    worktrees_root,
    base_ref,
    concurrency,
    model,
    draft,
    cleanup,
  }
  let repo = normalize_path(expand_home(options.repo_path))
  if !is_git_repo(repo) {
    return
  }
  let base = options.base_ref
  let worktrees =
    if options.worktrees_root.is_empty() {
      default_worktrees_root(repo)
    } else {
      normalize_path(expand_home(options.worktrees_root))
    }
  let packages = discover_packages(repo)
  if packages.is_empty() {
    @stdio.stdout.write("No MoonBit packages found in \{repo}\n")
    return
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
    return
  }
  let workflow = build_review_workflow(ready, options.model, repo, base)
  let codex = @codex.Codex::new()
  let run_options = @workflow.RunOptions::new(
    repo,
    options.concurrency,
    default_sandbox=@codex.SandboxMode::WorkspaceWrite,
    default_model?=options.model,
  )
  @stdio.stdout.write(
    "Reviewing \{ready.length()} packages with concurrency \{run_options.concurrency}...\n",
  )
  let results = @workflow.run_workflow(workflow, codex, run_options) catch {
    e => {
      @stdio.stderr.write("Package review failed: \{e}\n")
      return
    }
  }
  let base_branch = pr_base_branch(base)
  for review in ready {
    let output = results.get(review.task_id).unwrap_or("")
    let changed_files = list_changed_files(review.worktree_path)
    if changed_files.is_empty() {
      @stdio.stdout.write(
        "Package \{review.package_dir}: no changes detected.\n",
      )
      if options.cleanup {
        remove_worktree(repo, review.worktree_path)
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
fn normalize_path(path : String) -> String {
  @path.Path(path).normalize().to_string()
}

///|
fn default_worktrees_root(repo_path : String) -> String {
  let repo = @path.Path(repo_path)
  let parent = repo.dirname()
  let name = repo.basename().to_string()
  let root = "\{name}.worktrees"
  parent.join(@path.Path(root)).to_string()
}

///|
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
async fn ensure_directory(path : String) -> Unit {
  let _ = @process.run("mkdir", ["-p", path], inherit_env=true)
}

///|
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
fn default_review_title(package_dir : String) -> String {
  "review(\{package_dir}): updates"
}

///|
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
fn pr_base_branch(base_ref : String) -> String {
  let mut last = base_ref
  for part in base_ref.split("/") {
    last = part.to_string()
  }
  last
}

///|
async fn remove_worktree(repo : String, worktree_path : String) -> Unit {
  let _ = run_command_output(
    "git",
    ["-C", repo, "worktree", "remove", worktree_path],
  )
}

///|
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
