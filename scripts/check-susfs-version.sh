#!/bin/bash

# check-susfs-version.sh — Check for new SUSFS patch versions
#
# This script compares the local SUSFS patch with the upstream version
# and notifies if a newer version is available.
#
# Usage: ./check-susfs-version.sh

set -e

# Colors
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
NC='\033[0m'

# Script is in scripts/ subdirectory, go up one level to project root
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_PATCH="$SCRIPT_DIR/susfs-2.0.0.patch"
UPSTREAM_URL="https://raw.githubusercontent.com/TheSillyOk/kernel_ls_patches/master/susfs-2.0.0.patch"
TEMP_PATCH="/tmp/susfs-2.0.0-upstream.patch"

echo ""
echo "========================================"
echo "  SUSFS Patch Version Check"
echo "========================================"
echo ""

# Download upstream patch
echo "Downloading upstream SUSFS patch..."
if ! curl -sL -o "$TEMP_PATCH" "$UPSTREAM_URL"; then
  echo -e "${RED}ERROR: Failed to download upstream patch${NC}"
  exit 1
fi

# Compare patches
echo "Comparing local patch with upstream..."
echo ""

LOCAL_SIZE=$(stat -f%z "$LOCAL_PATCH" 2>/dev/null || stat -c%s "$LOCAL_PATCH" 2>/dev/null)
UPSTREAM_SIZE=$(stat -f%z "$TEMP_PATCH" 2>/dev/null || stat -c%s "$TEMP_PATCH" 2>/dev/null)

LOCAL_HASH=$(sha256sum "$LOCAL_PATCH" | awk '{print $1}')
UPSTREAM_HASH=$(sha256sum "$TEMP_PATCH" | awk '{print $1}')

echo "Local patch:"
echo "  Size: $LOCAL_SIZE bytes"
echo "  SHA256: $LOCAL_HASH"
echo ""
echo "Upstream patch:"
echo "  Size: $UPSTREAM_SIZE bytes"
echo "  SHA256: $UPSTREAM_HASH"
echo ""

if [ "$LOCAL_HASH" = "$UPSTREAM_HASH" ]; then
  echo -e "${GREEN}✓ Local patch is up to date!${NC}"
  echo "NEW_SUSFS_VERSION=false" >> $GITHUB_OUTPUT 2>/dev/null || true
else
  echo -e "${YELLOW}⚠ New SUSFS patch version detected!${NC}"
  echo ""
  echo "Differences:"
  diff -u "$LOCAL_PATCH" "$TEMP_PATCH" | head -50 || true
  echo ""
  echo -e "${YELLOW}Consider updating the local patch:${NC}"
  echo "  cp $TEMP_PATCH $LOCAL_PATCH"
  echo ""
  echo "NEW_SUSFS_VERSION=true" >> $GITHUB_OUTPUT 2>/dev/null || true
  echo "SUSFS_UPSTREAM_URL=$UPSTREAM_URL" >> $GITHUB_OUTPUT 2>/dev/null || true
fi

# Cleanup
rm -f "$TEMP_PATCH"

echo ""
echo "========================================"
echo ""
