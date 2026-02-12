#!/bin/bash

# configure-susfs.sh — Configure kernel with KernelSU + SUSFS options
#
# This script applies all necessary kernel configuration options for
# KernelSU with SUSFS support on non-GKI kernels (manual hook mode).
#
# Usage: ./configure-susfs.sh
#
# Expected to run inside the kernel directory with out/.config present.

set -e

# Colors
GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
NC='\033[0m'

CONFIG_FILE="out/.config"

echo ""
echo "========================================"
echo -e "${GREEN}  Configuring KernelSU + SUSFS${NC}"
echo "========================================"
echo ""

if [ ! -f "$CONFIG_FILE" ]; then
  echo -e "${RED}ERROR: $CONFIG_FILE not found!${NC}"
  echo "Run kernel config generation first (e.g., make defconfig)"
  exit 1
fi

echo "Config file: $CONFIG_FILE"
echo ""

# Enable KernelSU
echo "=== Enabling KernelSU ==="
scripts/config --file "$CONFIG_FILE" --enable KSU || { echo -e "${RED}ERROR: Failed to enable KSU${NC}"; exit 1; }
scripts/config --file "$CONFIG_FILE" --disable KSU_DEBUG || { echo -e "${RED}ERROR: Failed to disable KSU_DEBUG${NC}"; exit 1; }

# Force manual hook mode (non-GKI)
echo "=== Configuring manual hooks (non-GKI) ==="
scripts/config --file "$CONFIG_FILE" --enable KSU_MANUAL_HOOK || { echo -e "${RED}ERROR: Failed to enable KSU_MANUAL_HOOK${NC}"; exit 1; }
scripts/config --file "$CONFIG_FILE" --disable KSU_KPROBES_HOOK || { echo -e "${RED}ERROR: Failed to disable KSU_KPROBES_HOOK${NC}"; exit 1; }

# Enable SUSFS and all sub-options
echo "=== Enabling SUSFS features ==="
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS || { echo -e "${RED}ERROR: Failed to enable KSU_SUSFS${NC}"; exit 1; }
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS_SUS_PATH || { echo -e "${RED}ERROR: Failed to enable KSU_SUSFS_SUS_PATH${NC}"; exit 1; }
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS_SUS_MOUNT || { echo -e "${RED}ERROR: Failed to enable KSU_SUSFS_SUS_MOUNT${NC}"; exit 1; }
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS_SUS_KSTAT || { echo -e "${RED}ERROR: Failed to enable KSU_SUSFS_SUS_KSTAT${NC}"; exit 1; }
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS_TRY_UMOUNT || { echo -e "${RED}ERROR: Failed to enable KSU_SUSFS_TRY_UMOUNT${NC}"; exit 1; }
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS_SPOOF_UNAME || { echo -e "${RED}ERROR: Failed to enable KSU_SUSFS_SPOOF_UNAME${NC}"; exit 1; }
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS_ENABLE_LOG || { echo -e "${RED}ERROR: Failed to enable KSU_SUSFS_ENABLE_LOG${NC}"; exit 1; }
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS || { echo -e "${RED}ERROR: Failed to enable KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS${NC}"; exit 1; }
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG || { echo -e "${RED}ERROR: Failed to enable KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG${NC}"; exit 1; }
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS_OPEN_REDIRECT || { echo -e "${RED}ERROR: Failed to enable KSU_SUSFS_OPEN_REDIRECT${NC}"; exit 1; }
scripts/config --file "$CONFIG_FILE" --enable KSU_SUSFS_SUS_MAP || { echo -e "${RED}ERROR: Failed to enable KSU_SUSFS_SUS_MAP${NC}"; exit 1; }

echo ""
echo "=== Resolving config dependencies ==="
make O=out ARCH=arm64 LLVM=1 CROSS_COMPILE=aarch64-linux-gnu- CLANG_TRIPLE=aarch64-linux-gnu- olddefconfig

echo ""
echo "=== Verifying KernelSU + SUSFS configuration ==="

MISSING_CONFIGS=0

# Verify critical configs
for cfg in CONFIG_KSU CONFIG_KSU_MANUAL_HOOK CONFIG_KSU_SUSFS; do
  if grep -q "^${cfg}=y" "$CONFIG_FILE"; then
    echo -e "  ${GREEN}✓${NC} $cfg=y"
  else
    echo -e "  ${RED}✗${NC} $cfg is not set to y!"
    MISSING_CONFIGS=1
  fi
done

# Check that kprobes is disabled
if grep -q "^CONFIG_KSU_KPROBES_HOOK=y" "$CONFIG_FILE"; then
  echo -e "  ${YELLOW}⚠${NC} CONFIG_KSU_KPROBES_HOOK=y — this should be disabled for non-GKI!"
  MISSING_CONFIGS=1
else
  echo -e "  ${GREEN}✓${NC} CONFIG_KSU_KPROBES_HOOK is disabled (correct for non-GKI)"
fi

if [ "$MISSING_CONFIGS" -ne 0 ]; then
  echo ""
  echo -e "${RED}ERROR: Critical config options are not set correctly.${NC}"
  exit 1
fi

echo ""
echo "=== All KSU and SUSFS config options ==="
grep -E "CONFIG_KSU" "$CONFIG_FILE" | sort || true

echo ""
echo "========================================"
echo -e "${GREEN}  Configuration Complete!${NC}"
echo "========================================"
echo ""
echo "KernelSU + SUSFS configuration applied successfully."
echo "Ready to build kernel."
echo ""
