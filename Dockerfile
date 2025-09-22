FROM amd64/gcc:15@sha256:4bfa7671e6989b71cd1ccb296014c3403b0ad0d3ab4bf180aadc6011e620641c AS builder

ARG DEBIAN_FRONTEND=noninteractive

RUN DEBIAN_FRONTEND=${DEBIAN_FRONTEND} apt-get update && apt-get install -y --no-install-recommends bash curl locales g++-multilib

WORKDIR /app

COPY ./hello.cpp .

RUN g++ -std=c++11 -fno-quadmath -o hello hello.cpp

# Keep the container running
CMD ["tail", "-f", "/dev/null"]