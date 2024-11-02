#FROM amd64/debian:bookworm AS builder
FROM amd64/ubuntu:24.10 AS builder

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
    libboost-dev libboost-system-dev

RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-${GCC_VERSION} 60 --slave /usr/bin/g++ g++ /usr/bin/g++-${GCC_VERSION} && \
    update-alternatives --install /usr/bin/aarch64-linux-gnu-g++ aarch64-linux-gnu-g++ /usr/bin/aarch64-linux-gnu-g++-${GCC_VERSION} 60 && \
    update-alternatives --install /usr/bin/aarch64-linux-gnu-gcc aarch64-linux-gnu-gcc /usr/bin/aarch64-linux-gnu-gcc-${GCC_VERSION} 60
# libjpeg62-turbo-dev

# /usr/lib/gcc/x86_64-linux-gnu/12/include/quadmath.h

#RUN ln -sf $(which gcc) /usr/local/bin/gcc-aarch64-linux-gnu \
#    && ln -sf $(which g++) /usr/local/bin/g++-aarch64-linux-gnu

WORKDIR /app

COPY ./hello.c .

# quadmath c++
COPY ./quadmath.cpp .
# quadmath c
COPY ./quadmath.c .

#RUN aarch64-linux-gnu-gcc -static -static-libgcc -std=c++11 hello.c -o hello
RUN x86_64-linux-gnu-gcc -g -Wall -Wextra -Wunreachable-code -static hello.c -o hello-x86_64 -lm -llapack -lblas -lpthread -lgfortran -lquadmath
RUN aarch64-linux-gnu-gcc -I/usr/lib/gcc/x86_64-linux-gnu/14 -I/usr/lib/gcc/x86_64-linux-gnu/14/include \
    -Wl,--unresolved-symbols=report-all,--warn-unresolved-symbols,--warn-once,-Bstatic -static-libgcc -g -Wall -Wextra \
    -Wunreachable-code -fext-numeric-literals -s -w -extldflags -static hello.c -o hello-arm64 -lm -lpthread

#RUN x86_64-linux-gnu-gcc quadmath.c -o qmc -Wl,-Bstatic -s -w -extldflags -static -lquadmath
#RUN gcc -g -Wall -Wextra -Wunreachable-code -static -static-libgcc quadmath.c -o qmc -Wl,-Bstatic -lm -llapack -lblas -lpthread -lgfortran -lquadmath

#ENV PATH=/usr/bin:$PATH
#ENV CC=aarch64-linux-gnu-gcc
#ENV CXX=aarch64-linux-gnu-g++
#ENV PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig
#ENV PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig
#RUN aarch64-linux-gnu-gcc --std=gnu++20 -I/usr/lib/gcc/x86_64-linux-gnu/14 -I/usr/lib/gcc/x86_64-linux-gnu/12/include -fext-numeric-literals -static -lgfortran -lquadmath quadmath.cpp -o quadmath
#RUN aarch64-linux-gnu-gcc-14 -I/usr/lib/gcc/x86_64-linux-gnu/14 -I/usr/lib/gcc/x86_64-linux-gnu/14/include -g -Wall -Wextra -Wunreachable-code -static quadmath.cpp -o qm-aarch64 -lm -llapack -lblas -lpthread -lgfortran -lquadmath
#RUN aarch64-linux-gnu-g++ -g -Wall -Wextra -Wunreachable-code -static quadmath.cpp -o qm-aarch64  -llapack -lblas -lpthread -lgfortran -lquadmath -lm
#RUN aarch64-linux-gnu-g++ -Wl,--unresolved-symbols=report-all,--warn-unresolved-symbols,--warn-once,-Bstatic -static-libgcc -g -Wall -Wextra -Wunreachable-code -static quadmath.cpp -o qm-aarch64  -llapack -lblas -lpthread -lgfortran -lquadmath -lm \
#    $(pkg-config --cflags --libs -statifrec opencv)

# arm-none-eabi-gcc -static hello.c -o hello
# find / -name aarch64-linux-gnu-gcc-10
# find / -name 'quadmath*'
# find / -name 'libquadmath*'
# find / -name 'pkgconfig'

# Keep the container running
CMD ["tail", "-f", "/dev/null"]