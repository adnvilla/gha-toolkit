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

Located in `.github/workflows/` with prefix indicating purpose:

- `go.yml`: Workflow for Go projects
- `release.yml`: Workflow for semantic releases

**Requirements for reusable workflows:**
1. Use `workflow_call` trigger
2. Define clear `inputs` with descriptions
3. Include usage examples in documentation
4. Be generic (not specific to one project)

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

## Validating Before PR

### YAML Validation

```bash
yamllint .github/workflows/*.yml
```

### Markdown Validation

```bash
markdownlint *.md
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
