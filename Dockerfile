FROM amd64/gcc:15@sha256:893ef8f3d9ef2e78f79abeae4acc9aa8f72144e6675f4542e70f57048ed3245e AS builder

ARG DEBIAN_FRONTEND=noninteractive

RUN DEBIAN_FRONTEND=${DEBIAN_FRONTEND} apt-get update && apt-get install -y --no-install-recommends bash curl locales g++-multilib

WORKDIR /app

COPY ./hello.cpp .

RUN g++ -std=c++11 -fno-quadmath -o hello hello.cpp

# Keep the container running
CMD ["tail", "-f", "/dev/null"]