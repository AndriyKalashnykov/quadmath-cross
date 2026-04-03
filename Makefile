.DEFAULT_GOAL := help

APP_NAME       := quadmath-cross
CURRENTTAG     := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "dev")
NEWTAG         ?= $(shell bash -c 'read -p "Please provide a new tag (current tag - $(CURRENTTAG)): " newtag; echo $$newtag')

# === Tool Versions (pinned) ===
HADOLINT_VERSION := 2.14.0
ACT_VERSION      := 0.2.87
NVM_VERSION      := 0.40.4
NODE_VERSION     := 22

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

#ci: @ Run full local CI pipeline (lint + build)
ci: deps lint build
	@echo "Local CI pipeline passed."

#release: @ Create and push a new tag
release:
	@$(eval NT=$(NEWTAG))
	@echo "$(NT)" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$$' || { echo "Error: Tag must match vN.N.N"; exit 1; }
	@echo -n "Are you sure to create and push $(NT) tag? [y/N] " && read ans && [ $${ans:-N} = y ]
	@echo $(NT) > ./version.txt
	@git add version.txt
	@git commit -m "Cut $(NT) release"
	@git tag $(NT)
	@git push origin $(NT)
	@git push
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
		curl -sSfL -o /tmp/hadolint https://github.com/hadolint/hadolint/releases/download/v$(HADOLINT_VERSION)/hadolint-Linux-x86_64 && \
		install -m 755 /tmp/hadolint /usr/local/bin/hadolint && \
		rm -f /tmp/hadolint; \
	}

#deps-act: @ Install act for running GitHub Actions locally
deps-act:
	@command -v act >/dev/null 2>&1 || { echo "Installing act $(ACT_VERSION)..."; \
		curl -sSfL https://raw.githubusercontent.com/nektos/act/v$(ACT_VERSION)/install.sh | sudo bash -s -- -b /usr/local/bin v$(ACT_VERSION); \
	}

#ci-run: @ Run GitHub Actions workflow locally using act
ci-run: deps-act
	@act push --container-architecture linux/amd64 \
		--artifact-server-path /tmp/act-artifacts

#renovate-bootstrap: @ Install nvm and npm for Renovate
renovate-bootstrap:
	@command -v node >/dev/null 2>&1 || { \
		echo "Installing nvm $(NVM_VERSION)..."; \
		curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v$(NVM_VERSION)/install.sh | bash; \
		export NVM_DIR="$$HOME/.nvm"; \
		[ -s "$$NVM_DIR/nvm.sh" ] && . "$$NVM_DIR/nvm.sh"; \
		nvm install $(NODE_VERSION); \
	}

#renovate-validate: @ Validate Renovate configuration
renovate-validate: renovate-bootstrap
	@npx --yes renovate --platform=local

.PHONY: help version clean deps build image-run image-prune cross-compile setup-binfmt \
	lint ci release tag-delete \
	deps-hadolint deps-act ci-run \
	renovate-bootstrap renovate-validate
