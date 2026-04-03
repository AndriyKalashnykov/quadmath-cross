[![CI](https://github.com/AndriyKalashnykov/quadmath-cross/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AndriyKalashnykov/quadmath-cross/actions/workflows/ci.yml)
[![Hits](https://hits.sh/github.com/AndriyKalashnykov/quadmath-cross.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/quadmath-cross/)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)
[![Renovate enabled](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://app.renovatebot.com/dashboard#github/AndriyKalashnykov/quadmath-cross)

# Quadmath Cross-Compilation

Docker-based cross-compilation environment for building 128-bit floating-point (quadruple precision) C/C++ programs across multiple CPU architectures (amd64, arm64, arm, armel). Uses GCC 14 cross-compilation toolchains inside Docker with QEMU for multi-arch emulation, Boost multiprecision for C++ float128 support, and publishes multi-platform images to GitHub Container Registry.

## Quick Start

```bash
make setup-binfmt  # setup QEMU binfmt for arm64 emulation (one-time)
make build         # build amd64 builder image + runtime image
make lint          # lint all Dockerfiles with hadolint
make image-run     # run arm64 runtime image interactively
```

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [GNU Make](https://www.gnu.org/software/make/) | 3.81+ | Build orchestration |
| [Docker](https://www.docker.com/) | latest | Container builds with Buildx |
| [Git](https://git-scm.com/) | 2.0+ | Version control and tagging |
| [hadolint](https://github.com/hadolint/hadolint) | 2.14.0 | Dockerfile linting (auto-installed by `make lint`) |
| [act](https://github.com/nektos/act) | 0.2.87 | Run GitHub Actions locally (auto-installed by `make ci-run`) |

## Available Make Targets

Run `make help` to see all available targets.

### Build & Run

| Target | Description |
|--------|-------------|
| `make build` | Build amd64 builder image and runtime image |
| `make image-run` | Run arm64 runtime image interactively |
| `make image-prune` | Docker system prune and buildx prune |
| `make cross-compile` | Cross-compile helloworld.c for x86_64, arm, and aarch64 |
| `make setup-binfmt` | Setup Docker binfmt support for arm64 emulation on x86_64 |
| `make clean` | Remove build artifacts |
| `make deps` | Check required system dependencies |

### Code Quality

| Target | Description |
|--------|-------------|
| `make lint` | Lint all Dockerfiles with [hadolint](https://github.com/hadolint/hadolint) |

### Dependencies

| Target | Description |
|--------|-------------|
| `make deps-hadolint` | Install [hadolint](https://github.com/hadolint/hadolint) for Dockerfile linting |
| `make deps-act` | Install [act](https://github.com/nektos/act) for running GitHub Actions locally |
| `make renovate-bootstrap` | Install nvm and npm for Renovate validation |

### CI

| Target | Description |
|--------|-------------|
| `make ci` | Full local CI pipeline (lint + build) |
| `make ci-run` | Run GitHub Actions workflow locally using [act](https://github.com/nektos/act) |

### Utilities

| Target | Description |
|--------|-------------|
| `make version` | Print current version (tag) |
| `make release` | Create and push a new tag |
| `make tag-delete` | Delete a tag locally and from origin (destructive, requires confirmation) |
| `make renovate-validate` | Validate Renovate configuration |

## CI/CD

GitHub Actions runs on every push to `main`, tags `v*`, pull requests, and `workflow_call`.

| Job | Triggers | Description |
|-----|----------|-------------|
| **docker-image-test** | push, PR, workflow_call | Lints Dockerfiles and builds builder + runtime images to verify the build works |
| **docker-image-builder** | tag push (v*) | Builds and pushes amd64 builder image to ghcr.io |
| **docker-image-runtime** | tag push (v*) | Builds and pushes multi-platform (arm64 + amd64) runtime image to ghcr.io |

A [cleanup workflow](https://github.com/AndriyKalashnykov/quadmath-cross/actions/workflows/cleanup-runs.yml) runs weekly to prune workflow runs older than 7 days.

[Renovate](https://docs.renovatebot.com/) keeps dependencies up to date with platform automerge enabled.

## License

[MIT](LICENSE)
