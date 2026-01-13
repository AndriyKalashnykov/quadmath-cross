FROM amd64/gcc:15@sha256:5141fffff1af37b2571a56ba78dedeff78e89264ae88328d8a10b57a11d8a3d3 AS builder

ARG DEBIAN_FRONTEND=noninteractive

RUN DEBIAN_FRONTEND=${DEBIAN_FRONTEND} apt-get update && apt-get install -y --no-install-recommends bash curl locales g++-multilib

WORKDIR /app

COPY ./hello.cpp .

RUN g++ -std=c++11 -fno-quadmath -o hello hello.cpp

# Keep the container running
CMD ["tail", "-f", "/dev/null"]