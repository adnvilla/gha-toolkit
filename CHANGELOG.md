## [2.2.0](https://github.com/adnvilla/gha-toolkit/compare/v2.1.0...v2.2.0) (2026-09-19)

### 🚀 Features

* add chart security context overrides ([819673b](https://github.com/adnvilla/gha-toolkit/commit/819673bc7d8cc7eb20bada07ecd0beeb24f29bdd))

## [2.1.0](https://github.com/adnvilla/gha-toolkit/compare/v2.0.1...v2.1.0) (2026-09-19)

### 🚀 Features

* add immutable image digest outputs ([6ead078](https://github.com/adnvilla/gha-toolkit/commit/6ead0782d8b5b0c1c8a167d615926d8df2243918))

### 🐛 Bug Fixes

* accept normalized Docker Hub digests ([2c8d28f](https://github.com/adnvilla/gha-toolkit/commit/2c8d28f909930481d2a8f565f5724a3e0ccf1223))
* keep job image tag fallback ([104c75c](https://github.com/adnvilla/gha-toolkit/commit/104c75c2693a6cab6b4a04b444d55c6f9968e426))
* keep rollout image tag fallback ([4c3b431](https://github.com/adnvilla/gha-toolkit/commit/4c3b43132708e276024247bb3b7fa4b9b1b3d40b))
* omit digest keys for local charts ([146dd46](https://github.com/adnvilla/gha-toolkit/commit/146dd46cec7201245f66eb8f7a6f3d055cd0c289))
* preserve blue-green slot digest overrides ([13b8b18](https://github.com/adnvilla/gha-toolkit/commit/13b8b188c416a6a06b7fa0426f918f3515053402))
* preserve digest image fallbacks ([8a2a488](https://github.com/adnvilla/gha-toolkit/commit/8a2a488b19ee329af12e1ec55acfbf1174bdd334))
* preserve digest image overrides ([ba5b925](https://github.com/adnvilla/gha-toolkit/commit/ba5b92589cf6b249691d3b83f5f431102d1173d3))
* preserve local chart digest references ([a620093](https://github.com/adnvilla/gha-toolkit/commit/a620093ce4a7b1d4802e19124c8ce00130b5ce52))
* preserve rollout image tag fallback ([e9df0c4](https://github.com/adnvilla/gha-toolkit/commit/e9df0c43d638a46f4186d40e2b0a56baf4ac6122))

### 📚 Documentation

* cover immutable image digest outputs ([da67dc5](https://github.com/adnvilla/gha-toolkit/commit/da67dc58d148074be7fc8bf2da4157ea3bd95b48))

## [2.0.1](https://github.com/adnvilla/gha-toolkit/compare/v2.0.0...v2.0.1) (2026-09-19)

### 🐛 Bug Fixes

* lock semantic release toolchain ([8cd8d0c](https://github.com/adnvilla/gha-toolkit/commit/8cd8d0c67180aef3af9cbd7bbc1d7fda51c7553a))

## [2.0.0](https://github.com/adnvilla/gha-toolkit/compare/v1.9.3...v2.0.0) (2026-09-18)

### ⚠ BREAKING CHANGES

* reusable workflows now cancel after their documented timeout-minutes default instead of GitHub Actions implicit 360-minute job limit.

### 🚀 Features

* bound workflow execution time ([19e42f7](https://github.com/adnvilla/gha-toolkit/commit/19e42f7555366231d5a2f2dbe68df61a7e67d4bc))
* classify workflow timeout defaults as breaking ([7ce28ce](https://github.com/adnvilla/gha-toolkit/commit/7ce28ce04c7bf549ef581c3f27af94be8f98dfca))

### 🐛 Bug Fixes

* preserve k8s job timeout diagnostics ([489fe05](https://github.com/adnvilla/gha-toolkit/commit/489fe050749b00e2ac4bd2f96405d04edf040a7b))

### 📚 Documentation

* enforce reusable workflow timeout contract ([6acfc8f](https://github.com/adnvilla/gha-toolkit/commit/6acfc8fdc5bf20ef7ca09da39e1ac1a46735abca))

## [1.9.3](https://github.com/adnvilla/gha-toolkit/compare/v1.9.2...v1.9.3) (2026-09-18)

### 🐛 Bug Fixes

* declare least-privilege workflow permissions ([2d394ba](https://github.com/adnvilla/gha-toolkit/commit/2d394ba3a694c3c9f97fc9b948ada399825a24f3))
* preserve release smoke permissions ([63f515a](https://github.com/adnvilla/gha-toolkit/commit/63f515a2831e04763bbe115990483727e9992cb6))

## [1.9.2](https://github.com/adnvilla/gha-toolkit/compare/v1.9.1...v1.9.2) (2026-09-18)

### 🐛 Bug Fixes

* isolate workflow inputs from run scripts ([1e81fc2](https://github.com/adnvilla/gha-toolkit/commit/1e81fc21ee1e0a9f7a2ce38b8fbedb18811ee801))

### 📚 Documentation

* clarify workflow run expression guard ([b518526](https://github.com/adnvilla/gha-toolkit/commit/b518526850f61896e92cfc56bf91668ed1c52789))

## [1.9.1](https://github.com/adnvilla/gha-toolkit/compare/v1.9.0...v1.9.1) (2026-09-18)

### 🐛 Bug Fixes

* isolate Kubernetes workflow contexts ([58bd27e](https://github.com/adnvilla/gha-toolkit/commit/58bd27e3f7565d95abad14576903bfa56cf4b332))

## [1.9.0](https://github.com/adnvilla/gha-toolkit/compare/v1.8.0...v1.9.0) (2026-09-16)

### 🚀 Features

* add Python uv workflow ([6035d9f](https://github.com/adnvilla/gha-toolkit/commit/6035d9ff7fc9a12dd58dd2841460b44a682fcd22))

### 🐛 Bug Fixes

* lock Python uv dependencies ([2f415e3](https://github.com/adnvilla/gha-toolkit/commit/2f415e3e69cf1f309c9d4b8996777c407a9435ed))

## [1.8.0](https://github.com/adnvilla/gha-toolkit/compare/v1.7.1...v1.8.0) (2026-09-14)

### 🚀 Features

* compose ingress.host from prefix and cluster domain ([08aa28a](https://github.com/adnvilla/gha-toolkit/commit/08aa28a39749a58e88b479d3d0034d96483411a6)), closes [#43](https://github.com/adnvilla/gha-toolkit/issues/43)

## [1.7.1](https://github.com/adnvilla/gha-toolkit/compare/v1.7.0...v1.7.1) (2026-09-13)

### 🐛 Bug Fixes

* release breaking changes as a major version ([ca88f1f](https://github.com/adnvilla/gha-toolkit/commit/ca88f1fdc24b60dc856fce2fa88782592fa9f312))

### 📚 Documentation

* correct why releaseRules must carry a breaking rule ([a357fce](https://github.com/adnvilla/gha-toolkit/commit/a357fce781a0d2a884047d01a50b997e0f56b412))

## [1.7.0](https://github.com/adnvilla/gha-toolkit/compare/v1.6.6...v1.7.0) (2026-09-13)

### ⚠ BREAKING CHANGES

* in charts/app, strategy.mode=blueGreen previously rendered no
Ingress, HPA or PodDisruptionBudget at all. Those values are still default-off,
but a release that already sets ingress.enabled, autoscaling.enabled or
podDisruptionBudget.enabled together with blueGreen will now get those resources
created. Under an HPA the active slot's Deployment also stops setting replicas,
handing the replica count to the autoscaler. Review such values files before
upgrading the pinned workflow ref.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Lonz9bBFZDT4UR2wE4YuQV

### 🚀 Features

* add k8s-job.yml and extend blue/green to HTTP apps ([eb7363d](https://github.com/adnvilla/gha-toolkit/commit/eb7363db8bd462bd2ff7d67d5b02333ae3a5277f))

### 🐛 Bug Fixes

* address Codex review findings on jobs and CronJobs ([163c2c7](https://github.com/adnvilla/gha-toolkit/commit/163c2c79cb5f1bba553a580aa6d214a111babd64))

## [1.6.6](https://github.com/adnvilla/gha-toolkit/compare/v1.6.5...v1.6.6) (2026-07-27)

### 🐛 Bug Fixes

* migrate workflow actions to Node 24 ([97324d4](https://github.com/adnvilla/gha-toolkit/commit/97324d4b55dc35d1b83ac5247624254e6d1aabd0))

## [1.6.5](https://github.com/adnvilla/gha-toolkit/compare/v1.6.4...v1.6.5) (2026-07-27)

### 🐛 Bug Fixes

* handle untagged Kubernetes image references ([#39](https://github.com/adnvilla/gha-toolkit/issues/39)) ([37f93d5](https://github.com/adnvilla/gha-toolkit/commit/37f93d5c6eb94f9a20de7b8543a0e7cfd764f726)), closes [#33](https://github.com/adnvilla/gha-toolkit/issues/33)

## [1.6.4](https://github.com/adnvilla/gha-toolkit/compare/v1.6.3...v1.6.4) (2026-07-27)

### 📚 Documentation

* point agents at .cursor/install.sh for the harness ([a85a6b9](https://github.com/adnvilla/gha-toolkit/commit/a85a6b9f864098bb6887ba6873e0973cb649677d)), closes [#35](https://github.com/adnvilla/gha-toolkit/issues/35) [#36](https://github.com/adnvilla/gha-toolkit/issues/36)

## [1.6.3](https://github.com/adnvilla/gha-toolkit/compare/v1.6.2...v1.6.3) (2026-07-27)

### 🐛 Bug Fixes

* restore release notes by pinning the changelog preset to ^9 ([#37](https://github.com/adnvilla/gha-toolkit/issues/37)) ([c1ec1aa](https://github.com/adnvilla/gha-toolkit/commit/c1ec1aa3b171f049e6135b5f466d1270defd9469))

## [1.6.2](https://github.com/adnvilla/gha-toolkit/compare/v1.6.1...v1.6.2) (2026-07-26)

## [1.6.1](https://github.com/adnvilla/gha-toolkit/compare/v1.6.0...v1.6.1) (2026-07-26)

## [1.6.0](https://github.com/adnvilla/gha-toolkit/compare/v1.5.0...v1.6.0) (2026-07-25)

## [1.5.0](https://github.com/adnvilla/gha-toolkit/compare/v1.4.1...v1.5.0) (2026-07-20)

## [1.4.1](https://github.com/adnvilla/gha-toolkit/compare/v1.4.0...v1.4.1) (2026-07-20)

## [1.4.0](https://github.com/adnvilla/gha-toolkit/compare/v1.3.5...v1.4.0) (2026-07-20)

## [1.3.5](https://github.com/adnvilla/gha-toolkit/compare/v1.3.4...v1.3.5) (2026-07-19)

### 🐛 Bug Fixes

* call release.yml from auto-release instead of duplicating it ([a738565](https://github.com/adnvilla/gha-toolkit/commit/a738565dd5e7f65c9ee5fd356e8cd0c39d6ec65a)), closes [#9](https://github.com/adnvilla/gha-toolkit/issues/9)

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
