#!/usr/bin/env bash
set -euo pipefail

# Test: agentsview Quadlet unit is present in the recipe
# Verifies that files/system/etc/containers/systemd/users/agentsview.container exists
# and will be baked into the image via files.yml

QUADLET_UNIT="files/system/etc/containers/systemd/users/agentsview.container"

if [[ ! -f "${QUADLET_UNIT}" ]]; then
    echo "FAIL: ${QUADLET_UNIT} not found"
    exit 1
fi

# Verify the unit references the correct image and port binding
if ! grep -q 'Image=ghcr.io/kenn-io/agentsview' "${QUADLET_UNIT}"; then
    echo "FAIL: ${QUADLET_UNIT} missing ghcr.io/kenn-io/agentsview image reference"
    exit 1
fi

if ! grep -q 'PublishPort=127.0.0.1:8080:8080' "${QUADLET_UNIT}"; then
    echo "FAIL: ${QUADLET_UNIT} missing localhost port binding"
    exit 1
fi

if ! grep -q 'Volume=%h/.claude/projects:/agents/claude' "${QUADLET_UNIT}"; then
    echo "FAIL: ${QUADLET_UNIT} missing Claude projects volume mount"
    exit 1
fi

if ! grep -q 'Environment=CLAUDE_PROJECTS_DIR=/agents/claude' "${QUADLET_UNIT}"; then
    echo "FAIL: ${QUADLET_UNIT} missing CLAUDE_PROJECTS_DIR environment variable"
    exit 1
fi

echo "PASS: agentsview Quadlet unit is correctly defined"
