#!/bin/bash
#
# Build the custom ARC runner image on the OpenShift cluster and push it to
# the internal registry. Run after install-arc.sh and install-hco.sh so the
# cluster and ARC namespaces exist.
#
# The image includes Node.js, kubectl, oc, and virtctl so workflow jobs do not
# need to install them. Build runs in-cluster; output is available locally
# as image-registry.openshift-image-registry.svc:5000/<ARC_RUNNERS_NS>/arc-runner-custom:latest
#
# Optional environment variables:
#   ARC_RUNNERS_NS   - Namespace for runners and built image (default: arc-runners)
#   OC_VERSION       - OpenShift client version to bake in (default: 4.20)
#   VIRTCTL_VERSION  - virtctl version to bake in (default: v1.4.0)
#
# Output: writes the image reference to stdout and to ARC_RUNNER_IMAGE_FILE if set.

set -euo pipefail

ARC_RUNNERS_NS="${ARC_RUNNERS_NS:-arc-runners}"
OC_VERSION="${OC_VERSION:-4.20}"
VIRTCTL_VERSION="${VIRTCTL_VERSION:-v1.4.0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUNNER_IMAGE_DIR="${SCRIPT_DIR}/runner-image"

echo "=== Build ARC runner image (in-cluster) ==="
echo "  ARC_RUNNERS_NS:  ${ARC_RUNNERS_NS}"
echo "  OC_VERSION:      ${OC_VERSION}"
echo "  VIRTCTL_VERSION: ${VIRTCTL_VERSION}"
echo ""

if [[ ! -f "${RUNNER_IMAGE_DIR}/Dockerfile" ]]; then
  echo "ERROR: Dockerfile not found at ${RUNNER_IMAGE_DIR}/Dockerfile"
  exit 1
fi

# Ensure namespace exists
oc create namespace "${ARC_RUNNERS_NS}" --dry-run=client -o yaml | oc apply -f -

# Create ImageStream so BuildConfig output can resolve (avoids InvalidOutputReference)
oc apply -f - <<EOF
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: arc-runner-custom
  namespace: ${ARC_RUNNERS_NS}
spec:
  lookupPolicy:
    local: true
EOF

# Create or replace BuildConfig for binary Docker build
oc apply -f - <<EOF
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: arc-runner-custom
  namespace: ${ARC_RUNNERS_NS}
spec:
  source:
    type: Binary
    binary: {}
  strategy:
    type: Docker
    dockerStrategy:
      buildArgs:
        - name: OC_VERSION
          value: "${OC_VERSION}"
        - name: VIRTCTL_VERSION
          value: "${VIRTCTL_VERSION}"
  output:
    to:
      kind: ImageStreamTag
      name: arc-runner-custom:latest
  runPolicy: Serial
EOF

echo "Starting build from ${RUNNER_IMAGE_DIR}..."
oc start-build -n "${ARC_RUNNERS_NS}" arc-runner-custom --from-dir="${RUNNER_IMAGE_DIR}" --follow

# Internal registry image reference (runners in same namespace can pull without pull secret)
IMAGE_REF="image-registry.openshift-image-registry.svc:5000/${ARC_RUNNERS_NS}/arc-runner-custom:latest"
echo ""
echo "=== Build complete ==="
echo "Image: ${IMAGE_REF}"

if [[ -n "${ARC_RUNNER_IMAGE_FILE:-}" ]]; then
  echo "${IMAGE_REF}" > "${ARC_RUNNER_IMAGE_FILE}"
  echo "Wrote image ref to ${ARC_RUNNER_IMAGE_FILE}"
fi

# Output for caller (e.g. generate values and upgrade ARC)
echo "${IMAGE_REF}"
