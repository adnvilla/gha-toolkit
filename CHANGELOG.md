## [1.3.4](https://github.com/adnvilla/gha-toolkit/compare/v1.3.3...v1.3.4) (2026-07-19)

### 📚 Documentation

* add go-base.yml to README Available Workflows ([fbdbdfc](https://github.com/adnvilla/gha-toolkit/commit/fbdbdfc40b85e3ebc3e65aaa90f733182ecef7a2)), closes [#10](https://github.com/adnvilla/gha-toolkit/issues/10)

## [1.3.3](https://github.com/adnvilla/gha-toolkit/compare/v1.3.2...v1.3.3) (2026-07-19)

### 🐛 Bug Fixes

* add registry authentication to docker-build-push.yml ([4bfd516](https://github.com/adnvilla/gha-toolkit/commit/4bfd5169654cec78af1ec75a91367ac3e1f360ee)), closes [#8](https://github.com/adnvilla/gha-toolkit/issues/8)

## [1.3.2](https://github.com/adnvilla/gha-toolkit/compare/v1.3.1...v1.3.2) (2026-07-19)

### 🐛 Bug Fixes

* make k8s-deploy dry-run genuinely offline with helm template ([07d0e5a](https://github.com/adnvilla/gha-toolkit/commit/07d0e5a7f0ad7b33aa49bcbf614e8104c639c091)), closes [#16](https://github.com/adnvilla/gha-toolkit/issues/16)

## [1.3.1](https://github.com/adnvilla/gha-toolkit/compare/v1.3.0...v1.3.1) (2026-07-19)

### 🐛 Bug Fixes

* extend validate-doc-pins guard to cover ENVIRONMENTS.md ([cc5a741](https://github.com/adnvilla/gha-toolkit/commit/cc5a741caeb803398ff4bc6bf409c242c31d8654)), closes [#7](https://github.com/adnvilla/gha-toolkit/issues/7)

## [1.3.0](https://github.com/adnvilla/gha-toolkit/compare/v1.2.1...v1.3.0) (2026-07-19)

### 🚀 Features

* add GitHub Environment support to k8s-deploy.yml (staging/production) ([70e840e](https://github.com/adnvilla/gha-toolkit/commit/70e840e2156ce6061ac95989cae3ef8fefa48559))

## [1.2.1](https://github.com/adnvilla/gha-toolkit/compare/v1.2.0...v1.2.1) (2026-07-19)

### 🐛 Bug Fixes

* build/deploy the exact triggering ref and auto-resolve chart version ([1aadae3](https://github.com/adnvilla/gha-toolkit/commit/1aadae3a9286930655b0afef3c2a129ba7061226)), closes [#4](https://github.com/adnvilla/gha-toolkit/issues/4) [#5](https://github.com/adnvilla/gha-toolkit/issues/5) [#6](https://github.com/adnvilla/gha-toolkit/issues/6)

### 📚 Documentation

* fix stale [@v1](https://github.com/v1).0.0 pins in Example 8, add doc-pin CI guard ([b7760fc](https://github.com/adnvilla/gha-toolkit/commit/b7760fc8e2eecd239a6503a776babeb2975d3c3b)), closes [#7](https://github.com/adnvilla/gha-toolkit/issues/7)

## [1.2.0](https://github.com/adnvilla/gha-toolkit/compare/v1.1.1...v1.2.0) (2026-07-19)

### 🚀 Features

* add Node CI, Docker build/push, and Helm-based Kubernetes deploy workflows ([1a7020f](https://github.com/adnvilla/gha-toolkit/commit/1a7020f043be616c2761a039288f7c488563f423))

### 📚 Documentation

* add CLAUDE.md repo guidance for Claude Code ([2c84fd4](https://github.com/adnvilla/gha-toolkit/commit/2c84fd4785a00464f1af49921fe58f62338863eb))
* sync release-rule docs with .releaserc.json ([e4137d4](https://github.com/adnvilla/gha-toolkit/commit/e4137d493b54bcbcd75f8a1d7c85abc9276a81bb))

## [1.1.1](https://github.com/adnvilla/gha-toolkit/compare/v1.1.0...v1.1.1) (2025-10-14)

### ♻️ Code Refactoring

* remove composite actions for Go build, test, and setup; integrate directly into workflows ([#3](https://github.com/adnvilla/gha-toolkit/issues/3)) ([b668582](https://github.com/adnvilla/gha-toolkit/commit/b6685820fe7d342dda2e3f1675f4bcd723017652))

## [1.1.0](https://github.com/adnvilla/gha-toolkit/compare/v1.0.0...v1.1.0) (2025-10-14)

### 🚀 Features

* add composite actions for building, testing, and setting up Go environment ([#2](https://github.com/adnvilla/gha-toolkit/issues/2)) ([dcd1504](https://github.com/adnvilla/gha-toolkit/commit/dcd15048593977a5f898ef127fb24ae82dd78efd))

## 1.0.0 (2025-10-13)

### 🚀 Features

* add initial implementation of reusable workflows toolkit ([#1](https://github.com/adnvilla/gha-toolkit/issues/1)) ([d8ba90d](https://github.com/adnvilla/gha-toolkit/commit/d8ba90d463bbb3bef06b9d1a21516ab9009dc81e))

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Initial Release
- Reusable workflows toolkit for GitHub Actions
- Go build and test workflow
- Semantic release workflow
- CI/CD for the toolkit itself
- Comprehensive documentation
