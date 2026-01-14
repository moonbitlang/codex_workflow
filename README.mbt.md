# codex_workflow

Multi-agent workflow runner for Codex, built in MoonBit.

## Layout

- `workflow/` library package with agents, workflow DAG types, and runner
- `cmd/main/` CLI entrypoint

## Quick start

```bash
moon run cmd/main -- --list
moon run cmd/main -- --sample kickoff
```

## CLI options

```bash
moon run cmd/main -- --help
moon run cmd/main -- --sample kickoff --dag
```

## Notes

- Agents are defined in `workflow/sample.mbt`.
- Each task node references an agent by name and declares dependencies.
- The runner executes ready nodes concurrently (configurable with `--concurrency`).
