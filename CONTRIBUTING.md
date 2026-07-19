# Contributing to GitHub Actions Toolkit

Thank you for considering contributing to this project! This toolkit provides reusable workflows for CI/CD across different types of projects.

## How to Contribute

### 1. Fork and Clone

```bash
git fork adnvilla/gha-toolkit
git clone https://github.com/YOUR_USERNAME/gha-toolkit.git
cd gha-toolkit
```

### 2. Create a Branch

```bash
git checkout -b feature/my-new-feature
```

### 3. Make Your Changes

- Follow existing code style
- Keep workflows simple and reusable
- Add clear comments in YAML
- Update documentation if adding/changing features

### 4. Commit with Conventional Commits

This project uses **semantic-release** to generate versions automatically. Use conventional commits:

**Format:**
```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types:**
- `feat`: New feature (generates MINOR version)
- `fix`: Bug fix (generates PATCH version)
- `docs`: Documentation changes
- `chore`: Maintenance tasks
- `refactor`: Code refactoring
- `test`: Adding/modifying tests
- `ci`: CI/CD changes

**Examples:**

```bash
# Add a new feature
git commit -m "feat: add support for Node.js workflows"

# Fix a bug
git commit -m "fix: correct PostgreSQL service configuration"

# Breaking change (generates MAJOR version)
git commit -m "feat!: change workflow input structure

BREAKING CHANGE: input names have changed from snake_case to kebab-case"

# Documentation
git commit -m "docs: add examples for Python projects"

# Infrastructure
git commit -m "chore: update dependencies"
```

### 5. Push and Create a Pull Request

```bash
git push origin feature/my-new-feature
```

Then create a PR on GitHub with:
- Clear title following conventional commits
- Description of what changes and why
- Reference to related issues (if applicable)

## Workflow Structure

### Reusable Workflows

Located in `.github/workflows/`, one file per domain:

- `go-base.yml` / `go.yml`: Go projects (without / with PostgreSQL)
- `node.yml`: Node.js/TypeScript projects (pnpm, npm or yarn)
- `docker-build-push.yml`: Build and push a Docker image
- `k8s-deploy.yml`: Deploy to Kubernetes via Helm, using `charts/app`
- `release.yml`: Semantic releases

**Requirements for reusable workflows:**
1. Use `workflow_call` trigger
2. Define clear `inputs` with descriptions
3. Include a `runs-on` input (string, default `ubuntu-latest` unless the workflow inherently needs a
   private network — e.g. `k8s-deploy.yml` defaults to `self-hosted`), so consumers can choose the runner
4. Include usage examples in documentation
5. Be generic (not specific to one project)

### Internal Workflows

Workflows that manage the toolkit itself:

- `ci.yml`: Validates YAML and Markdown syntax
- `auto-release.yml`: Generates toolkit versions

## Adding a New Reusable Workflow

1. Create the file in `.github/workflows/`:

```yaml
name: My New Workflow

on:
  workflow_call:
    inputs:
      my-param:
        description: 'Description of parameter'
        required: true
        type: string
        default: 'default-value'
    secrets:
      my-secret:
        description: 'Description of secret'
        required: false

jobs:
  my-job:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Do something
        run: echo "Using ${{ inputs.my-param }}"
```

2. Add usage example to `EXAMPLES.md`
3. Update `README.md` if necessary
4. Create a PR with commit `feat: add workflow for X`

## Modifying the Helm Chart (charts/app)

`charts/app` is consumed by every project using `k8s-deploy.yml`, pinned to a specific
`gha-toolkit` git ref via the `toolkit-ref` input — so changes here are versioned the same way as
the workflows themselves:

1. Prefer adding a new **optional** value with a backward-compatible default over changing the
   meaning of an existing one
2. Bump `charts/app/Chart.yaml`'s `version` whenever a template changes in a way consumers should
   notice (new resource, changed default, renamed value) — this is a manual bump, there's no
   automation for it yet
3. Update `charts/app/README.md`'s values table
4. Validate locally before opening a PR:

```bash
helm lint charts/app
helm template charts/app --set image.repository=test --set image.tag=test
```

5. Renaming or removing a value, or changing a default in a way that changes rendered output, is a
   **breaking change** — commit with `feat!:` and call it out in the PR description

## Validating Before PR

### YAML Validation

```bash
yamllint .github/workflows/*.yml
```

### Markdown Validation

```bash
markdownlint *.md
```

### Helm Chart Validation

```bash
helm lint charts/app
helm template charts/app --set image.repository=test --set image.tag=test
```

## Versioning

This project follows **Semantic Versioning**:

- **MAJOR** (1.0.0 → 2.0.0): Breaking changes
- **MINOR** (1.0.0 → 1.1.0): New features (backward compatible)
- **PATCH** (1.0.0 → 1.0.1): Bug fixes

Versions are generated **automatically** by semantic-release based on conventional commits.

## Configuration Files

### `.releaserc.json`

Configuration for semantic-release. Defines:
- Which branches generate releases
- Which plugins are used
- Commit analysis

### `.yamllint.yml`

YAML linting configuration. Ensures:
- Consistent indentation
- Line length limits
- Proper syntax

### `.markdownlint.json`

Markdown linting configuration. Ensures:
- Consistent formatting
- Proper headers
- Code block style

## Continuous Integration

All PRs go through CI that validates:

1. **YAML Syntax** (`yamllint`)
2. **Markdown Syntax** (`markdownlint`)
3. **Workflow Structure** (GitHub Actions validation)

PRs cannot be merged if CI fails.

## Release Process

**Automated:**

1. Merge PR to `master`
2. `ci.yml` runs validations
3. If CI passes, `auto-release.yml` runs
4. Semantic-release analyzes commits
5. If applicable, creates new tag and release

**Manual:**

If you need to test the release process:

```bash
git checkout master
git pull
npx semantic-release --dry-run
```

## Questions or Issues?

- Open an **Issue** for bugs or feature requests
- Use **Discussions** for general questions
- Mention `@adnvilla` if urgent

## Code of Conduct

- Be respectful and professional
- Accept constructive criticism
- Focus on what's best for the project
- Help other contributors

Thank you for contributing! 🎉
