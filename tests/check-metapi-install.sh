#!/usr/bin/env bash
set -euo pipefail

# Test: metapi Quadlet unit is present in the recipe
# Verifies that files/system/etc/containers/systemd/users/metapi.container exists
# and will be baked into the image via files.yml

QUADLET_UNIT="files/system/etc/containers/systemd/users/metapi.container"

if [[ ! -f "${QUADLET_UNIT}" ]]; then
    echo "FAIL: ${QUADLET_UNIT} not found"
    exit 1
fi

# Verify the unit references the correct image and port binding
if ! grep -q 'Image=docker.io/1467078763/metapi' "${QUADLET_UNIT}"; then
    echo "FAIL: ${QUADLET_UNIT} missing metapi image reference"
    exit 1
fi

if ! grep -q 'PublishPort=127.0.0.1:4000:4000' "${QUADLET_UNIT}"; then
    echo "FAIL: ${QUADLET_UNIT} missing localhost port binding"
    exit 1
fi

if ! grep -q 'Volume=metapi-data:/app/data' "${QUADLET_UNIT}"; then
    echo "FAIL: ${QUADLET_UNIT} missing metapi-data volume mount"
    exit 1
fi

# Secrets must NOT be baked into the image — they're provided via local drop-in.
# Assert no hardcoded secret values leaked into the committed unit.
if grep -qE '^Environment=(AUTH_TOKEN|PROXY_TOKEN|ACCOUNT_CREDENTIAL_SECRET)=' "${QUADLET_UNIT}"; then
    echo "FAIL: ${QUADLET_UNIT} bakes a secret into the image — secrets must be runtime-only"
    exit 1
fi

echo "PASS: metapi Quadlet unit is correctly defined"
