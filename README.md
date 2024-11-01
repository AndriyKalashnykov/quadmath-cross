# quadmath-cross

Cross compile quadmath

## Build docker images

Build `amd64` `builder` image first

```bash
docker build --platform linux/amd64 -f Dockerfile.builder -t docker.io/anriykalashnykov/quadmath-cross:v0.0.1-builder .
```

Build `arm64` `runtime` image from `amd64` `builder` image

```bash
docker build -f Dockerfile.runtme.local -t docker.io/anriykalashnykov/quadmath-cross:v0.0.1-runtime .
```

## Run docker image

Run `arm64` `runtime` image

```bash
docker run -it --rm --platform linux/arm64 docker.io/anriykalashnykov/quadmath-cross:v0.0.1-runtime /bin/sh
```