# Architecture - GitHub Actions Toolkit

This document explains the technical design and architecture of the reusable workflows toolkit.

## Overview

The toolkit follows a **two-tier architecture**:

1. **Reusable Workflows**: Generic workflows that other projects can consume
2. **Internal Workflows**: Workflows that manage the toolkit's own lifecycle

## Reusable Workflows

### go.yml

**Purpose:** Provides a complete CI pipeline for Go projects with optional PostgreSQL integration.

**Trigger:**
```yaml
on:
  workflow_call:
```

**Inputs:**
- `go-version` (string): Go version to use (default: '1.24')
- `postgres-version` (string): PostgreSQL version (default: '15')
- `run-tests` (boolean): Whether to execute tests (default: true)
- `postgres-dsn` (string): PostgreSQL connection string (optional)

**Jobs:**

1. **build:**
   - Sets up Go environment with specified version
   - Builds the project with `go build -v ./...`
   - Validates compilation without running tests

2. **test:**
   - Depends on `build` job completion
   - Conditionally starts PostgreSQL service (if `postgres-dsn` provided)
   - Runs tests with `go test -v ./...`
   - Uses environment variable for database connection

**Design Decisions:**
- Separates build and test for better error diagnosis
- PostgreSQL is optional to support projects without databases
- Uses service containers (more efficient than installing PostgreSQL)
- Allows customization of connection string for different schemas

**Usage Pattern:**
```yaml
jobs:
  ci:
    uses: adnvilla/gha-toolkit/.github/workflows/go.yml@v1.0.0
    with:
      go-version: '1.24'
      postgres-version: '16'
```

### release.yml

**Purpose:** Implements semantic versioning and automatic releases using conventional commits.

**Trigger:**
```yaml
on:
  workflow_call:
```

**Inputs:**
- `node-version` (string): Node.js version for semantic-release (default: '20')
- `dry-run` (boolean): Test mode without publishing (default: false)

**Secrets:**
- `github-token`: Required for creating releases and tags

**Jobs:**

1. **semantic-release:**
   - Checks out repository with full history (`fetch-depth: 0`)
   - Sets up Node.js environment
   - Installs semantic-release and plugins
   - Analyzes commits to determine version
   - Creates tags and GitHub releases

**Design Decisions:**
- Requires full git history to analyze all commits
- Uses semantic-release plugins for automation
- Supports dry-run for testing
- Requires explicit token passing (security)

**Dependencies:**
```json
{
  "semantic-release": "^19.0.0",
  "@semantic-release/commit-analyzer": "^9.0.0",
  "@semantic-release/release-notes-generator": "^10.0.0",
  "@semantic-release/github": "^8.0.0"
}
```

**Usage Pattern:**
```yaml
jobs:
  release:
    uses: adnvilla/gha-toolkit/.github/workflows/release.yml@v1.0.0
    permissions:
      contents: write
    with:
      dry-run: false
    secrets:
      github-token: ${{ secrets.GITHUB_TOKEN }}
```

## Internal Workflows

### ci.yml

**Purpose:** Validates the toolkit itself - lints YAML and Markdown files.

**Trigger:**
```yaml
on:
  push:
    branches: [ "master" ]
  pull_request:
    branches: [ "master" ]
```

**Jobs:**

1. **lint:**
   - Validates all `.yml` files with `yamllint`
   - Validates all `.md` files with `markdownlint`
   - Prevents merging PRs with syntax errors

**Configuration Files:**
- `.yamllint.yml`: YAML linting rules
- `.markdownlint.json`: Markdown linting rules

**Design Decisions:**
- Runs on every push/PR to maintain quality
- Blocks merging if validation fails
- Uses GitHub Actions for consistency

### auto-release.yml

**Purpose:** Generates semantic versions for the toolkit itself.

**Trigger:**
```yaml
on:
  workflow_run:
    workflows: ["CI"]
    types: [completed]
    branches: [master]
```

**Conditional Execution:**
```yaml
if: ${{ github.event.workflow_run.conclusion == 'success' }}
```

**Jobs:**

1. **release:**
   - Waits for `ci.yml` to complete successfully
   - Calls `release.yml` as a reusable workflow
   - Creates tags like `v1.0.0`, `v1.1.0`, etc.

**Design Decisions:**
- Only runs after CI passes (quality gate)
- Only runs on `master` branch
- Uses the same `release.yml` that consumers use (dogfooding)
- Automatically triggered (no manual intervention)

## Workflow Interaction Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     External Project                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  .github/workflows/ci.yml                                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  uses: adnvilla/gha-toolkit/.github/workflows/      │   │
│  │        go.yml@v1.0.0                                │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                 │
│                           ▼                                 │
│  .github/workflows/release.yml                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  uses: adnvilla/gha-toolkit/.github/workflows/      │   │
│  │        release.yml@v1.0.0                           │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                   gha-toolkit Repository                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  .github/workflows/go.yml         ◄── Reusable Workflows   │
│  .github/workflows/release.yml    ◄── Reusable Workflows   │
│                                                             │
│  .github/workflows/ci.yml         ◄── Internal Workflows   │
│           │                                                 │
│           ▼                                                 │
│  .github/workflows/auto-release.yml                         │
│           │                                                 │
│           └─────► calls release.yml                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Version Management

### Semantic Versioning Flow

```
Conventional Commit → Commit Analyzer → Version Calculator → Tag Creator → Release Publisher
```

**Commit Types → Version Impact** (per the `commit-analyzer` `releaseRules` in `.releaserc.json`):

| Type | Example | Version Change |
|------|---------|----------------|
| `feat:` | `feat: add new input` | 1.0.0 → 1.1.0 (MINOR) |
| `fix:` | `fix: correct validation` | 1.0.0 → 1.0.1 (PATCH) |
| `perf:` | `perf: reduce checkout time` | 1.0.0 → 1.0.1 (PATCH) |
| `revert:` | `revert: revert previous change` | 1.0.0 → 1.0.1 (PATCH) |
| `docs:` | `docs: clarify usage example` | 1.0.0 → 1.0.1 (PATCH) |
| `refactor:` | `refactor: simplify job steps` | 1.0.0 → 1.0.1 (PATCH) |
| `feat!:` | `feat!: change API` | 1.0.0 → 2.0.0 (MAJOR) |
| `BREAKING CHANGE:` | In commit body | 1.0.0 → 2.0.0 (MAJOR) |
| `chore:`, `test:`, `build:`, `ci:` | Maintenance/CI-only | No release |

### Configuration (.releaserc.json)

This repository's own `.releaserc.json` (used by `auto-release.yml`):

```json
{
  "branches": ["master"],
  "plugins": [
    ["@semantic-release/commit-analyzer", { "preset": "conventionalcommits", "releaseRules": ["..."] }],
    ["@semantic-release/release-notes-generator", { "preset": "conventionalcommits", "presetConfig": { "...": "..." } }],
    "@semantic-release/changelog",
    ["@semantic-release/git", { "assets": ["CHANGELOG.md"], "message": "chore(release): ..." }],
    ["@semantic-release/github", { "successComment": false, "failComment": false, "releasedLabels": false }]
  ]
}
```

See the actual `.releaserc.json` for the full `releaseRules` and `presetConfig`; `.releaserc.json.example` shows the equivalent config consumers should copy into their own projects.

**Plugin Roles:**
- **commit-analyzer**: Determines if a release is needed and the version bump, per the custom `releaseRules` (see the table above)
- **release-notes-generator**: Creates changelog notes from commits, grouped into sections via `presetConfig`
- **changelog**: Writes/updates `CHANGELOG.md`
- **git**: Commits `CHANGELOG.md` back to the repo as `chore(release): <version> [skip ci]`
- **github**: Publishes the GitHub release and tag

## Extensibility

### Adding New Workflows

1. Create workflow with `workflow_call` trigger
2. Define inputs clearly with descriptions
3. Add examples to `EXAMPLES.md`
4. Update `README.md`
5. Commit with `feat: add X workflow`

### Modifying Existing Workflows

**Breaking Changes:**
- Changing input names
- Removing inputs
- Changing default behavior

**Non-Breaking Changes:**
- Adding optional inputs
- Fixing bugs
- Improving performance

## Security Considerations

### Secret Handling

- Secrets are never logged or exposed
- Must be passed explicitly with `secrets:`
- Use `GITHUB_TOKEN` when possible (auto-rotated)

### Permissions

Reusable workflows inherit caller's permissions:

```yaml
permissions:
  contents: write  # Needed for releases
  pull-requests: read  # Needed for PR comments
```

### Dependency Management

- Pin action versions (`@v3`, not `@latest`)
- Review dependencies regularly
- Use Dependabot for updates

## Testing

### Manual Testing

```bash
# Test YAML validation
yamllint .github/workflows/*.yml

# Test Markdown validation
markdownlint *.md

# Test release (dry-run)
npx semantic-release --dry-run
```

### Integration Testing

- Create test repository
- Use workflows from branch before merging
- Verify outputs and behaviors

## Performance

### Optimization Strategies

1. **Caching:**
   - Go modules cached with `actions/cache`
   - Node modules cached in release workflow

2. **Parallel Execution:**
   - Build and test run sequentially (dependency)
   - Multiple reusable workflows can run in parallel

3. **Resource Usage:**
   - Uses `ubuntu-latest` (fastest runner)
   - PostgreSQL as service container (lightweight)

## Monitoring

### Workflow Status

Check workflow runs at:
```
https://github.com/adnvilla/gha-toolkit/actions
```

### Release History

Check releases at:
```
https://github.com/adnvilla/gha-toolkit/releases
```

## Future Considerations

### Potential Additions

- Python project workflow
- Node.js project workflow
- Docker build workflow
- Multi-platform testing
- Security scanning integration

### Backward Compatibility

- Version tags are immutable
- Consumers should pin to specific versions
- Major version updates documented clearly

## References

- [GitHub Actions Reusable Workflows](https://docs.github.com/en/actions/using-workflows/reusing-workflows)
- [Semantic Release](https://semantic-release.gitbook.io/)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [Semantic Versioning](https://semver.org/)
