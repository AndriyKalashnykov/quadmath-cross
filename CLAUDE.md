# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Docker-based cross-compilation project for building 128-bit floating-point (quadruple precision) C/C++ programs across multiple CPU architectures (amd64, arm64, arm, armel). Uses GCC cross-compilation toolchains inside Docker with QEMU for multi-arch emulation.

## Build Commands

All builds are Docker-based. There is no local compilation pipeline outside of Docker (except `make cross-compile` which requires local cross-compilers).

```bash
make help              # List all targets
make build             # Build amd64 builder image, then local runtime image (the main build)
make image-run         # Run arm64 runtime image interactively
make image-prune       # Docker system prune + buildx prune
make setup-binfmt      # Setup Docker binfmt for arm64 emulation on x86_64 (one-time)
make cross-compile     # Cross-compile helloworld.c for x86_64, arm, aarch64 (requires local cross-compilers)
make lint              # Lint all Dockerfiles with hadolint
make ci                # Full local CI pipeline (lint + build)
make ci-run            # Run GitHub Actions workflow locally via act
make version           # Print current git tag version
make release           # Interactive: create and push a new git tag
make renovate-validate # Validate Renovate configuration
```

## Architecture

### Two-Stage Docker Build

1. **Builder image** (`Dockerfile.builder`) - Ubuntu Noble (amd64) with full cross-compilation toolchain:
   - GCC 14 with cross-compilers for aarch64, arm, armhf
   - Math libraries: libquadmath, gfortran, lapack, blas, atlas
   - Boost multiprecision for C++ float128 support
   - QEMU user-static for running cross-compiled binaries
   - Compiles all C/C++ sources into statically-linked binaries at build time

2. **Runtime image** (`Dockerfile.runtime` / `Dockerfile.runtime.local`) - Alpine with only the compiled binaries:
   - `Dockerfile.runtime` pulls builder from `ghcr.io` (used in CI)
   - `Dockerfile.runtime.local` pulls builder from local Docker (used with `make build`)

3. **Simple GCC image** (`Dockerfile`) - gcc:15 based, compiles `hello.cpp` only (no cross-compilation)

### Build Artifacts (produced inside builder)

| Binary | Source | Compiler | Notes |
|--------|--------|----------|-------|
| `hello-x86_64` | hello.c | x86_64-linux-gnu-gcc | Static, linked with lapack/blas/gfortran/quadmath |
| `hello-arm64` | hello.c | aarch64-linux-gnu-gcc | Static cross-compiled |
| `qm-x86_64` | quadmath.cpp | x86_64-linux-gnu-g++ | Boost multiprecision float128 |
| `float128-x86_64` | float128_example.cpp | x86_64-linux-gnu-g++ | Boost float128 extended example |

Additional source files (`quadmath.c`, `hello.cpp`) exist in the repo but are not compiled in the builder image.

## CI/CD

### Main workflow: `.github/workflows/ci.yml`

- **On push/PR**: `docker-image-test` job runs `make build` to verify the build works
- **On tag push (v*)**: additionally builds and pushes both builder and runtime images to `ghcr.io/andriykalashnykov/quadmath-cross` with semver tags
- Runtime image is multi-platform: `linux/arm64,linux/amd64`
- Uses `secrets.GITHUB_TOKEN` for ghcr.io authentication

### Cleanup workflow: `.github/workflows/cleanup-runs.yml`

- Runs weekly (Sundays at 00:00 UTC) and on manual dispatch
- Deletes workflow runs older than 7 days, keeps minimum 5 runs

## Key Details

- Version tracked in `version.txt` and git tags (current: v0.0.2)
- GCC version is parameterized via `ARG GCC_VERSION=14` in Dockerfile.builder
- All C binaries are statically linked (`-static`) for portability across architectures
- Renovate manages dependency updates with branch automerge enabled

## Upgrade Backlog

Items identified during upgrade analysis (2026-04-03) that are not immediately actionable:

- [x] Add `.dockerignore` to exclude `.git/`, `*.md`, `LICENSE`, `helloworld-*`, `.idea/`, `.vscode/` (done 2026-04-03)
- [x] Add `.hadolint.yaml` with intentional rule ignores for `DL3008`, `DL3015` (done 2026-04-03)
- [x] Pin `tonistiigi/binfmt` image in Makefile `setup-binfmt` target to `tonistiigi/binfmt:qemu-v10.2.1` (done 2026-04-03)
- [ ] `ARG GCC_VERSION=14` in Dockerfile.builder is not tracked by Renovate — manually update when Ubuntu Noble ships GCC 15
- [x] Pin CI runner to `ubuntu-24.04` instead of `ubuntu-latest` (done 2026-04-03)

## Skills

Use the following skills when working on related files:

| File(s) | Skill |
|---------|-------|
| `Makefile` | `/makefile` |
| `renovate.json` | `/renovate` |
| `README.md` | `/readme` |
| `.github/workflows/*.yml` | `/ci-workflow` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
