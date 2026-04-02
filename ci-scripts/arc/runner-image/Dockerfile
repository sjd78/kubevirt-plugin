# Custom GitHub Actions runner image for kubevirt-plugin-ci CI.
# Extends the official runner image with cli tools used in the CI pipeline (such as jq, curl,
# envsubst, Node.js, kubectl, oc, and virtctl) and support for running Cypress tests.

#
# https://github.com/actions/runner/blob/main/images/Dockerfile: the base image
# The base image includes the docker CLI; with ARC containerMode.type=dind, jobs use the
# docker:dind sidecar (DOCKER_HOST=unix:///var/run/docker.sock) for docker/container actions.
#
ARG RUNNER_BASE=ghcr.io/actions/actions-runner:latest
FROM ${RUNNER_BASE}

USER root

# Versions (override with build-args to match cluster)
ARG NODE_VERSION=22
# OpenShift client version to match cluster (e.g. 4.20)
ARG OC_VERSION=4.20
# KubeVirt CLI version to match HCO install (e.g. v1.4.0)
ARG VIRTCTL_VERSION=v1.4.0

# Tools used: jq, curl, envsubst (gettext-base)
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates jq yq curl gettext-base \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Cypress 14+ headless (bundled Electron) — Linux deps for Ubuntu 24.04+ (noble).
# Official runner image is noble (see actions/runner images/Dockerfile: mcr.microsoft.com/dotnet/runtime-deps:8.0-noble).
# Matches Cypress docs: https://docs.cypress.io/guides/getting-started/installing-cypress#Linux — Ubuntu >=24.04 list.
# GitHub-hosted ubuntu-latest (runner-images Ubuntu2404) also includes xvfb, Chrome/Firefox, and extra fonts; for ARC we
# install the minimum Electron stack plus common fonts so screenshots/video match hosted runners more closely.
# unzip is already present in the upstream actions-runner image (needed for fast Cypress binary unpack).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        fontconfig \
        fonts-liberation \
        libasound2t64 \
        libgbm-dev \
        libgtk-3-0t64 \
        libnss3 \
        libnotify-dev \
        libxss1 \
        libxtst6 \
        xauth \
        xvfb \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Node.js (LTS)
RUN apt-get update \
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

USER runner

# Default npm and tmp to HOME so npm ci works in restricted containers without workflow overrides
ENV KUBEVIRT_UI_PLUGIN_RUNNER=true \
    HOME=/home/runner \
    TMPDIR=/home/runner/.tmp

# Keep the same entrypoint/CMD as the base image so ARC works unchanged.
