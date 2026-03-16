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
#   ARC_RUNNERS_NS         - Namespace for runners and built image (default: arc-runners)
#   RUNNER_SCALE_SET_NAME  - Name for the runner scale set (default: "kubevirt-plugin-ci")
#   OC_VERSION             - OpenShift client version to bake in (default: 4.20)
#   VIRTCTL_VERSION        - virtctl version to bake in (default: v1.4.0)
#
# Output: writes the image reference to stdout and to ARC_RUNNER_IMAGE_FILE if set.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUNNER_IMAGE_DIR="${SCRIPT_DIR}/runner-image"

ARC_RUNNERS_NS="${ARC_RUNNERS_NS:-arc-runners}"
RUNNER_SCALE_SET_NAME="${RUNNER_SCALE_SET_NAME:-kubevirt-plugin-ci}"

if [[ -z "${OC_VERSION:-}" ]]; then
  OC_VERSION=$(oc version --output json 2>/dev/null | jq -r '.openshiftVersion | split(".") | .[0:2] | join(".") // empty') || true
  OC_VERSION="${OC_VERSION:-4.20}"
fi
VIRTCTL_VERSION="${VIRTCTL_VERSION:-v1.4.0}"

echo "=== Build ARC runner image (in-cluster) ==="
echo "  ARC_RUNNERS_NS:        ${ARC_RUNNERS_NS}"
echo "  RUNNER_SCALE_SET_NAME: ${RUNNER_SCALE_SET_NAME}"
echo "  OC_VERSION:            ${OC_VERSION}"
echo "  VIRTCTL_VERSION:       ${VIRTCTL_VERSION}"
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


echo ""
echo "=== Update ARC runner scale set ==="
TEMP_VALUES_FILE=$(mktemp --suffix=.yaml)

#
# Values fragment must match gha-runner-scale-set chart: template.spec is the PodSpec,
# containers[0] must be name: runner with image and command (see chart values.yaml).
# Add work volume for /home/runner/_work; npm emptyDirs so cache/tmp are writable (OpenShift random UID).
#
# See the helm chart values.yaml for the available values:
#   https://github.com/actions/actions-runner-controller/blob/master/charts/gha-runner-scale-set/values.yaml
#
cat > "${TEMP_VALUES_FILE}" <<EOF
template:
  spec:
    volumes:
      - name: work
        emptyDir: {}
      - name: npm-cache
        emptyDir: {}
      - name: npm-tmp
        emptyDir: {}
    containers:
      - name: runner
        image: ${IMAGE_REF}
        command:
          - "/home/runner/run.sh"
        volumeMounts:
          - name: work
            mountPath: "/home/runner/_work"
          - name: npm-cache
            mountPath: "/home/runner/.npm"
          - name: npm-tmp
            mountPath: "/home/runner/.tmp"
EOF

helm upgrade "${RUNNER_SCALE_SET_NAME}" oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --namespace "${ARC_RUNNERS_NS}" \
  --reuse-values \
  --values "${TEMP_VALUES_FILE}" \
  --wait

rm -f "${TEMP_VALUES_FILE}"
