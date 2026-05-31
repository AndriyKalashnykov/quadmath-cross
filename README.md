[![CI](https://github.com/AndriyKalashnykov/quadmath-cross/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AndriyKalashnykov/quadmath-cross/actions/workflows/ci.yml)
[![Hits](https://hits.sh/github.com/AndriyKalashnykov/quadmath-cross.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/quadmath-cross/)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)
[![Renovate enabled](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://app.renovatebot.com/dashboard#github/AndriyKalashnykov/quadmath-cross)

# Quadmath Cross-Compilation

**quadmath-cross** cross-compiles statically-linked C/C++ programs that exercise 128-bit
quadruple-precision floating point (`__float128` via **GCC libquadmath**, and **Boost.Multiprecision**
`float128`) for amd64, arm64, arm, and armel. The **build surface** is a two-stage Docker pipeline — a
**GCC 14 + QEMU** builder that compiles and verifies the binaries (cppcheck, plus run-and-assert of every
artifact including arm64 under QEMU) feeding a minimal **Alpine runtime** image — while the **delivery
surface** adds hadolint + Trivy scanning, **cosign** keyless signing, and Renovate-managed multi-platform
publishing to **GitHub Container Registry**.

## Tech Stack

| Component | Technology |
|-----------|------------|
| Cross toolchain | GCC 14 (x86_64, aarch64, arm, armhf cross-compilers) |
| Quad-precision math | libquadmath / `__float128`, Boost.Multiprecision `float128` |
| Multi-arch emulation | QEMU user-static + binfmt |
| Builder base | Ubuntu 24.04 (Noble), digest-pinned |
| Runtime base | Alpine 3.23, digest-pinned |
| Static analysis | cppcheck (sources), hadolint (Dockerfiles), Trivy (filesystem + image) |
| Supply chain | cosign keyless signing (Sigstore), GitHub Actions, GHCR |
| Tooling | GNU Make, mise (Node.js for Renovate), act |
| Dependency updates | Renovate |

## Quick Start

```bash
make setup-binfmt  # set up QEMU binfmt for arm64 emulation (one-time)
make build         # build amd64 builder image + local runtime image
make image-run     # run the arm64 runtime image interactively
make ci            # full local pipeline: lint + scan + build + binary smoke test
```

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [GNU Make](https://www.gnu.org/software/make/) | 3.81+ | Build orchestration |
| [Docker](https://www.docker.com/) | latest | Container builds with Buildx |
| [Git](https://git-scm.com/) | 2.0+ | Version control and tagging |
| [hadolint](https://github.com/hadolint/hadolint) | 2.14.0 | Dockerfile linting (auto-installed by `make lint`) |
| [Trivy](https://trivy.dev/) | 0.70.0 | Filesystem CVE/secret scanning (auto-installed by `make trivy-fs`) |
| [act](https://github.com/nektos/act) | 0.2.88 | Run GitHub Actions locally (auto-installed by `make ci-run`) |
| [mise](https://mise.jdx.dev/) | latest | Provides Node.js (`.mise.toml`) for `make renovate-validate` (auto-installed) |

Auto-installed tools land in `~/.local/bin` (no `sudo`); make sure it is on your `PATH`.

## Architecture

### Two-stage Docker build

1. **Builder image** (`Dockerfile.builder`) — Ubuntu Noble (amd64) with the full
   cross-compilation toolchain (GCC 14 for x86_64/aarch64/arm/armhf, libquadmath,
   gfortran, LAPACK/BLAS/ATLAS, Boost). It runs **cppcheck** on the project's own
   sources, then compiles every C/C++ source into a statically-linked binary.
2. **Runtime image** (`Dockerfile.runtime` for CI, `Dockerfile.runtime.local` for
   `make build`) — Alpine carrying **only** the compiled binaries. The builder image
   reference is a build-arg (`BUILDER_IMAGE`), so CI pulls the exact `<tag>-builder`
   image for the release being built — no manual version bumping.

### Binary verification

Compilation alone proves the binaries link; it does not prove they *run*. Two
layers assert behavior:

- **Build time** (`Dockerfile.builder`): immediately after compilation, every
  binary is executed and its output asserted — the arm64 binary via
  `qemu-aarch64-static` (statically linked, no binfmt needed). A broken or
  incorrect artifact fails the image build.
- **`make smoke`** (folded into `make ci`): runs the binaries out of the built
  images and asserts output (√2 from `qm-x86_64`, `boost::float128_t is
  available` from `float128-x86_64`, argv echo from the `hello-*` pair).

### Sources → binaries

| Source | Binary | Compiler | Notes |
|--------|--------|----------|-------|
| `hello.c` | `hello-x86_64`, `hello-arm64` | x86_64 / aarch64 gcc | Static cross-compilation smoke test |
| `quadmath.cpp` | `qm-x86_64` | x86_64 g++ | `sqrt(2)` via `__float128` + libquadmath C API |
| `float128_example.cpp` | `float128-x86_64` | x86_64 g++ | Boost.Multiprecision `float128` example (frozen third-party Boost source) |
| `helloworld.c` | — | local cross-compilers | Used only by `make cross-compile`, not by Docker |

### Supply chain

Published images are digest-pinned at the base (Ubuntu Noble, Alpine), built from
SHA-pinned GitHub Actions, **scanned** with Trivy and **smoke-tested** before push, and
**signed** with cosign keyless (Sigstore OIDC). Verify a published image with:

```bash
cosign verify ghcr.io/andriykalashnykov/quadmath-cross:<tag>-runtime \
  --certificate-identity-regexp 'https://github.com/AndriyKalashnykov/quadmath-cross/.+' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Available Make Targets

Run `make help` to see all available targets.

### Build & Run

| Target | Description |
|--------|-------------|
| `make build` | Build amd64 builder image and local runtime image |
| `make image-run` | Run arm64 runtime image interactively |
| `make image-prune` | Docker system prune and buildx prune |
| `make cross-compile` | Cross-compile `helloworld.c` for x86_64, arm, aarch64 (requires local cross-compilers, e.g. `arm-linux-gnueabi-gcc`) |
| `make setup-binfmt` | Set up Docker binfmt support for arm64 emulation on x86_64 |

### Code Quality

| Target | Description |
|--------|-------------|
| `make lint` | Lint all Dockerfiles with [hadolint](https://github.com/hadolint/hadolint) |
| `make trivy-fs` | Scan the repository for vulnerabilities and secrets with [Trivy](https://trivy.dev/) |
| `make smoke` | Run every compiled binary and assert its output (amd64 natively; arm64 under QEMU) |

### CI

| Target | Description |
|--------|-------------|
| `make ci` | Full local CI pipeline (lint + filesystem scan + build + smoke) |
| `make ci-run` | Run the GitHub Actions workflow locally using [act](https://github.com/nektos/act) |

### Dependencies & Setup

| Target | Description |
|--------|-------------|
| `make deps` | Check required system dependencies (Docker, Git) |
| `make clean` | Remove build artifacts |
| `make deps-hadolint` | Install [hadolint](https://github.com/hadolint/hadolint) |
| `make deps-act` | Install [act](https://github.com/nektos/act) |
| `make deps-trivy` | Install [Trivy](https://trivy.dev/) |
| `make renovate-bootstrap` | Install [mise](https://mise.jdx.dev/) and the Node.js toolchain (`.mise.toml`) |

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
| **changes** | all | Path filter — skips the build for docs-only changes (`*.md`, `LICENSE`) |
| **docker-image-test** | push, PR, workflow_call | Runs `make ci` (hadolint + Trivy filesystem scan + builder/runtime build + binary smoke test) |
| **docker-image-builder** | tag push (`v*`) | Builds and pushes the amd64 builder image to ghcr.io, then cosign-signs it |
| **docker-image-runtime** | tag push (`v*`) | Builds the runtime image, **Trivy-scans + smoke-tests** it, pushes multi-platform (arm64 + amd64) to ghcr.io, then cosign-signs it |
| **ci-pass** | all | Aggregator gate — succeeds only if the required jobs passed (suitable as a single required status check) |

A [cleanup workflow](https://github.com/AndriyKalashnykov/quadmath-cross/actions/workflows/cleanup-runs.yml) runs weekly to prune workflow runs older than 7 days.

[Renovate](https://docs.renovatebot.com/) keeps dependencies up to date with PR automerge (squash) enabled.

## License

[MIT](LICENSE)
