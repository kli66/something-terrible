#!/usr/bin/env bash
set -euo pipefail

# Test: LiteLLM Quadlet unit is present in the recipe
# Verifies that files/system/etc/containers/systemd/users/litellm.container exists
# and will be baked into the image via files.yml

QUADLET_UNIT="files/system/etc/containers/systemd/users/litellm.container"

if [[ ! -f "${QUADLET_UNIT}" ]]; then
    echo "FAIL: ${QUADLET_UNIT} not found"
    exit 1
fi

# Verify the unit references the correct image and port binding
if ! grep -q 'Image=ghcr.io/berriai/litellm:v' "${QUADLET_UNIT}"; then
    echo "FAIL: ${QUADLET_UNIT} missing ghcr.io/berriai/litellm image reference"
    exit 1
fi

if ! grep -q 'PublishPort=127.0.0.1:4000:4000' "${QUADLET_UNIT}"; then
    echo "FAIL: ${QUADLET_UNIT} missing localhost port binding"
    exit 1
fi

if ! grep -q 'Volume=%h/.config/litellm/config.yaml:/app/config.yaml' "${QUADLET_UNIT}"; then
    echo "FAIL: ${QUADLET_UNIT} missing config.yaml volume mount"
    exit 1
fi

echo "PASS: LiteLLM Quadlet unit is correctly defined"
