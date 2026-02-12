#!/bin/bash

# get-ksu-version.sh — Extract KernelSU version from installed driver
#
# This script extracts the KernelSU version from the installed driver after
# KernelSU has been installed into the kernel tree.
#
# Detection methods (in order):
#  1. Symlink method: For setup.sh installations (finds KernelSU-Next repo)
#  2. Direct git: For direct clones (checks drivers/kernelsu/.git)
#  3. Kbuild fallback: Extracts from KSU_VERSION_TAG_FALLBACK
#  4. Numeric fallback: Uses KSU_VERSION_FALLBACK to compute version
#
# Outputs: ksu_version.txt in project root

set -e

# Colors
GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
NC='\033[0m'

# Script is in scripts/ subdirectory
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL_DIR="$SCRIPT_DIR/kernel"
KBUILD_FILE="$KERNEL_DIR/drivers/kernelsu/Kbuild"
VERSION_FILE="$SCRIPT_DIR/ksu_version.txt"

echo ""
echo "========================================"
echo -e "${GREEN}  Extracting KernelSU Version${NC}"
echo "========================================"
echo ""

# Check if KernelSU driver is installed
if [ ! -f "$KBUILD_FILE" ]; then
  echo -e "${RED}ERROR: KernelSU driver not found at $KBUILD_FILE${NC}"
  echo "Make sure KernelSU is installed before running this script."
  exit 1
fi

echo "KernelSU Kbuild file: $KBUILD_FILE"
echo ""

# Extract version information from Kbuild
# The Kbuild file has variables like:
# KSU_VERSION := $(shell ... git describe --tags)
# KSU_VERSION_FALLBACK := 30XXX
# KSU_VERSION_TAG_FALLBACK := vX.X.X

echo "Extracting version from Kbuild..."

# Method 1: Check if drivers/kernelsu is a symlink (setup.sh method)
if [ -L "$KERNEL_DIR/drivers/kernelsu" ]; then
  echo "  Method: Symlink detected (setup.sh installation)"

  # Find the KernelSU-Next repository (setup.sh clones it at project root or kernel root)
  KSU_REPO_DIR=""
  for possible_dir in "$SCRIPT_DIR/KernelSU-Next" "$KERNEL_DIR/../KernelSU-Next" "$KERNEL_DIR/KernelSU-Next"; do
    if [ -d "$possible_dir/.git" ]; then
      KSU_REPO_DIR="$possible_dir"
      break
    fi
  done

  if [ -n "$KSU_REPO_DIR" ]; then
    echo "  Found KernelSU-Next repository at: $KSU_REPO_DIR"
    KSU_VERSION=$(cd "$KSU_REPO_DIR" && git describe --tags --always 2>/dev/null || echo "")

    if [ -n "$KSU_VERSION" ]; then
      # Remove 'v' prefix if present (workflow adds it back)
      KSU_VERSION="${KSU_VERSION#v}"
      echo -e "${GREEN}  ✓ Version from git: $KSU_VERSION${NC}"
      echo "$KSU_VERSION" >"$VERSION_FILE"
      echo ""
      echo "Version saved to: $VERSION_FILE"
      exit 0
    fi
  else
    echo -e "${YELLOW}  ⚠ Symlink found but KernelSU-Next repo not located${NC}"
  fi
fi

# Method 2: Check if drivers/kernelsu is a direct git clone
if [ -d "$KERNEL_DIR/drivers/kernelsu/.git" ]; then
  echo "  Method: Git repository (direct clone)"
  KSU_VERSION=$(cd "$KERNEL_DIR/drivers/kernelsu" && git describe --tags --always 2>/dev/null || echo "")

  if [ -n "$KSU_VERSION" ]; then
    # Remove 'v' prefix if present (workflow adds it back)
    KSU_VERSION="${KSU_VERSION#v}"
    echo -e "${GREEN}  ✓ Version from git: $KSU_VERSION${NC}"
    echo "$KSU_VERSION" >"$VERSION_FILE"
    echo ""
    echo "Version saved to: $VERSION_FILE"
    exit 0
  fi
fi

# If git method failed, extract from Kbuild fallback values
echo "  Method: Kbuild fallback values"

# Extract KSU_VERSION_TAG_FALLBACK
KSU_TAG=$(grep "^KSU_VERSION_TAG_FALLBACK :=" "$KBUILD_FILE" | sed 's/^KSU_VERSION_TAG_FALLBACK := //' || echo "")

if [ -n "$KSU_TAG" ] && [ "$KSU_TAG" != "v0.0.1" ]; then
  # Remove 'v' prefix if present (workflow adds it back)
  KSU_TAG="${KSU_TAG#v}"
  echo -e "${GREEN}  ✓ Version from Kbuild: $KSU_TAG${NC}"
  echo "$KSU_TAG" >"$VERSION_FILE"
else
  # Fallback: try to compute from numeric version
  KSU_VERSION_NUM=$(grep "^KSU_VERSION_FALLBACK :=" "$KBUILD_FILE" | sed 's/^KSU_VERSION_FALLBACK := //' || echo "1")

  if [ "$KSU_VERSION_NUM" != "1" ]; then
    # For SUSFS variants, version is usually 30000 + commits + 60
    # We can't reverse-compute the exact tag, but we can show the version
    KSU_TAG="1.0-build-${KSU_VERSION_NUM}"
    echo -e "${YELLOW}  ⚠ Using computed version: $KSU_TAG${NC}"
  else
    # Ultimate fallback
    KSU_TAG="1.0-unknown"
    echo -e "${YELLOW}  ⚠ Using fallback version: $KSU_TAG${NC}"
  fi

  echo "$KSU_TAG" >"$VERSION_FILE"
fi

echo ""
echo "========================================"
echo -e "${GREEN}  KernelSU Version Extracted${NC}"
echo "========================================"
echo ""
echo "Version: $(cat "$VERSION_FILE")"
echo "Saved to: $VERSION_FILE"
echo ""
