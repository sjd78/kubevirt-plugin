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
#   RUNNER_SCALE_SET_NAME  - Name for the runner scale set (default: "kubevirt-plugin-ci")
#   MIN_RUNNERS            - Minimum number of runners (default: 0)
#   MAX_RUNNERS            - Maximum number of runners (default: 5)
#   ARC_CONTROLLER_NS      - Namespace for the ARC controller (default: "arc-systems")
#   ARC_RUNNERS_NS         - Namespace for the runners (default: "arc-runners")
#   ARC_VERSION            - Helm chart version (default: latest)
#   CONTAINER_MODE         - Set to "dind" to enable Docker-in-Docker for container jobs (default: unset)
#   ARC_RUNNER_VALUES_FILE - Path to a YAML file to merge for gha-runner-scale-set (template, custom image, etc.)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ci-tools.sh"

ARC_CONFIG_URL="${ARC_CONFIG_URL:?ARC_CONFIG_URL is required}"
RUNNER_SCALE_SET_NAME="${RUNNER_SCALE_SET_NAME:-kubevirt-plugin-ci}"
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

# --- Ensure tools are available ---
ensure_helm
ensure_oc

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
helm upgrade --install arc \
  ${VERSION_FLAG} \
  --namespace "${ARC_CONTROLLER_NS}" \
  "${ARC_HELM_REPO}/gha-runner-scale-set-controller" \
  --wait

echo "ARC controller installed successfully"

# --- Build authentication args ---
# Chart and controller require GitHub App ID and Installation ID as strings (not numbers),
# otherwise they get JSON-serialized as float and strconv.ParseInt fails (e.g. "1.14550292e+08").
# All GitHub App inputs are written into a single YAML values file (no yq/jinja required).
AUTH_ARGS=()
AUTH_VALUES_FILE=""
if [[ -n "${ARC_APP_ID:-}" && -n "${ARC_APP_INSTALL_ID:-}" && -n "${ARC_APP_PRIVATE_KEY:-}" ]]; then
  echo "Using GitHub App authentication"
  AUTH_VALUES_FILE=$(mktemp)
  {
    echo 'githubConfigSecret:'
    echo "  github_app_id: \"${ARC_APP_ID}\""
    echo "  github_app_installation_id: \"${ARC_APP_INSTALL_ID}\""
    echo '  github_app_private_key: |'
    echo "${ARC_APP_PRIVATE_KEY}" | sed 's/^/    /'
  } > "${AUTH_VALUES_FILE}"
  AUTH_ARGS+=(--values "${AUTH_VALUES_FILE}")
elif [[ -n "${ARC_PAT:-}" ]]; then
  echo "Using Personal Access Token authentication"
  AUTH_ARGS+=(--set "githubConfigSecret.github_token=${ARC_PAT}")
else
  echo "ERROR: No authentication configured."
  echo "Set ARC_APP_ID + ARC_APP_INSTALL_ID + ARC_APP_PRIVATE_KEY, or ARC_PAT"
  exit 1
fi

# --- Install runner scale set ---
# Optional: enable Docker-in-Docker for workflows that use container jobs or container actions.
# Optional: custom runner image, resources, or other template overrides via ARC_RUNNER_VALUES_FILE
# (see https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/deploying-runner-scale-sets-with-actions-runner-controller)
#
# https://github.com/actions/actions-runner-controller/blob/master/charts/gha-runner-scale-set/values.yaml
#
RUNNER_SET_ARGS=(
  --set "githubConfigUrl=${ARC_CONFIG_URL}"
  --set "minRunners=${MIN_RUNNERS}"
  --set "maxRunners=${MAX_RUNNERS}"
  "${AUTH_ARGS[@]}"
)
if [[ -n "${CONTAINER_MODE:-}" ]]; then
  echo "Enabling container mode: ${CONTAINER_MODE}"
  RUNNER_SET_ARGS+=(--set "containerMode.type=${CONTAINER_MODE}")
fi
if [[ -n "${ARC_RUNNER_VALUES_FILE:-}" && -f "${ARC_RUNNER_VALUES_FILE}" ]]; then
  echo "Using runner values file: ${ARC_RUNNER_VALUES_FILE}"
  RUNNER_SET_ARGS+=(--values "${ARC_RUNNER_VALUES_FILE}")
fi

echo "Installing ARC runner scale set '${RUNNER_SCALE_SET_NAME}'..."
helm upgrade --install "${RUNNER_SCALE_SET_NAME}" \
  ${VERSION_FLAG} \
  --namespace "${ARC_RUNNERS_NS}" \
  "${RUNNER_SET_ARGS[@]}" \
  "${ARC_HELM_REPO}/gha-runner-scale-set" \
  --wait

[[ -n "${AUTH_VALUES_FILE:-}" ]] && rm -f "${AUTH_VALUES_FILE}"

echo ""
echo "=== ARC Installation Complete ==="
echo "Runner scale set '${RUNNER_SCALE_SET_NAME}' is registered."
echo "Use 'runs-on: ${RUNNER_SCALE_SET_NAME}' in workflow files to target these runners."
echo ""
echo "Optional: To use a custom runner image (e.g. with podman or extra tools), set"
echo "  ARC_RUNNER_VALUES_FILE to a YAML file that overrides template.spec.containers."
echo ""
echo "Optional: For workflows that use container jobs or Docker actions, set"
echo "  CONTAINER_MODE=dind before re-running this script (or add to your values file)."
