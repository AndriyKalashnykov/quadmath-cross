#FROM amd64/debian:bookworm AS builder
FROM amd64/ubuntu:noble-20260217@sha256:84ebf67ad1e2908cb4f21aa99c1611aafd1690ba118c7fbaf201e5cbef3c7850 AS builder

ARG DEBIAN_FRONTEND=noninteractive
ARG GCC_VERSION=14

# build-essential
RUN DEBIAN_FRONTEND=${DEBIAN_FRONTEND} apt-get update && apt-get install -y --no-install-recommends bash curl locales

RUN dpkg --add-architecture arm64
RUN dpkg --add-architecture armel
RUN dpkg --add-architecture armhf

RUN DEBIAN_FRONTEND=${DEBIAN_FRONTEND} apt-get install -y --no-install-recommends \
    crossbuild-essential-arm64 \
    crossbuild-essential-armel \
    crossbuild-essential-armhf

RUN DEBIAN_FRONTEND=${DEBIAN_FRONTEND} apt-get install -y --no-install-recommends qemu-user-static qemu-user binfmt-support
# https://packages.debian.org/bookworm/gcc-arm-none-eabi
# Bare metal C and C++ compiler for embedded ARM chips using Cortex-M, and Cortex-R processors. This package is based on the GNU ARM toolchain provided by ARM.
RUN DEBIAN_FRONTEND=${DEBIAN_FRONTEND} apt-get install -y --no-install-recommends gdb-multiarch gcc-arm-none-eabi binutils-arm-none-eabi
RUN DEBIAN_FRONTEND=${DEBIAN_FRONTEND} apt-get install -y --no-install-recommends \
    cmake gcc-${GCC_VERSION} g++-${GCC_VERSION} \
    gcc-x86-64-linux-gnu g++-x86-64-linux-gnu binutils-x86-64-linux-gnu \
    g++-${GCC_VERSION}-aarch64-linux-gnu binutils-aarch64-linux-gnu libc6-dev-amd64-cross libstdc++-${GCC_VERSION}-dev-arm64-cross \
    gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf \
    libc6-amd64-cross libc6-dev-arm64-cross libc6-dev-armel-cross libc6-dev-armhf-cross libc6-dev-i386 \
    libdlib-dev libblas-dev libatlas-base-dev liblapack-dev wget bzip2 \
    gfortran libgfortran5 libquadmath0 libquadmath0-amd64-cross libquadrule-dev \
    libboost-dev libboost-system-dev \
    cppcheck

RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-${GCC_VERSION} 60 --slave /usr/bin/g++ g++ /usr/bin/g++-${GCC_VERSION} && \
    update-alternatives --install /usr/bin/aarch64-linux-gnu-g++ aarch64-linux-gnu-g++ /usr/bin/aarch64-linux-gnu-g++-${GCC_VERSION} 60 && \
    update-alternatives --install /usr/bin/aarch64-linux-gnu-gcc aarch64-linux-gnu-gcc /usr/bin/aarch64-linux-gnu-gcc-${GCC_VERSION} 60

WORKDIR /app

COPY ./hello.c .
COPY ./quadmath.cpp .
COPY ./float128_example.cpp .

# Static analysis (own sources only — float128_example.cpp is a third-party Boost example)
RUN cppcheck --enable=all --error-exitcode=1 \
    --suppress=missingIncludeSystem --suppress=missingInclude \
    --suppress=checkersReport --suppress=unmatchedSuppression \
    hello.c quadmath.cpp

# Cross-compilation smoke test (x86_64 + arm64)
RUN x86_64-linux-gnu-gcc -Wall -Wextra -static hello.c -o hello-x86_64
RUN aarch64-linux-gnu-gcc -Wall -Wextra -static hello.c -o hello-arm64

# sqrt(2) via __float128 + libquadmath C API
RUN x86_64-linux-gnu-g++ -I/usr/lib/gcc/x86_64-linux-gnu/${GCC_VERSION} -I/usr/lib/gcc/x86_64-linux-gnu/${GCC_VERSION}/include \
    quadmath.cpp -o qm-x86_64 -static -lm -lpthread -lgfortran -lboost_system -lquadmath

# Boost multiprecision float128 extended example
RUN x86_64-linux-gnu-g++ -Wall -std=gnu++14 -fexceptions -fext-numeric-literals \
    -I/usr/lib/gcc/x86_64-linux-gnu/${GCC_VERSION}/include \
    -c float128_example.cpp -o float128.o
RUN x86_64-linux-gnu-g++ -static -o float128-x86_64 float128.o -lquadmath

# Keep the container running
CMD ["tail", "-f", "/dev/null"]