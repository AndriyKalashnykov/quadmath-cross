.DEFAULT_GOAL := help

# CLI tools (hadolint, act, trivy, node) are installed by mise into its shims
# dir; mise's auto-activation does not run inside Make's $(SHELL) -c sub-shells,
# so put the shims dir on PATH explicitly. ~/.local/bin stays for mise itself
# (bootstrapped via https://mise.run) and any hand-installed binary.
export PATH := $(HOME)/.local/share/mise/shims:$(HOME)/.local/bin:$(PATH)

APP_NAME       := quadmath-cross
CURRENTTAG     := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "dev")
NEWTAG         ?= $(shell bash -c 'read -p "Please provide a new tag (current tag - $(CURRENTTAG)): " newtag; echo $$newtag')

# === Tool Versions ===
# hadolint, act, trivy, and node are pinned in .mise.toml (single source of
# truth, tracked by Renovate's native `mise` manager) and installed by
# `make deps-tools`. The only image pinned here is the binfmt installer used by
# `setup-binfmt` (consumed via `docker run`, so it stays a Makefile reference
# tracked by a renovate.json customManager).

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
lint: deps-tools
	@hadolint Dockerfile.builder
	@hadolint Dockerfile.runtime
	@hadolint Dockerfile.runtime.local

#trivy-fs: @ Scan the repository for vulnerabilities and secrets with trivy
trivy-fs: deps-tools
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
	@if git rev-parse -q --verify "refs/tags/$(NT)" >/dev/null 2>&1; then echo "ERROR: tag $(NT) already exists locally. Pick a new version or delete it: git tag -d $(NT)"; exit 1; fi
	@if git ls-remote --exit-code --tags origin "refs/tags/$(NT)" >/dev/null 2>&1; then echo "ERROR: tag $(NT) already exists on origin. Pick a new version."; exit 1; fi
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

#deps-tools: @ Install pinned CLI tools (hadolint, act, trivy, node) via mise
deps-tools:
	@if ! command -v mise >/dev/null 2>&1; then \
		if [ -z "$$CI" ]; then \
			echo "Installing mise (no root; installs to ~/.local/bin)..."; \
			curl -fsSL https://mise.run | sh; \
		else \
			echo "Error: mise required in CI (use jdx/mise-action)."; exit 1; \
		fi; \
	fi
	@mise install --yes

#ci-run: @ Run GitHub Actions workflow locally using act
ci-run: deps-tools
	@docker container prune -f 2>/dev/null || true
	@ACT_PORT=$$(shuf -i 40000-59999 -n 1); \
	act push --container-architecture linux/amd64 \
		--artifact-server-port "$$ACT_PORT" \
		--artifact-server-path "$$(mktemp -d -t act-artifacts.XXXXXX)"

#renovate-validate: @ Validate Renovate configuration
renovate-validate: deps-tools
	@mise exec -- npx --yes renovate@latest --platform=local

.PHONY: help version clean deps deps-tools build image-run image-prune cross-compile setup-binfmt \
	lint trivy-fs smoke ci release tag-delete \
	ci-run renovate-validate
