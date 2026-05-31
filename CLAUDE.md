# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Docker-based cross-compilation project for building 128-bit floating-point (quadruple precision) C/C++ programs across multiple CPU architectures (amd64, arm64, arm, armel). Uses GCC cross-compilation toolchains inside Docker with QEMU for multi-arch emulation.

## Build Commands

All builds are Docker-based. There is no local compilation pipeline outside of Docker (except `make cross-compile` which requires local cross-compilers).

```bash
make help              # List all targets
make deps              # Check required system dependencies (docker, git)
make build             # Build amd64 builder image, then local runtime image (the main build)
make image-run         # Run arm64 runtime image interactively
make image-prune       # Docker system prune + buildx prune
make clean             # Remove build artifacts
make setup-binfmt      # Setup Docker binfmt for arm64 emulation on x86_64 (one-time)
make cross-compile     # Cross-compile helloworld.c for x86_64, arm, aarch64 (requires local cross-compilers)
make lint              # Lint all Dockerfiles with hadolint
make trivy-fs          # Scan repo for vulnerabilities + secrets with trivy
make smoke             # Run every compiled binary + assert output (arm64 via QEMU)
make ci                # Full local CI pipeline (lint + trivy-fs + build + smoke)
make ci-run            # Run GitHub Actions workflow locally via act
make version           # Print current git tag version
make release           # Interactive: create and push a new git tag
make tag-delete        # Interactive: delete a tag locally and from origin (destructive)
make renovate-validate # Validate Renovate configuration
```

## Architecture

### Two-Stage Docker Build

1. **Builder image** (`Dockerfile.builder`) - Ubuntu Noble (amd64) with full cross-compilation toolchain:
   - GCC 14 with cross-compilers for aarch64, arm, armhf
   - Math libraries: libquadmath, gfortran, lapack, blas, atlas
   - Boost multiprecision for C++ float128 support
   - QEMU user-static for running cross-compiled binaries
   - cppcheck static analysis runs before compilation (own sources only; `float128_example.cpp` excluded as third-party Boost example)
   - Compiles all C/C++ sources into statically-linked binaries at build time
   - **Behavioral verification**: after compilation, every binary is executed and its output asserted (arm64 via `qemu-aarch64-static`, no binfmt needed since binaries are static). A broken artifact fails the image build. `make smoke` repeats these assertions against the built images and is folded into `make ci`.

2. **Runtime image** (`Dockerfile.runtime` / `Dockerfile.runtime.local`) - Alpine with only the compiled binaries. Both take an `ARG BUILDER_IMAGE` so the builder reference is supplied at build time:
   - `Dockerfile.runtime` (CI): the `docker-image-runtime` job passes `BUILDER_IMAGE=ghcr.io/<owner>/quadmath-cross:${tag}-builder`, so the runtime always pulls the exact builder for the release being built.
   - `Dockerfile.runtime.local` (`make build`): `make build` passes the just-built local `docker.io/$(DOCKER_ORG)/quadmath-cross:<tag>-builder`.
   - The `ARG` default in each file is only a fallback for a bare `docker build` without `--build-arg`.

### Two registries (local vs CI)

- **Local** (`make build`): tags images `docker.io/$(DOCKER_ORG)/quadmath-cross:<tag>-builder` / `-runtime` (overridable via `DOCKER_REGISTRY` / `DOCKER_ORG`); never touches ghcr.io.
- **CI** (tag push): publishes both images to `ghcr.io/<owner>/quadmath-cross`, Trivy-scanned + smoke-tested and cosign-signed.

Because the builder reference is a build-arg derived from the release tag, there is **no manual `FROM`-tag bump** when cutting a release.

### Source Files

| File | Purpose | Compiled in builder? |
|------|---------|---------------------|
| `hello.c` | Cross-compilation smoke test (prints argc/argv) | Yes — x86_64 + arm64 |
| `quadmath.cpp` | `__float128` arithmetic via GCC libquadmath C API (`sqrtq`, `quadmath_snprintf`) | Yes — x86_64 |
| `float128_example.cpp` | Boost multiprecision `float128` demo (constants, precision, `constexpr`) — from Boost.Math examples | Yes — x86_64 |
| `helloworld.c` | Minimal printf — used only by local `make cross-compile`, not by Docker | No |

### Build Artifacts (produced inside builder)

| Binary | Source | Compiler | Notes |
|--------|--------|----------|-------|
| `hello-x86_64` | hello.c | x86_64-linux-gnu-gcc | Static cross-compilation smoke test |
| `hello-arm64` | hello.c | aarch64-linux-gnu-gcc | Static cross-compiled to arm64 |
| `qm-x86_64` | quadmath.cpp | x86_64-linux-gnu-g++ | `sqrt(2)` via `__float128` + libquadmath C API |
| `float128-x86_64` | float128_example.cpp | x86_64-linux-gnu-g++ | Boost multiprecision float128 extended example |

## CI/CD

### Main workflow: `.github/workflows/ci.yml`

- **`changes`** (all events): `dorny/paths-filter` skips the build on docs-only changes (`*.md`, `LICENSE`).
- **On push/PR/workflow_call**: `docker-image-test` runs `make ci` (hadolint + Trivy filesystem scan + builder/runtime build) — gated on `changes` (or any tag).
- **On tag push (v*)**: three jobs run in sequence after `docker-image-test`:
  1. `docker-image-builder` — builds + pushes the amd64 builder image to ghcr.io, then cosign-signs it (`id-token: write`).
  2. `docker-image-runtime` — builds the runtime image (amd64) → **Trivy image scan** (CRITICAL/HIGH blocking) → **smoke test** (`qm-x86_64` prints `sqrt(2)`) → pushes multi-platform (`linux/arm64,linux/amd64`) → cosign-signs the digest.
- **`ci-pass`** (all events): aggregator that fails if a required job failed/cancelled — the intended single required status check.
- Uses `secrets.GITHUB_TOKEN` for ghcr.io auth; cosign uses keyless OIDC (Sigstore).
- The builder image is **not** CVE-gated (it is a dev-toolchain image with expected `-dev`/compiler CVEs that never reach the Alpine runtime); the runtime image — the artifact users run — is the gated one.

### Cleanup workflow: `.github/workflows/cleanup-runs.yml`

- Runs weekly (Sundays at 00:00 UTC) and on manual dispatch
- Deletes workflow runs older than 7 days, keeps minimum 5 runs

## Key Details

- Version tracked in `version.txt` and git tags (current: v0.0.2)
- GCC version is parameterized via `ARG GCC_VERSION=14` in Dockerfile.builder
- All C binaries are statically linked (`-static`) for portability across architectures
- Renovate manages dependency updates with PR automerge (squash) enabled
- **Version manager**: mise (`.mise.toml`) provides Node.js (used only by `make renovate-validate`); auto-installed tools (hadolint, act, trivy) live in `~/.local/bin` (no sudo), which the Makefile adds to `PATH`
- **Boost** is consumed header-only via apt (`libboost-dev`); `float128_example.cpp` is a frozen third-party Boost.Math example, so no Boost version bump is needed unless new Boost features are required

## Upgrade Backlog

- [ ] `ARG GCC_VERSION=14` in Dockerfile.builder is not tracked by Renovate — manually update when Ubuntu Noble ships GCC 15 (verified 2026-04-03: gcc-15 not yet in Noble repos)

## Skills

Use the following skills when working on related files:

| File(s) | Skill |
|---------|-------|
| `Makefile` | `/makefile` |
| `renovate.json` | `/renovate` |
| `README.md` | `/readme` |
| `.github/workflows/*.{yml,yaml}` | `/ci-workflow` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
