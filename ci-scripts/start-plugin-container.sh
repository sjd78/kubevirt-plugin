#! /bin/bash
set -euox pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ARC jobs use Docker-in-Docker (DOCKER_HOST); prefer docker so ports publish on the dind host.
# If podman is also on PATH, `podman || docker` would bypass the daemon jobs use for `docker run`.
if [[ -n "${DOCKER_HOST:-}" ]] && command -v docker &>/dev/null; then
  RUNTIME=$(command -v docker)
elif command -v podman &>/dev/null; then
  RUNTIME=$(command -v podman)
else
  RUNTIME=$(command -v docker)
fi
PLUGIN_NAME=${PLUGIN_NAME:-kubevirt-plugin-ci}

# :z is for Podman SELinux; plain Docker (incl. dind) uses :ro only.
VOL_SUFFIX=":ro"
[[ "${RUNTIME}" == *podman ]] && VOL_SUFFIX=":ro,z"

#
# If the PLUGIN_IMAGE is not set, build it locally.
#
if [[ -z "${PLUGIN_IMAGE:-}" ]]; then
  PLUGIN_IMAGE="localhost/kubevirt-plugin:local"
  $RUNTIME build -t "${PLUGIN_IMAGE}" -f Dockerfile "${REPO_ROOT}"
fi
echo "Using PLUGIN_IMAGE: ${PLUGIN_IMAGE}"

#
# Create the self-signed certs
#
# With Docker-in-Docker (ARC), bind-mount sources must exist on the docker *daemon* host. Paths under
# $TMPDIR (e.g. /home/runner/.tmp) are often not shared with dind, so the mount appears empty in the
# container and nginx fails: cannot load certificate "/var/serving-cert/tls.crt". Use the workspace.
#
CERT_PARENT="${GITHUB_WORKSPACE:-${REPO_ROOT}}"
KUBEVIRT_PLUGIN_CERT_DIR=$(mktemp -d "${CERT_PARENT}/.tmp-plugin-cert.XXXXXX")
openssl req -x509 -nodes -days 1 -newkey rsa:2048 \
  -keyout "${KUBEVIRT_PLUGIN_CERT_DIR}/tls.key" \
  -out "${KUBEVIRT_PLUGIN_CERT_DIR}/tls.crt" \
  -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,DNS:host.docker.internal"
chmod a+rx "${KUBEVIRT_PLUGIN_CERT_DIR}"
chmod a+r "${KUBEVIRT_PLUGIN_CERT_DIR}/tls.crt" "${KUBEVIRT_PLUGIN_CERT_DIR}/tls.key"

#
# Start the plugin container with the self-signed certs and nginx `nginx-9443.conf` config
# mounted into the container.  This emulates how the pod is deployed with the kubevirt operator
# using a ConfigMap and Secrets mounted into the container.
#
# Do not use the image CMD (/usr/libexec/s2i/run): it rewrites /etc/nginx/nginx.conf, which fails
# when this path is a read-only bind mount — the container then exits immediately (--rm removes it).
# Run nginx in the foreground with our config instead (same pattern as openshift/console plugin images).
#
$RUNTIME rm -f "${PLUGIN_NAME}" 2>/dev/null || true
$RUNTIME run -d \
  --name "${PLUGIN_NAME}" \
  --entrypoint nginx \
  -p ${PLUGIN_PORT:-9001}:9443 \
  -v "${SCRIPT_DIR}/nginx-9443.conf:/etc/nginx/nginx.conf${VOL_SUFFIX}" \
  -v "${KUBEVIRT_PLUGIN_CERT_DIR}:/var/serving-cert${VOL_SUFFIX}" \
  "${PLUGIN_IMAGE}"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "<details><summary>Kubevirt Plugin Container</summary>"
    echo ""
    echo "| Item | Value |"
    echo "|------|-------|"
    echo "| Plugin image | \`${PLUGIN_IMAGE}\` |"
    echo "| Plugin port | \`${PLUGIN_PORT:-9001}\` |"
    echo ""
    echo "</details>"
  } >> "${GITHUB_STEP_SUMMARY}"
fi