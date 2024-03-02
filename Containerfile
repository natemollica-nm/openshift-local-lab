# Preparation Build
FROM quay.io/centos/centos:stream9-minimal as prep

# ARG
ARG VERSION

# ENV
ENV VERSION=${VERSION}
ENV ARCH=aarch64

# Download binary
RUN microdnf install tar gzip -y
RUN curl -sLO https://mirror.openshift.com/pub/openshift-v4/${ARCH}/clients/ocp/${VERSION}/openshift-install-linux.tar.gz
RUN curl -sLO https://mirror.openshift.com/pub/openshift-v4/${ARCH}/clients/ocp/${VERSION}/openshift-client-linux.tar.gz
RUN tar xzf openshift-install-linux.tar.gz
RUN tar xzf openshift-client-linux.tar.gz

# Build image
FROM quay.io/centos/centos:stream9-minimal as build

RUN microdnf update -y \
    && microdnf install nmstate -y \
    && microdnf clean all

COPY --from=prep openshift-install /usr/local/bin
COPY --from=prep oc /usr/local/bin

ENTRYPOINT ["/usr/local/bin/openshift-install"]