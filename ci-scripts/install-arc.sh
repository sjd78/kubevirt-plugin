#!/bin/bash
#
# Install Actions Runner Controller (ARC) on an OpenShift/Kubernetes cluster.
# Deploys the controller and a runner scale set that registers as self-hosted
# runners with the GitHub repository.
#
# Required environment variables:
#   ARC_CONFIG_URL         - Repository or org URL (e.g., https://github.com/org/repo)
#
# Authentication (one of the following sets):
#   Option A - GitHub App (recommended):
#     ARC_APP_ID             - GitHub App ID
#     ARC_APP_INSTALL_ID     - GitHub App installation ID
#     ARC_APP_PRIVATE_KEY    - GitHub App private key (PEM content)
#
#   Option B - Personal Access Token:
#     ARC_PAT                - Fine-grained PAT with administration:write
#
# Optional environment variables:
#   RUNNER_SCALE_SET_NAME  - Name for the runner scale set (default: "hot-cluster")
#   MIN_RUNNERS            - Minimum number of runners (default: 0)
#   MAX_RUNNERS            - Maximum number of runners (default: 5)
#   ARC_CONTROLLER_NS      - Namespace for the ARC controller (default: "arc-systems")
#   ARC_RUNNERS_NS         - Namespace for the runners (default: "arc-runners")
#   ARC_VERSION            - Helm chart version (default: latest)

set -euo pipefail

ARC_CONFIG_URL="${ARC_CONFIG_URL:?ARC_CONFIG_URL is required}"
RUNNER_SCALE_SET_NAME="${RUNNER_SCALE_SET_NAME:-hot-cluster}"
MIN_RUNNERS="${MIN_RUNNERS:-0}"
MAX_RUNNERS="${MAX_RUNNERS:-5}"
ARC_CONTROLLER_NS="${ARC_CONTROLLER_NS:-arc-systems}"
ARC_RUNNERS_NS="${ARC_RUNNERS_NS:-arc-runners}"
ARC_VERSION="${ARC_VERSION:-}"

ARC_HELM_REPO="oci://ghcr.io/actions/actions-runner-controller-charts"

echo "=== ARC Installation ==="
echo "  ARC_CONFIG_URL:        ${ARC_CONFIG_URL}"
echo "  RUNNER_SCALE_SET_NAME: ${RUNNER_SCALE_SET_NAME}"
echo "  MIN_RUNNERS:           ${MIN_RUNNERS}"
echo "  MAX_RUNNERS:           ${MAX_RUNNERS}"
echo "  ARC_CONTROLLER_NS:     ${ARC_CONTROLLER_NS}"
echo "  ARC_RUNNERS_NS:        ${ARC_RUNNERS_NS}"
echo ""

# --- Ensure Helm is available ---
if ! command -v helm &>/dev/null; then
  echo "Installing Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# --- Build version flag ---
VERSION_FLAG=""
if [[ -n "${ARC_VERSION}" ]]; then
  VERSION_FLAG="--version ${ARC_VERSION}"
fi

# --- Create namespaces ---
echo "Creating namespaces..."
oc create namespace "${ARC_CONTROLLER_NS}" --dry-run=client -o yaml | oc apply -f -
oc create namespace "${ARC_RUNNERS_NS}" --dry-run=client -o yaml | oc apply -f -

# --- Install ARC controller ---
echo "Installing ARC controller..."
helm install arc \
  ${VERSION_FLAG} \
  --namespace "${ARC_CONTROLLER_NS}" \
  "${ARC_HELM_REPO}/gha-runner-scale-set-controller" \
  --wait

echo "ARC controller installed successfully"

# --- Build authentication args ---
AUTH_ARGS=""
if [[ -n "${ARC_APP_ID:-}" && -n "${ARC_APP_INSTALL_ID:-}" && -n "${ARC_APP_PRIVATE_KEY:-}" ]]; then
  echo "Using GitHub App authentication"
  AUTH_ARGS="--set githubConfigSecret.github_app_id=${ARC_APP_ID}"
  AUTH_ARGS="${AUTH_ARGS} --set githubConfigSecret.github_app_installation_id=${ARC_APP_INSTALL_ID}"

  TEMP_KEY_FILE=$(mktemp)
  echo "${ARC_APP_PRIVATE_KEY}" > "${TEMP_KEY_FILE}"
  AUTH_ARGS="${AUTH_ARGS} --set-file githubConfigSecret.github_app_private_key=${TEMP_KEY_FILE}"
elif [[ -n "${ARC_PAT:-}" ]]; then
  echo "Using Personal Access Token authentication"
  AUTH_ARGS="--set githubConfigSecret.github_token=${ARC_PAT}"
else
  echo "ERROR: No authentication configured."
  echo "Set ARC_APP_ID + ARC_APP_INSTALL_ID + ARC_APP_PRIVATE_KEY, or ARC_PAT"
  exit 1
fi

# --- Install runner scale set ---
echo "Installing ARC runner scale set '${RUNNER_SCALE_SET_NAME}'..."
helm install "${RUNNER_SCALE_SET_NAME}" \
  ${VERSION_FLAG} \
  --namespace "${ARC_RUNNERS_NS}" \
  --set githubConfigUrl="${ARC_CONFIG_URL}" \
  --set minRunners="${MIN_RUNNERS}" \
  --set maxRunners="${MAX_RUNNERS}" \
  ${AUTH_ARGS} \
  "${ARC_HELM_REPO}/gha-runner-scale-set" \
  --wait

if [[ -n "${TEMP_KEY_FILE:-}" && -f "${TEMP_KEY_FILE:-}" ]]; then
  rm -f "${TEMP_KEY_FILE}"
fi

echo ""
echo "=== ARC Installation Complete ==="
echo "Runner scale set '${RUNNER_SCALE_SET_NAME}' is registered."
echo "Use 'runs-on: ${RUNNER_SCALE_SET_NAME}' in workflow files to target these runners."
