# Usage Examples - GitHub Actions Toolkit

This document contains practical examples of how to use the reusable workflows in different scenarios.

## Example 1: Simple Go Project

For a Go project without a database:

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [ "master", "main" ]
  pull_request:
    branches: [ "master", "main" ]

jobs:
  build-and-test:
    uses: adnvilla/gha-toolkit/.github/workflows/go.yml@v1.0.0
    with:
      go-version: '1.24'
      run-tests: true
```

## Example 2: Go Project with PostgreSQL

For a project that needs PostgreSQL for tests:

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [ "master" ]
  pull_request:
    branches: [ "master" ]

jobs:
  build-and-test:
    uses: adnvilla/gha-toolkit/.github/workflows/go.yml@v1.0.0
    with:
      go-version: '1.24'
      postgres-version: '16'
      run-tests: true
      postgres-dsn: 'host=localhost user=postgres password=postgres dbname=testdb port=5432 sslmode=disable'
```

## Example 3: Complete CI/CD (Build + Release)

Complete pipeline that runs tests and then creates automatic releases:

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [ "master" ]
  pull_request:
    branches: [ "master" ]

jobs:
  build-and-test:
    uses: adnvilla/gha-toolkit/.github/workflows/go.yml@v1.0.0
    with:
      go-version: '1.24'
      postgres-version: '15'
```

```yaml
# .github/workflows/release.yml
name: Release

on:
  workflow_run:
    workflows: ["CI"]
    types:
      - completed
    branches:
      - master

jobs:
  semantic-release:
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    uses: adnvilla/gha-toolkit/.github/workflows/release.yml@v1.0.0
    permissions:
      contents: write
    with:
      node-version: '20'
      dry-run: false
    secrets:
      github-token: ${{ secrets.GITHUB_TOKEN }}
```

## Example 4: Multiple Jobs in CI

If you need to run multiple jobs before release:

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [ "master" ]
  pull_request:
    branches: [ "master" ]

jobs:
  test:
    uses: adnvilla/gha-toolkit/.github/workflows/go.yml@v1.0.0
    with:
      go-version: '1.24'
  
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-go@v4
        with:
          go-version: '1.24'
      - name: golangci-lint
        uses: golangci/golangci-lint-action@v3

  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run Gosec Security Scanner
        uses: securego/gosec@master
        with:
          args: './...'
```

## Example 5: Dry-Run Release

To test the release process without publishing:

```yaml
# .github/workflows/test-release.yml
name: Test Release

on:
  workflow_dispatch:  # Run manually

jobs:
  test-release:
    uses: adnvilla/gha-toolkit/.github/workflows/release.yml@v1.0.0
    permissions:
      contents: write
    with:
      dry-run: true
    secrets:
      github-token: ${{ secrets.GITHUB_TOKEN }}
```

## Example 6: Use a Specific Version of the Workflow

Instead of using `@master`, you can use tags for greater stability:

```yaml
jobs:
  build:
    uses: adnvilla/gha-toolkit/.github/workflows/go.yml@v1.0.0
    with:
      go-version: '1.24'
```

## Example 7: Multiple Go Versions (Matrix)

If you want to test with multiple Go versions:

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [ "master" ]
  pull_request:
    branches: [ "master" ]

jobs:
  test:
    strategy:
      matrix:
        go-version: ['1.22', '1.23', '1.24']
    uses: adnvilla/gha-toolkit/.github/workflows/go.yml@v1.0.0
    with:
      go-version: ${{ matrix.go-version }}
```

## Important Notes

### Permissions

Make sure the calling workflow has the necessary permissions:

```yaml
permissions:
  contents: write  # For semantic-release
```

### Secrets

Secrets must be passed explicitly:

```yaml
secrets:
  github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Semantic Release Configuration

Don't forget to add `.releaserc.json` to your project. See `.releaserc.json.example` for reference.

### Conventional Commits

Examples of commits that generate releases:

```bash
# Generates PATCH (1.0.0 -> 1.0.1)
git commit -m "fix: correct validation error"

# Generates MINOR (1.0.0 -> 1.1.0)
git commit -m "feat: add new feature"

# Generates MAJOR (1.0.0 -> 2.0.0)
git commit -m "feat!: breaking compatibility change

BREAKING CHANGE: The API has completely changed"

# Does not generate release
git commit -m "chore: update dependencies"
git commit -m "docs: improve documentation"
```
