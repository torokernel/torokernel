# syntax=docker/dockerfile:1
FROM debian:buster
RUN apt update && apt install python3-pip apt-utils make git wget libcap-dev libcap-ng-dev libcurl4-gnutls-dev libgtk-3-dev libglib2.0-dev libpixman-1-dev libseccomp-dev autoconf -y
RUN pip3 install ninja
RUN wget https://sourceforge.net/projects/lazarus/files/Lazarus%20Linux%20amd64%20DEB/Lazarus%202.0.10/fpc-laz_3.2.0-1_amd64.deb/download && mv download fpc-laz_3.2.0-1_amd64.deb && apt install ./fpc-laz_3.2.0-1_amd64.deb -y
RUN ln -s /root /home/debian
WORKDIR /root
RUN git clone https://github.com/qemu/qemu.git qemuforvmm
RUN cd qemuforvmm && git checkout 51204c2f && mkdir build && cd build && ../configure --target-list=x86_64-softmmu && make 
RUN git clone https://github.com/torokernel/freepascal.git -b fpc-3.2.0 fpc-3.2.0
RUN git clone https://github.com/torokernel/torokernel.git
RUN sed -i '/fpcrtlsource=/c\fpcrtlsource="'"$PWD"'/fpc-3.2.0/rtl/"' ./torokernel/examples/CloudIt.sh
RUN sed -i '/fpcrtlsource=/c\fpcrtlsource="'"$PWD"'/fpc-3.2.0/rtl/"' ./torokernel/examples/CloudIt.sh
RUN sed -i 's/sudo//g' ./torokernel/examples/CloudIt.sh
WORKDIR /root/torokernel
