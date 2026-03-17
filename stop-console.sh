#!/usr/bin/env bash
# Stops the off-cluster console and plugin containers started for E2E (e.g. by
# start-console.sh and the workflow's plugin container). Safe to run if none
# are running.

set -euo pipefail

CONSOLE_IMAGE="${CONSOLE_IMAGE:-quay.io/openshift/origin-console:latest}"
PLUGIN_CONTAINER_NAME="${PLUGIN_CONTAINER_NAME:-kubevirt-plugin}"

stop_console() {
  if command -v podman &>/dev/null; then
    ids=$(podman ps -q -f "ancestor=${CONSOLE_IMAGE}" 2>/dev/null || true)
    if [ -n "$ids" ]; then
      echo "Stopping console container(s) (${CONSOLE_IMAGE})..."
      echo "$ids" | xargs -r podman stop -t 10
    fi
  elif command -v docker &>/dev/null; then
    ids=$(docker ps -q -f "ancestor=${CONSOLE_IMAGE}" 2>/dev/null || true)
    if [ -n "$ids" ]; then
      echo "Stopping console container(s) (${CONSOLE_IMAGE})..."
      echo "$ids" | xargs -r docker stop -t 10
    fi
  fi
}

stop_plugin() {
  if command -v podman &>/dev/null; then
    if podman ps -q -f "name=${PLUGIN_CONTAINER_NAME}" 2>/dev/null | grep -q .; then
      echo "Stopping plugin container (${PLUGIN_CONTAINER_NAME})..."
      podman stop -t 10 "${PLUGIN_CONTAINER_NAME}" 2>/dev/null || true
    fi
  elif command -v docker &>/dev/null; then
    if docker ps -q -f "name=${PLUGIN_CONTAINER_NAME}" 2>/dev/null | grep -q .; then
      echo "Stopping plugin container (${PLUGIN_CONTAINER_NAME})..."
      docker stop -t 10 "${PLUGIN_CONTAINER_NAME}" 2>/dev/null || true
    fi
  fi
}

stop_plugin
stop_console
echo "Console and plugin containers stopped."
