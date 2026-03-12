#!/bin/bash
#
# Write a gha-runner-scale-set values fragment that sets the runner container image.
# Use with ARC_RUNNER_VALUES_FILE when running install-arc.sh to point runners at
# the custom image built by build-arc-runner-image.sh.
#
# Usage: generate-arc-runner-values.sh <image_ref> [output_file]
# Example: generate-arc-runner-values.sh image-registry.../arc-runner-custom:latest /tmp/arc-values.yaml
# If output_file is omitted, writes to stdout.

set -euo pipefail

IMAGE_REF="${1:?Usage: generate-arc-runner-values.sh <image_ref> [output_file]}"
OUTPUT_FILE="${ARC_RUNNER_VALUES_FILE:-${2:-}}"

# Run as UID 1001 (runner user in the image) so /home/runner is writable; OpenShift
# otherwise may use a random UID and the process cannot create /home/runner/.npm/_logs.
YAML="template:
  spec:
    securityContext:
      runAsUser: 1001
      runAsGroup: 1001
      fsGroup: 1001
    containers:
      - name: runner
        image: ${IMAGE_REF}
        command: [\"/home/runner/run.sh\"]
"

if [[ -n "${OUTPUT_FILE}" ]]; then
  echo "${YAML}" > "${OUTPUT_FILE}"
  echo "Wrote ${OUTPUT_FILE}"
else
  echo "${YAML}"
fi
