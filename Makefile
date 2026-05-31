.DEFAULT_GOAL := help

# Tools installed by the deps-* targets land in ~/.local/bin (no sudo). Export
# it so a recipe that just installed a tool can immediately invoke it, and so
# `make ci-run` (act) finds the same binaries.
export PATH := $(HOME)/.local/bin:$(PATH)

APP_NAME       := quadmath-cross
CURRENTTAG     := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "dev")
NEWTAG         ?= $(shell bash -c 'read -p "Please provide a new tag (current tag - $(CURRENTTAG)): " newtag; echo $$newtag')

# === Tool Versions (pinned; tracked by renovate.json customManagers) ===
HADOLINT_VERSION := 2.14.0
ACT_VERSION      := 0.2.88
TRIVY_VERSION    := 0.70.0
# Node.js is pinned in .mise.toml (Renovate `mise` manager); used only by
# `make renovate-validate`.

# === Docker Image Settings ===
DOCKER_REGISTRY  ?= docker.io
DOCKER_ORG       ?= andriykalashnykov
DOCKER_IMAGE     := $(DOCKER_REGISTRY)/$(DOCKER_ORG)/$(APP_NAME)

#help: @ List available tasks
help:
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-22s\033[0m - %s\n", $$1, $$2}'

#version: @ Print current version (tag)
version:
	@echo $(CURRENTTAG)

#clean: @ Remove build artifacts
clean:
	@rm -f helloworld-x86_64 helloworld-arm helloworld-aarch64

#deps: @ Check required system dependencies
deps:
	@command -v docker >/dev/null 2>&1 || { echo "Error: Docker required. Install from https://www.docker.com/"; exit 1; }
	@command -v git >/dev/null 2>&1 || { echo "Error: Git required. Install from https://git-scm.com/"; exit 1; }

#build: @ Build amd64 builder image and runtime image
build: deps
	@docker build --platform linux/amd64 -f Dockerfile.builder -t $(DOCKER_IMAGE):$(CURRENTTAG)-builder .
	@docker build --build-arg BUILDER_IMAGE=$(DOCKER_IMAGE):$(CURRENTTAG)-builder -f Dockerfile.runtime.local -t $(DOCKER_IMAGE):$(CURRENTTAG)-runtime .

#image-run: @ Run arm64 runtime image interactively
image-run: deps
	@docker run -it --rm --platform linux/arm64 $(DOCKER_IMAGE):$(CURRENTTAG)-runtime /bin/sh

#image-prune: @ Docker system prune and buildx prune
image-prune: deps
	@docker system prune
	@docker buildx prune

#cross-compile: @ Cross-compile helloworld.c for x86_64, arm, and aarch64
cross-compile: deps
	@gcc -static helloworld.c -o helloworld-x86_64
	@file helloworld-x86_64
	@arm-linux-gnueabi-gcc helloworld.c -o helloworld-arm -static
	@file helloworld-arm
	@aarch64-linux-gnu-gcc helloworld.c -o helloworld-aarch64 -static
	@file helloworld-aarch64

#setup-binfmt: @ Setup Docker binfmt support for arm64 emulation on x86_64
setup-binfmt: deps
	@docker run --privileged --rm tonistiigi/binfmt:qemu-v10.2.1 --install all
	@echo "binfmt setup complete. Test with: docker run -it --rm --platform linux/arm64 arm64v8/ubuntu sh"

#lint: @ Lint all Dockerfiles with hadolint
lint: deps-hadolint
	@hadolint Dockerfile.builder
	@hadolint Dockerfile.runtime
	@hadolint Dockerfile.runtime.local

#trivy-fs: @ Scan the repository for vulnerabilities and secrets with trivy
trivy-fs: deps-trivy
	@trivy fs --scanners vuln,secret --severity CRITICAL,HIGH --ignore-unfixed --exit-code 1 .

#smoke: @ Run every compiled binary and assert its output (incl. arm64 under QEMU)
smoke: build
	@echo "Smoke-testing runtime image binaries (amd64)..."
	@out="$$(docker run --rm $(DOCKER_IMAGE):$(CURRENTTAG)-runtime /app/hello-x86_64)"; \
		case "$$out" in *"Total Number of args:"*) echo "  PASS hello-x86_64";; *) echo "  FAIL hello-x86_64: $$out"; exit 1;; esac
	@out="$$(docker run --rm $(DOCKER_IMAGE):$(CURRENTTAG)-runtime /app/qm-x86_64)"; \
		case "$$out" in *1.41421356237309504880*) echo "  PASS qm-x86_64";; *) echo "  FAIL qm-x86_64: $$out"; exit 1;; esac
	@out="$$(docker run --rm $(DOCKER_IMAGE):$(CURRENTTAG)-runtime /app/float128-x86_64)"; \
		case "$$out" in *"boost::float128_t is available"*) echo "  PASS float128-x86_64";; *) echo "  FAIL float128-x86_64: $$out"; exit 1;; esac
	@echo "Smoke-testing arm64 binary via builder qemu-aarch64-static..."
	@out="$$(docker run --rm $(DOCKER_IMAGE):$(CURRENTTAG)-builder qemu-aarch64-static /app/hello-arm64)"; \
		case "$$out" in *"Total Number of args:"*) echo "  PASS hello-arm64 (qemu)";; *) echo "  FAIL hello-arm64: $$out"; exit 1;; esac
	@echo "All smoke tests passed."

#ci: @ Run full local CI pipeline (lint + filesystem scan + build + smoke)
ci: deps lint trivy-fs build smoke
	@echo "Local CI pipeline passed."

#release: @ Create and push a new tag
release:
	@$(eval NT=$(NEWTAG))
	@echo "$(NT)" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$$' || { echo "Error: Tag must match vN.N.N"; exit 1; }
	@git diff --quiet && git diff --cached --quiet || { echo "Error: working tree is dirty; commit or stash changes before releasing."; exit 1; }
	@echo -n "Are you sure to create and push $(NT) tag? [y/N] " && read ans && [ $${ans:-N} = y ]
	@echo $(NT) > ./version.txt
	@git add version.txt
	@git commit -m "Cut $(NT) release"
	@git tag $(NT)
	@git push origin HEAD
	@git push origin $(NT)
	@echo "Done."

#tag-delete: @ Delete a tag locally and from origin (destructive, requires confirmation)
tag-delete:
	@bash -c 'read -p "Tag to delete: " tag && \
		echo -n "Are you sure you want to delete tag $$tag locally and from origin? [y/N] " && \
		read ans && [ $${ans:-N} = y ] && \
		git push --delete origin $$tag && \
		git tag --delete $$tag'

#deps-hadolint: @ Install hadolint for Dockerfile linting
deps-hadolint:
	@command -v hadolint >/dev/null 2>&1 || { echo "Installing hadolint $(HADOLINT_VERSION)..."; \
		mkdir -p $$HOME/.local/bin && \
		curl -sSfL -o /tmp/hadolint https://github.com/hadolint/hadolint/releases/download/v$(HADOLINT_VERSION)/hadolint-Linux-x86_64 && \
		install -m 755 /tmp/hadolint $$HOME/.local/bin/hadolint && \
		rm -f /tmp/hadolint; \
	}

#deps-act: @ Install act for running GitHub Actions locally
deps-act:
	@command -v act >/dev/null 2>&1 || { echo "Installing act $(ACT_VERSION)..."; \
		mkdir -p $$HOME/.local/bin && \
		curl -sSfL https://raw.githubusercontent.com/nektos/act/v$(ACT_VERSION)/install.sh | bash -s -- -b $$HOME/.local/bin v$(ACT_VERSION); \
	}

#deps-trivy: @ Install trivy for filesystem vulnerability and secret scanning
deps-trivy:
	@command -v trivy >/dev/null 2>&1 || { echo "Installing trivy $(TRIVY_VERSION)..."; \
		mkdir -p $$HOME/.local/bin && \
		curl -sSfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b $$HOME/.local/bin v$(TRIVY_VERSION); \
	}

#ci-run: @ Run GitHub Actions workflow locally using act
ci-run: deps-act
	@act push --container-architecture linux/amd64 \
		--artifact-server-path /tmp/act-artifacts

#renovate-bootstrap: @ Install mise and the Node.js toolchain (.mise.toml) for Renovate
renovate-bootstrap:
	@command -v mise >/dev/null 2>&1 || { echo "Installing mise..."; \
		curl -fsSL https://mise.run | sh; \
	}
	@mise install

#renovate-validate: @ Validate Renovate configuration
renovate-validate: renovate-bootstrap
	@mise exec -- npx --yes renovate@latest --platform=local

.PHONY: help version clean deps build image-run image-prune cross-compile setup-binfmt \
	lint trivy-fs smoke ci release tag-delete \
	deps-hadolint deps-act deps-trivy ci-run \
	renovate-bootstrap renovate-validate
