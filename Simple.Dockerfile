FROM phusion/baseimage:0.9.19 as Base

#ARG STEEMD_BLOCKCHAIN=https://example.com/steemd-blockchain.tbz2

ARG STEEM_STATIC_BUILD=ON
ENV STEEM_STATIC_BUILD ${STEEM_STATIC_BUILD}

ENV LANG=en_US.UTF-8

RUN \
    apt-get update && \
    apt-get install -y \
        autoconf \
        automake \
        autotools-dev \
        bsdmainutils \
        build-essential \
        cmake \
        doxygen \
        git \
        libboost-all-dev \
        libreadline-dev \
        libssl-dev \
        libtool \
        liblz4-tool \
        ncurses-dev \
        pkg-config \
        python3 \
        python3-dev \
        python3-jinja2 \
        python3-pip \
        nginx \
        fcgiwrap \
        awscli \
        jq \
        wget \
        gdb \
    && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    pip3 install gcovr

ADD . /usr/local/src/steem

# FROM Base as Tester
# 
# RUN \
#     cd /usr/local/src/steem && \
#     git submodule update --init --recursive && \
#     mkdir build && \
#     cd build && \
#     cmake \
#         -DCMAKE_BUILD_TYPE=Release \
#         -DBUILD_STEEM_TESTNET=ON \
#         -DLOW_MEMORY_NODE=OFF \
#         -DCLEAR_VOTES=ON \
#         -DSKIP_BY_TX_ID=ON \
#         .. && \
#     make -j$(nproc) chain_test test_fixed_string && \
#     ./tests/chain_test && \
#     ./programs/util/test_fixed_string && \
#     cd /usr/local/src/steem && \
#     doxygen && \
#     programs/build_helpers/check_reflect.py && \
#     programs/build_helpers/get_config_check.sh && \
#     rm -rf /usr/local/src/steem/build
# 
# RUN \
#     cd /usr/local/src/steem && \
#     git submodule update --init --recursive && \
#     mkdir build && \
#     cd build && \
#     cmake \
#         -DCMAKE_BUILD_TYPE=Debug \
#         -DENABLE_COVERAGE_TESTING=ON \
#         -DBUILD_STEEM_TESTNET=ON \
#         -DLOW_MEMORY_NODE=OFF \
#         -DCLEAR_VOTES=ON \
#         -DSKIP_BY_TX_ID=ON \
#         -DCHAINBASE_CHECK_LOCKING=OFF \
#         .. && \
#     make -j$(nproc) chain_test && \
#     ./tests/chain_test && \
#     mkdir -p /var/cobertura && \
#     gcovr --object-directory="../" --root=../ --xml-pretty --gcov-exclude=".*tests.*" --gcov-exclude=".*fc.*" --gcov-exclude=".*app*" --gcov-exclude=".*net*" --gcov-exclude=".*plugins*" --gcov-exclude=".*schema*" --gcov-exclude=".*time*" --gcov-exclude=".*utilities*" --gcov-exclude=".*wallet*" --gcov-exclude=".*programs*" --output="/var/cobertura/coverage.xml" && \
#     cd /usr/local/src/steem && \
#     rm -rf /usr/local/src/steem/build
# 
FROM Base as Builder

RUN \
    cd /usr/local/src/steem && \
    git submodule update --init --recursive
# RUN \
#     mkdir build && \
#     cd build && \
#     cmake \
#         -DCMAKE_INSTALL_PREFIX=/usr/local/steemd-default \
#         -DCMAKE_BUILD_TYPE=Release \
#         -DLOW_MEMORY_NODE=ON \
#         -DCLEAR_VOTES=ON \
#         -DSKIP_BY_TX_ID=OFF \
#         -DBUILD_STEEM_TESTNET=OFF \
#         -DSTEEM_STATIC_BUILD=${STEEM_STATIC_BUILD} \
#         .. \
#     && \
#     make -j$(nproc) && \
#     make install && \
#     cd .. && \
#     ( /usr/local/steemd-default/bin/steemd --version \
#       | grep -o '[0-9]*\.[0-9]*\.[0-9]*' \
#       && echo '_' \
#       && git rev-parse --short HEAD ) \
#       | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n//g' \
#       > /etc/steemdversion && \
#     cat /etc/steemdversion && \
#     rm -rfv build
RUN \
    cd /usr/local/src/steem && \
    mkdir build && \
    cd build && \
    cmake \
        -DCMAKE_INSTALL_PREFIX=/usr/local/steemd-full \
        -DCMAKE_BUILD_TYPE=Release \
        -DLOW_MEMORY_NODE=OFF \
        -DCLEAR_VOTES=OFF \
        -DSKIP_BY_TX_ID=ON \
        -DBUILD_STEEM_TESTNET=OFF \
        -DSTEEM_STATIC_BUILD=${STEEM_STATIC_BUILD} \
        .. \
    && \
    make -j$(nproc) && \
    make install && \
    rm -rfv build
RUN \
    rm -rf /usr/local/src/steem

FROM phusion/baseimage:0.9.19 as Final

# COPY --from=Builder /usr/local/steemd-default /usr/local/steemd-default
COPY --from=Builder /usr/local/steemd-full /usr/local/steemd-full

RUN useradd -s /bin/bash -m -d /var/lib/steemd steemd

RUN mkdir /var/cache/steemd && \
    chown steemd:steemd -R /var/cache/steemd

# add blockchain cache to image
#ADD $STEEMD_BLOCKCHAIN /var/cache/steemd/blocks.tbz2

ENV HOME /var/lib/steemd
RUN chown steemd:steemd -R /var/lib/steemd

VOLUME ["/var/lib/steemd"]

# rpc service:
EXPOSE 8090
# p2p service:
EXPOSE 2001

# add seednodes from documentation to image
ADD doc/seednodes.txt /etc/steemd/seednodes.txt

# the following adds lots of logging info to stdout
ADD contrib/config-for-docker.ini /etc/steemd/config.ini
ADD contrib/fullnode.config.ini /etc/steemd/fullnode.config.ini
ADD contrib/config-for-broadcaster.ini /etc/steemd/config-for-broadcaster.ini
ADD contrib/config-for-ahnode.ini /etc/steemd/config-for-ahnode.ini

# add normal startup script that starts via sv
ADD contrib/steemd.run /usr/local/bin/steem-sv-run.sh
RUN chmod +x /usr/local/bin/steem-sv-run.sh

# add nginx templates
ADD contrib/steemd.nginx.conf /etc/nginx/steemd.nginx.conf
ADD contrib/healthcheck.conf.template /etc/nginx/healthcheck.conf.template

# add PaaS startup script and service script
ADD contrib/startpaassteemd.sh /usr/local/bin/startpaassteemd.sh
ADD contrib/paas-sv-run.sh /usr/local/bin/paas-sv-run.sh
ADD contrib/sync-sv-run.sh /usr/local/bin/sync-sv-run.sh
ADD contrib/healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/startpaassteemd.sh
RUN chmod +x /usr/local/bin/paas-sv-run.sh
RUN chmod +x /usr/local/bin/sync-sv-run.sh
RUN chmod +x /usr/local/bin/healthcheck.sh

# new entrypoint for all instances
# this enables exitting of the container when the writer node dies
# for PaaS mode (elasticbeanstalk, etc)
# AWS EB Docker requires a non-daemonized entrypoint
ADD contrib/steemdentrypoint.sh /usr/local/bin/steemdentrypoint.sh
RUN chmod +x /usr/local/bin/steemdentrypoint.sh
CMD /usr/local/bin/steemdentrypoint.sh