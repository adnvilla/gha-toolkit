# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`gha-toolkit` has no application source code. Its entire product is the set of **reusable GitHub Actions
workflows** in `.github/workflows/`, consumed by other repos via `uses: adnvilla/gha-toolkit/.github/workflows/<file>.yml@<ref>`.
Everything else in the repo (README, ARCHITECTURE, EXAMPLES, CONTRIBUTING) documents those workflows.

## Commands

There is no build/test/app runtime — validation is linting the workflow YAML and the Markdown docs.

```bash
# Validate all workflow YAML (matches ci.yml's validate-workflows job)
yamllint -c .yamllint.yml .github/workflows/

# Validate a single workflow file
yamllint -c .yamllint.yml .github/workflows/go.yml

# Validate Markdown docs (matches ci.yml's validate-markdown job)
markdownlint . --config .markdownlint.json --ignore node_modules

# Dry-run the release process locally (requires GITHUB_TOKEN and node/npm)
npx semantic-release --dry-run
```

Manual end-to-end testing of a reusable workflow is done via `.github/workflows/test.yml`
(`workflow_dispatch`, choice input `go` | `release` | `both`) — it calls `go.yml` and `release.yml`
locally with safe flags (`run-tests: false` since this repo has no Go code; `dry-run: true` for release).

## Architecture

Two tiers, both living in `.github/workflows/`:

**Reusable workflows** (triggered by `workflow_call`, meant to be consumed by other repos):
- `go-base.yml` — build/test Go projects with no external services (`go mod tidy && go mod verify`, `go build`, `go test`).
- `go.yml` — same as `go-base.yml` but spins up a Postgres service container and passes `POSTGRES_DSN` to the test step. Use `go-base.yml` for plain libraries, `go.yml` when tests need a database.
- `release.yml` — runs `semantic-release` (installed ad hoc via `npm install -g`, not a committed `package.json`) using the caller's `GITHUB_TOKEN` or an explicit `github-token` secret. Supports `dry-run`.

**Internal workflows** (govern this repo's own lifecycle, not reusable):
- `ci.yml` — runs on push/PR to `master`; lints workflow YAML (`yamllint`) and Markdown (`markdownlint`), then a no-op `ci-complete` job that gates on both (markdown failures are logged but don't currently fail the gate — see the `if` check in that job).
- `auto-release.yml` — triggered by `workflow_run` after `ci.yml` succeeds on `master`; runs the same semantic-release logic as `release.yml` (dogfooded, not literally invoked as a reusable workflow) to tag/publish this repo's own versions.
- `test.yml` — manual (`workflow_dispatch`) smoke test that calls `go.yml`/`release.yml` from `./.github/workflows/` (local ref) to confirm they're callable without breaking.

**Versioning flow**: commit to `master` with a Conventional Commit → `ci.yml` lints → on success `auto-release.yml` fires → `semantic-release` (config in `.releaserc.json`) analyzes commits, bumps the version, updates `CHANGELOG.md`, and creates a GitHub release/tag. Release-triggering rules per commit type are defined in `.releaserc.json`'s `commit-analyzer` config: `feat`→minor, `fix`/`perf`/`revert`/`docs`/`refactor`→patch, `chore`/`test`/`build`/`ci`→no release. (Note: this is stricter than what `CONTRIBUTING.md`/`ARCHITECTURE.md` describe — those docs are not fully in sync with `.releaserc.json`; treat `.releaserc.json` as the source of truth.)

Consumers pin a version tag (e.g. `@v1.0.0`), a major-version moving tag (`@v1`), or `@master` for bleeding edge.

## Conventions when editing workflows

- Every reusable workflow must use `on: workflow_call`, declare `inputs`/`secrets` with `description`s, and stay generic (not tailored to one project).
- When adding or changing a reusable workflow: add a usage example to `EXAMPLES.md` and update `README.md`'s workflow list.
- Conventional Commits are required for every commit that should participate in the release calculus (see `.releaserc.json` mapping above) — `docs:`/`chore:`/etc. for non-release changes.
- `.releaserc.json.example` is the template consumers copy into their own repos as `.releaserc.json`; keep it representative of a typical consumer config (it does not need to match this repo's own `.releaserc.json` exactly).
