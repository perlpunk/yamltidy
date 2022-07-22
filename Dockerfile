FROM opensuse/leap:15.4

RUN zypper -n install perl

WORKDIR /pwd
