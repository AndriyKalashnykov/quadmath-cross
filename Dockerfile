FROM amd64/gcc:15@sha256:3972c52b24c1d513c87c1835e1aa4a84f4e4a9c19903f16b0021e3f224b71a18 AS builder

ARG DEBIAN_FRONTEND=noninteractive

RUN DEBIAN_FRONTEND=${DEBIAN_FRONTEND} apt-get update && apt-get install -y --no-install-recommends bash curl locales g++-multilib

WORKDIR /app

COPY ./hello.cpp .

RUN g++ -std=c++11 -fno-quadmath -o hello hello.cpp

# Keep the container running
CMD ["tail", "-f", "/dev/null"]