#FROM amd64/debian:bookworm AS builder
FROM amd64/ubuntu:noble-20260509.1@sha256:ff32d54215b8fb6e315be754f45dec57341437ec6c4e4a95026ee6a234f5baf9 AS builder

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
    libboost-dev \
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
    quadmath.cpp -o qm-x86_64 -static -lm -lpthread -lgfortran -lquadmath

# Boost multiprecision float128 extended example
RUN x86_64-linux-gnu-g++ -Wall -std=gnu++14 -fexceptions -fext-numeric-literals \
    -I/usr/lib/gcc/x86_64-linux-gnu/${GCC_VERSION}/include \
    -c float128_example.cpp -o float128.o
RUN x86_64-linux-gnu-g++ -static -o float128-x86_64 float128.o -lquadmath

# Behavioral verification — run every compiled binary and assert its output.
# amd64 binaries run natively; the arm64 binary runs under qemu-aarch64-static
# (from qemu-user-static, installed above) with no binfmt registration needed
# because every binary is statically linked. A broken or incorrect artifact
# fails the image build here, not at first runtime use. Output is redirected to
# files (no pipes) so the assertions are hadolint DL4006-clean.
RUN set -eux; \
    ./hello-x86_64                    > /tmp/hello-x86_64.out  && grep -q 'Total Number of args:'      /tmp/hello-x86_64.out;  \
    qemu-aarch64-static ./hello-arm64 > /tmp/hello-arm64.out   && grep -q 'Total Number of args:'      /tmp/hello-arm64.out;   \
    ./qm-x86_64                       > /tmp/qm-x86_64.out      && grep -q '1.41421356237309504880'     /tmp/qm-x86_64.out;     \
    ./float128-x86_64                 > /tmp/float128-x86_64.out && grep -q 'boost::float128_t is available' /tmp/float128-x86_64.out; \
    rm -f /tmp/hello-x86_64.out /tmp/hello-arm64.out /tmp/qm-x86_64.out /tmp/float128-x86_64.out

# Keep the container running
CMD ["tail", "-f", "/dev/null"]