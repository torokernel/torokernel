# syntax=docker/dockerfile:1
FROM debian:latest
WORKDIR /root
RUN apt update && apt install -y \
    python3 python3-pip python3-venv \
    apt-utils make git wget \
    libcap-dev libcap-ng-dev \
    libcurl4-gnutls-dev \
    libgtk-3-dev libglib2.0-dev \
    libpixman-1-dev libseccomp-dev \
    autoconf build-essential ninja-build
RUN pip3 install --break-system-packages qemu.qmp
RUN ln -s /usr/bin/python3 /usr/bin/python
RUN ln -s /root /home/debian
RUN git clone https://github.com/qemu/qemu.git qemuforvmm
RUN cd qemuforvmm && git checkout ce64e622 \
    && mkdir build && cd build \
    && ../configure --target-list=x86_64-softmmu \
    && make
# the following steps are required for compiling fpc for Toro
# clone fpc for Toro
# RUN git clone https://github.com/torokernel/FPCSource.git -b fpc-3.2.2-for-toro source-fpc
# compile only fpcmake for Toro, note that linux is as target
# RUN cd source-fpc && git checkout f6573d32 && make OS_SOURCE=linux CPU_SOURCE=x86_64 OS_TARGET=linux CPU_TARGET=x86_64 OPT="-g" --jobs=8 FPMAKEOPT=--threads=8 all
# compile only the compiler for Toro
# RUN cd source-fpc/compiler && git checkout d283d9f && make clean && make x86_64
# compile the rtl for Toro using the crosscompiler
# RUN cd source-fpc/rtl/toro && ../../utils/fpcm/bin/x86_64-linux/fpcmake -Tx86_64-toro -w && make FPC=../../compiler/ppcx64 OS_TARGET=toro CPU_TARGET=x86_64 clean && make FPC=../../compiler/ppcx64 OS_TARGET=toro CPU_TARGET=x86_64
# get compiler and rtl for toro from release
RUN mkdir -p source-fpc/compiler \
    && cd source-fpc/compiler \
    && wget https://github.com/torokernel/FPCSource/releases/download/releasefortoro-3.2.2/ppcx64.tar \
    && tar -xvf ppcx64.tar
RUN mkdir -p source-fpc/rtl/units/x86_64-toro/ \
    && cd source-fpc/rtl/units/x86_64-toro/ \
    && wget https://github.com/torokernel/FPCSource/releases/download/releasefortoro-3.2.2/x86_64-toro-rtl.tar \
    && tar -xvf x86_64-toro-rtl.tar
ARG BRANCH=master
RUN git clone https://github.com/torokernel/torokernel.git -b $BRANCH
ENV TORO_ROOT=/root
WORKDIR /root/torokernel
