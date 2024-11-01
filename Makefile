projectname?=quadmath-cross

CURRENTTAG:=$(shell git describe --tags --abbrev=0)
NEWTAG ?= $(shell bash -c 'read -p "Please provide a new tag (currnet tag - ${CURRENTTAG}): " newtag; echo $$newtag')

default: help

help: ## list makefile targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-10s\033[0m %s\n", $$1, $$2}'

release: ## create and push a new tag
	$(eval NT=$(NEWTAG))
	@echo -n "Are you sure to create and push ${NT} tag? [y/N] " && read ans && [ $${ans:-N} = y ]
	@echo ${NT} > ./version.txt
	@git add -A
	@git commit -a -s -m "Cut ${NT} release"
	@git tag ${NT}
	@git push origin ${NT}
	@git push
	@echo "Done."

version: ## Print current version(tag)
	@echo $(shell git describe --tags --abbrev=0)

dp:
	docker system prune
	docker buildx prune

# setup Docker to run arm64 images on Ubuntu x86_64
# https://jkfran.com/running-ubuntu-arm-with-docker/
# https://www.stereolabs.com/docs/docker/building-arm-container-on-x86
# https://github.com/carlosperate/arm-none-eabi-gcc-action
# https://embeddedinventor.com/a-complete-beginners-guide-to-the-gnu-arm-toolchain-part-1/
# export PATH=/path/to/install/dir/bin:$PATH
sd:
	docker run --privileged --rm tonistiigi/binfmt --install all
	docker run -it --rm --platform linux/arm64 arm64v8/ubuntu sh
# uname -m
# aarch64

ba:
	docker build -f Dockerfile.amd64 -t docker.io/anriykalashnykov/quadmath-cross:latest-builder .
	docker build -f Dockerfile.arm64 -t docker.io/anriykalashnykov/quadmath-cross:latest-runtime .

ra:
	docker run -it --rm --platform linux/arm64 docker.io/anriykalashnykov/quadmath-cross:latest-runtime /bin/sh

dt:
	rm -f version.txt
	git push --delete origin v0.0.1
	git tag --delete v0.0.1
