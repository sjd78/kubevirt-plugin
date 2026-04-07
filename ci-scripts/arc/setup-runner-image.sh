#!/bin/bash
#
# OpenShift only: create ImageStream + BuildConfig and run a binary Docker build for the
# custom ARC runner image (ci-scripts/arc/runner-image/Dockerfile).
#
# Output: prints IMAGE_REF= to stdout (and to ARC_RUNNER_IMAGE_FILE if set).
# Run setup-dind-mirror.sh first if you need an internal docker:dind mirror (optional).
#
# Optional environment variables:
#   ARC_RUNNERS_NS   (default: arc-runners)
#   OC_VERSION       OpenShift client version build-arg (default: detect or 4.20)
#   VIRTCTL_VERSION  (default: v1.4.0)
#
# Requires: oc logged into OpenShift; jq optional for version detection and URL resolution.
#
# Binary URL resolution:
#   When jq is available, this script queries ConsoleCLIDownload resources to find the
#   exact binary download URLs for oc, kubectl, and virtctl that match the live cluster.
#   These are passed to the Docker build as OC_URL, KUBECTL_URL, and VIRTCTL_URL build-args.
#   If resolution fails (CRD not found, jq absent, etc.), the Dockerfile falls back to
#   mirror.openshift.com / dl.k8s.io / GitHub releases using OC_VERSION / VIRTCTL_VERSION.

set -euo pipefail
ARC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI_SCRIPTS_DIR="$(cd "${ARC_DIR}/.." && pwd)"
source "${CI_SCRIPTS_DIR}/ci-tools.sh"

ARC_RUNNERS_NS="${ARC_RUNNERS_NS:-arc-runners}"
RUNNER_IMAGE_DIR="${ARC_DIR}/runner-image"

ensure_oc

if ! oc get clusterversion version &>/dev/null; then
  echo "ERROR: OpenShift cluster required (clusterversion.version not found)."
  exit 1
fi

if [[ -z "${OC_VERSION:-}" ]]; then
  OC_VERSION=$(oc version --output json 2>/dev/null | jq -r '.openshiftVersion | split(".") | .[0:2] | join(".") // empty') || true
  OC_VERSION="${OC_VERSION:-4.20}"
fi
VIRTCTL_VERSION="${VIRTCTL_VERSION:-v1.4.0}"

# Resolve binary download URLs from ConsoleCLIDownload resources so the image binaries
# match the live cluster exactly. Requires jq; silently skipped if unavailable.
OC_URL=""
KUBECTL_URL=""
VIRTCTL_URL=""
if command -v jq &>/dev/null; then
  OC_DOWNLOAD_JSON=$(oc get consoleclidownload oc-cli-downloads -o json 2>/dev/null || true)
  if [[ -n "${OC_DOWNLOAD_JSON}" ]]; then
    OC_URL=$(echo "${OC_DOWNLOAD_JSON}" \
      | jq -r '.spec.links[] | select(.text | test("oc.*linux.*x86_64|oc.*linux.*amd64"; "i")) | .href' \
      | head -1)
    KUBECTL_URL=$(echo "${OC_DOWNLOAD_JSON}" \
      | jq -r '.spec.links[] | select(.text | test("kubectl.*linux.*x86_64|kubectl.*linux.*amd64"; "i")) | .href' \
      | head -1)
  fi
  VIRTCTL_URL=$(oc get consoleclidownload -o json 2>/dev/null \
    | jq -r '.items[].spec.links[] | select(.text | test("virtctl.*linux.*amd64|virtctl.*linux.*x86_64"; "i")) | .href' \
    | head -1 || true)
fi

echo "=== Build ARC runner image (in-cluster, OpenShift) ==="
echo "  ARC_RUNNERS_NS:   ${ARC_RUNNERS_NS}"
echo "  OC_VERSION:       ${OC_VERSION}"
echo "  VIRTCTL_VERSION:  ${VIRTCTL_VERSION}"
echo "  RUNNER_IMAGE_DIR: ${RUNNER_IMAGE_DIR}"
echo "  OC_URL:           ${OC_URL:-(fallback to mirror.openshift.com)}"
echo "  KUBECTL_URL:      ${KUBECTL_URL:-(fallback to dl.k8s.io)}"
echo "  VIRTCTL_URL:      ${VIRTCTL_URL:-(fallback to GitHub releases)}"
echo ""

if [[ ! -f "${RUNNER_IMAGE_DIR}/Dockerfile" ]]; then
  echo "ERROR: Dockerfile not found at ${RUNNER_IMAGE_DIR}/Dockerfile"
  exit 1
fi

oc create namespace "${ARC_RUNNERS_NS}" --dry-run=client -o yaml | oc apply -f -

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

EXTRA_BUILD_ARGS=()
[[ -n "${OC_URL}" ]]      && EXTRA_BUILD_ARGS+=(--build-arg "OC_URL=${OC_URL}")
[[ -n "${KUBECTL_URL}" ]] && EXTRA_BUILD_ARGS+=(--build-arg "KUBECTL_URL=${KUBECTL_URL}")
[[ -n "${VIRTCTL_URL}" ]] && EXTRA_BUILD_ARGS+=(--build-arg "VIRTCTL_URL=${VIRTCTL_URL}")

echo "Starting binary build from ${RUNNER_IMAGE_DIR}..."
oc start-build -n "${ARC_RUNNERS_NS}" arc-runner-custom \
  --from-dir="${RUNNER_IMAGE_DIR}" \
  "${EXTRA_BUILD_ARGS[@]}" \
  --follow

IMAGE_REF="image-registry.openshift-image-registry.svc:5000/${ARC_RUNNERS_NS}/arc-runner-custom:latest"
echo ""
echo "=== Build complete ==="
echo "Image: ${IMAGE_REF}"
if [[ -n "${ARC_RUNNER_IMAGE_FILE:-}" ]]; then
  printf '%s\n' "${IMAGE_REF}" > "${ARC_RUNNER_IMAGE_FILE}"
  echo "Wrote ${ARC_RUNNER_IMAGE_FILE}"
fi

echo "IMAGE_REF=${IMAGE_REF}"
