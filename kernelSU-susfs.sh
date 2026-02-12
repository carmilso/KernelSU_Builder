#!/bin/bash

# kernelSU-susfs.sh — Install KernelSU-Next-SUSFS driver for non-GKI kernels
#
# This script clones the wshamroukh KernelSU-Next-SUSFS driver and installs
# it into the kernel tree. It also computes and injects the proper KSU version
# into the driver's Kbuild file.
#
# Usage: Called from workflow when kernelSU.type = susfs-legacy in sources.yaml

set -e

# Define colors
GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
NC='\033[0m' # No Color

# Get configuration from sources.yaml via environment variables
REPO_URL=${KSU_REPO_URL}
BRANCH=${KSU_BRANCH}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KERNEL_DIR="$SCRIPT_DIR/kernel"
DRIVER_DIR="$SCRIPT_DIR/KernelSU-Next-SUSFS-kernelv4.19"

step() {
  echo ""
  echo "========================================"
  echo -e "${GREEN}  $1${NC}"
  echo "========================================"
  echo ""
}

error() {
  echo ""
  echo -e "${RED}ERROR: $1${NC}"
  echo ""
  exit 1
}

# =====================================================================
# Step 1: Clone or update KernelSU-Next-SUSFS driver
# =====================================================================
step "Step 1: Clone or update KernelSU-Next-SUSFS driver"

if [ -z "$REPO_URL" ] || [ -z "$BRANCH" ]; then
  error "KSU_REPO_URL and KSU_BRANCH environment variables must be set"
fi

echo "Repository: $REPO_URL"
echo "Branch: $BRANCH"
echo ""

if [ -d "$DRIVER_DIR/.git" ]; then
  echo "KSU driver repo already exists, pulling latest changes..."
  git -C "$DRIVER_DIR" pull --ff-only || echo "WARNING: pull failed, continuing with current state"
else
  echo "Cloning KernelSU-Next-SUSFS driver..."
  git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$DRIVER_DIR"
fi

# Unshallow if needed — required for accurate version computation (commit count)
if [ -f "$DRIVER_DIR/.git/shallow" ]; then
  echo "Unshallowing KSU driver repo for version detection..."
  git -C "$DRIVER_DIR" fetch --unshallow
fi

echo ""
echo -e "${GREEN}KernelSU-Next-SUSFS driver ready.${NC}"

# =====================================================================
# Step 2: Install KernelSU driver into kernel tree
# =====================================================================
step "Step 2: Install KernelSU driver into drivers/kernelsu/"

if [ ! -d "$KERNEL_DIR" ]; then
  error "Kernel directory not found at $KERNEL_DIR"
fi

# Remove old driver if present
rm -rf "$KERNEL_DIR/drivers/kernelsu"

echo "Copying wshamroukh KernelSU driver kernel/ -> drivers/kernelsu/..."
cp -r "$DRIVER_DIR/kernel" "$KERNEL_DIR/drivers/kernelsu"

echo "Contents of drivers/kernelsu/:"
ls "$KERNEL_DIR/drivers/kernelsu/" | head -20
echo "..."
echo "Total files: $(ls "$KERNEL_DIR/drivers/kernelsu/" | wc -l)"

# =====================================================================
# Step 3: Inject proper KSU version into Kbuild
# =====================================================================
step "Step 3: Inject proper KSU version into Kbuild"

echo "The Kbuild git detection fails because driver files are copied (not a git repo)."
echo "Without this fix, KSU_VERSION=1 and KSU_VERSION_TAG=v0.0.1 (useless defaults)."
echo "We compute the real version from the SUSFS driver repo's git history and update"
echo "the Kbuild fallback values so the KernelSU Manager app shows the correct version."
echo ""

KBUILD_FILE="$KERNEL_DIR/drivers/kernelsu/Kbuild"

if [ ! -f "$KBUILD_FILE" ]; then
  error "Kbuild file not found at $KBUILD_FILE"
fi

# Get commit count from the SUSFS driver repo
KSU_COMMIT_COUNT=$(git -C "$DRIVER_DIR" rev-list --count HEAD 2>/dev/null || echo "0")

if [ "$KSU_COMMIT_COUNT" -gt 0 ]; then
  # Formula matches the SUSFS variant's Kbuild: 30000 + commit_count + 60
  KSU_COMPUTED_VERSION=$((30000 + KSU_COMMIT_COUNT + 60))

  # For the tag: try the driver repo first, then construct from the latest commit
  KSU_TAG=$(git -C "$DRIVER_DIR" describe --tags --abbrev=0 2>/dev/null || true)
  if [ -z "$KSU_TAG" ]; then
    # Driver repo has no tags — construct a version tag from the short commit hash
    KSU_SHORT_HASH=$(git -C "$DRIVER_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    KSU_TAG="v1.0-susfs-${KSU_SHORT_HASH}"
  fi

  echo "Setting KSU version in Kbuild:"
  echo "  Commit count : $KSU_COMMIT_COUNT"
  echo "  KSU_VERSION  : $KSU_COMPUTED_VERSION"
  echo "  KSU_VERSION_TAG: $KSU_TAG"
  echo ""

  # Update the fallback values in the copied Kbuild
  sed -i "s/^KSU_VERSION_FALLBACK := 1$/KSU_VERSION_FALLBACK := $KSU_COMPUTED_VERSION/" "$KBUILD_FILE"
  sed -i "s/^KSU_VERSION_TAG_FALLBACK := v0.0.1$/KSU_VERSION_TAG_FALLBACK := $KSU_TAG/" "$KBUILD_FILE"

  # Verify the changes took effect
  if grep -q "KSU_VERSION_FALLBACK := $KSU_COMPUTED_VERSION" "$KBUILD_FILE"; then
    echo -e "${GREEN}Kbuild version fallback updated successfully.${NC}"
  else
    echo -e "${YELLOW}WARNING: Failed to update KSU_VERSION_FALLBACK in Kbuild.${NC}"
  fi

  # Save version for workflow
  echo "$KSU_TAG" > "$SCRIPT_DIR/ksu_version.txt"
  echo ""
  echo "KSU version saved to ksu_version.txt"
else
  echo -e "${YELLOW}WARNING: Could not determine KSU commit count. Version will use defaults.${NC}"
  echo "v1.0-susfs-unknown" > "$SCRIPT_DIR/ksu_version.txt"
fi

# =====================================================================
# Done
# =====================================================================
echo ""
echo "========================================"
echo -e "${GREEN}  KernelSU-Next-SUSFS Installation Complete!${NC}"
echo "========================================"
echo ""
echo "Summary:"
echo "  - Driver repository: $REPO_URL"
echo "  - Branch: $BRANCH"
echo "  - Version: $(cat "$SCRIPT_DIR/ksu_version.txt")"
echo "  - Install path: $KERNEL_DIR/drivers/kernelsu/"
echo ""
echo "Next steps:"
echo "  1. Apply SUSFS patches and hooks (run apply-susfs.sh)"
echo "  2. Configure kernel"
echo "  3. Build kernel"
echo ""
