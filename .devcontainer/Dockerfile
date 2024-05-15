FROM docker.io/opensuse/leap:15.5

RUN zypper ar -f -p 95 http://download.opensuse.org/repositories/devel:openQA/15.5 devel_openQA && \
    zypper --gpg-auto-import-keys ref && \
    zypper in -y openQA-client git && \
    zypper clean
