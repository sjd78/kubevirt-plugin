# Custom GitHub Actions runner image for hot-cluster CI.
# Extends the official runner image with Node.js, kubectl, oc, and virtctl
# so workflows do not need to install them at job start.
#
# Build on the cluster with: ci-scripts/build-arc-runner-image.sh
# Then configure ARC to use the built image via ARC_RUNNER_VALUES_FILE.

ARG RUNNER_BASE=ghcr.io/actions/actions-runner:latest
FROM ${RUNNER_BASE}

USER root

# Versions (override with build-args to match cluster)
ARG NODE_VERSION=22
ARG KUBECTL_VERSION=
ARG VIRTCTL_VERSION=v1.4.0
# OpenShift client version to match cluster (e.g. 4.20)
ARG OC_VERSION=4.20

# Node.js (LTS)
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# kubectl (stable)
RUN curl -fsSL "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# OpenShift client (oc); mirror uses stable-4.x or latest-4.x
RUN curl -fsSL "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-${OC_VERSION}/openshift-client-linux.tar.gz" | tar -xzf - -C /usr/local/bin

# virtctl (KubeVirt CLI)
RUN VIRTCTL_URL="https://github.com/kubevirt/kubevirt/releases/download/${VIRTCTL_VERSION}/virtctl-${VIRTCTL_VERSION}-linux-amd64" \
    && curl -fsSL "${VIRTCTL_URL}" -o /usr/local/bin/virtctl \
    && chmod +x /usr/local/bin/virtctl

# Writable dirs for npm under runner HOME (OpenShift non-root: only HOME is reliably writable)
# Note: The rw volume needs to be available in the running container
RUN mkdir -p /home/runner/.npm /home/runner/.tmp \
    && chown -R runner:root /home/runner
    # && npm -g config set cache /home/runner/.npm \
    # && npm -g config set tmp /home/runner/.tmp

USER runner

# Default npm and tmp to HOME so npm ci works in restricted containers without workflow overrides
ENV KUBEVIRT_UI_PLUGIN_RUNNER=true \
    HOME=/home/runner \
    TMPDIR=/home/runner/.tmp

# Keep the same entrypoint/CMD as the base image so ARC works unchanged.
