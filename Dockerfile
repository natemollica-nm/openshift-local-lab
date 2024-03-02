# Red Hat UBI-based image
# This target is used to build a Consul image for use on OpenShift.
FROM registry.access.redhat.com/ubi9-minimal:9.3 as ubi

ARG PRODUCT_NAME
ARG PRODUCT_VERSION
ARG PRODUCT_REVISION
ARG BIN_NAME

# PRODUCT_NAME and PRODUCT_VERSION are the name of the software on releases.hashicorp.com
# and the version to download. Example: PRODUCT_NAME=consul PRODUCT_VERSION=1.2.3.
ENV BIN_NAME=$BIN_NAME
ENV PRODUCT_VERSION=$PRODUCT_VERSION

ARG PRODUCT_NAME=$BIN_NAME

# TARGETOS and TARGETARCH are set automatically when --platform is provided.
ARG TARGETOS TARGETARCH

LABEL org.opencontainers.image.authors="Consul Team <consul@hashicorp.com>" \
      org.opencontainers.image.url="https://www.consul.io/" \
      org.opencontainers.image.documentation="https://www.consul.io/docs" \
      org.opencontainers.image.source="https://github.com/hashicorp/consul" \
      org.opencontainers.image.version=${PRODUCT_VERSION} \
      org.opencontainers.image.vendor="HashiCorp" \
      org.opencontainers.image.title="consul" \
      org.opencontainers.image.description="Consul is a datacenter runtime that provides service discovery, configuration, and orchestration." \
      version=${PRODUCT_VERSION}

# Copy license for Red Hat certification.
COPY LICENSE /licenses/mozilla.txt

# Set up certificates and base tools.
# dumb-init is downloaded directly from GitHub because there's no RPM package.
# Its shasum is hardcoded. If you upgrade the dumb-init verion you'll need to
# also update the shasum.
RUN set -eux && \
    microdnf install -y ca-certificates shadow-utils gnupg libcap openssl iputils jq iptables wget unzip tar && \
    wget -O /usr/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v1.2.5/dumb-init_1.2.5_x86_64 && \
    echo 'e874b55f3279ca41415d290c512a7ba9d08f98041b28ae7c2acb19a545f1c4df /usr/bin/dumb-init' > dumb-init-shasum && \
    sha256sum --check dumb-init-shasum && \
    chmod +x /usr/bin/dumb-init

# Create a non-root user to run the software. On OpenShift, this
# will not matter since the container is run as a random user and group
# but this is kept for consistency with our other images.
RUN groupadd $BIN_NAME && \
    adduser --uid 100 --system -g $BIN_NAME $BIN_NAME
COPY dist/$TARGETOS/$TARGETARCH/$BIN_NAME /bin/

# Include EULA and Terms of Eval
RUN mkdir -p /usr/share/doc/consul && \
    curl -o /usr/share/doc/consul/EULA.txt https://eula.hashicorp.com/EULA.txt && \
    curl -o /usr/share/doc/consul/TermsOfEvaluation.txt https://eula.hashicorp.com/TermsOfEvaluation.txt

# The /consul/data dir is used by Consul to store state. The agent will be started
# with /consul/config as the configuration directory so you can add additional
# config files in that location.
# In addition, change the group of the /consul directory to 0 since OpenShift
# will always execute the container with group 0.
RUN mkdir -p /consul/data && \
    mkdir -p /consul/config && \
    chown -R consul /consul && \
    chgrp -R 0 /consul && chmod -R g+rwX /consul

# set up nsswitch.conf for Go's "netgo" implementation which is used by Consul,
# otherwise DNS supercedes the container's hosts file, which we don't want.
RUN test -e /etc/nsswitch.conf || echo 'hosts: files dns' > /etc/nsswitch.conf

# Expose the consul data directory as a volume since there's mutable state in there.
VOLUME /consul/data

# Server RPC is used for communication between Consul clients and servers for internal
# request forwarding.
EXPOSE 8300

# Serf LAN and WAN (WAN is used only by Consul servers) are used for gossip between
# Consul agents. LAN is within the datacenter and WAN is between just the Consul
# servers in all datacenters.
EXPOSE 8301 8301/udp 8302 8302/udp

# HTTP and DNS (both TCP and UDP) are the primary interfaces that applications
# use to interact with Consul.
EXPOSE 8500 8600 8600/udp

COPY .release/docker/docker-entrypoint-ubi.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["docker-entrypoint.sh"]

# OpenShift by default will run containers with a random user, however their
# scanner requires that containers set a non-root user.
USER 100

# By default you'll get an insecure single-node development server that stores
# everything in RAM, exposes a web UI and HTTP endpoints, and bootstraps itself.
# Don't use this configuration for production.
CMD ["agent", "-dev", "-client", "0.0.0.0"]