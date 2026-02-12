#!/bin/bash

# apply-susfs.sh — Apply SUSFS v2.0.0 patch and KernelSU manual hooks
#
# This script coordinates the application of SUSFS patches and KernelSU hooks
# for non-GKI kernels. It is called from the GitHub Actions workflow when
# SUSFS support is enabled in sources.yaml.
#
# Usage: ./apply-susfs.sh
#
# Expected to run in the project root directory with kernel/ subdirectory present.

set -e

# Define colors
GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
NC='\033[0m' # No Color

# Get project root (script is in scripts/ subdirectory)
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL_DIR="$SCRIPT_DIR/kernel"
SUSFS_PATCH="$SCRIPT_DIR/susfs-2.0.0.patch"

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

warning() {
  echo ""
  echo -e "${YELLOW}WARNING: $1${NC}"
  echo ""
}

# =====================================================================
# Step 0: Verify environment
# =====================================================================
step "Step 0: Verify environment"

if [ ! -d "$KERNEL_DIR" ]; then
  error "Kernel directory not found at $KERNEL_DIR"
fi

if [ ! -f "$SUSFS_PATCH" ]; then
  error "SUSFS patch not found at $SUSFS_PATCH"
fi

echo "Kernel directory: $KERNEL_DIR"
echo "SUSFS patch: $SUSFS_PATCH"
echo "Project root: $SCRIPT_DIR"

# =====================================================================
# Step 1: Clean kernel tree (restore patched files)
# =====================================================================
step "Step 1: Clean kernel tree (restore patched files to pristine state)"

cd "$KERNEL_DIR"

# Files that the wshamroukh Kbuild modifies via sed at build time
KBUILD_SED_PATCHED_FILES=(
  fs/namespace.c
  fs/internal.h
  include/linux/seccomp.h
  security/selinux/hooks.c
  security/selinux/include/objsec.h
  security/selinux/selinuxfs.c
  security/selinux/xfrm.c
)

# Files modified by the SUSFS v2.0.0 kernel patch
SUSFS_PATCHED_FILES=(
  fs/Makefile
  fs/namei.c
  fs/namespace.c
  fs/notify/fdinfo.c
  fs/proc/base.c
  fs/proc/cmdline.c
  fs/proc/fd.c
  fs/proc/task_mmu.c
  fs/proc_namespace.c
  fs/readdir.c
  fs/seq_file.c
  fs/stat.c
  fs/statfs.c
  include/linux/mount.h
  include/linux/sched.h
  include/linux/seq_file.h
  kernel/kallsyms.c
  kernel/sys.c
  security/selinux/avc.c
)

# Files where manual KernelSU hooks are inserted
MANUAL_HOOK_FILES=(
  fs/exec.c
  fs/open.c
  fs/read_write.c
  fs/stat.c
  drivers/input/input.c
  fs/devpts/inode.c
  kernel/reboot.c
)

echo "Restoring files modified by Kbuild sed patches..."
for f in "${KBUILD_SED_PATCHED_FILES[@]}"; do
  if [ -f "$f" ]; then
    git checkout -- "$f" 2>/dev/null && echo "  Restored: $f" || true
  fi
done

echo ""
echo "Restoring files modified by SUSFS kernel patch..."
for f in "${SUSFS_PATCHED_FILES[@]}"; do
  if [ -f "$f" ]; then
    git checkout -- "$f" 2>/dev/null && echo "  Restored: $f" || true
  fi
done

echo ""
echo "Restoring files modified by manual hooks..."
for f in "${MANUAL_HOOK_FILES[@]}"; do
  if [ -f "$f" ]; then
    git checkout -- "$f" 2>/dev/null && echo "  Restored: $f" || true
  fi
done

echo ""
echo "Removing SUSFS source files created by the patch..."
rm -f fs/susfs.c
rm -f include/linux/susfs.h include/linux/susfs_def.h

echo ""
echo "Kernel tree cleaned successfully."

# =====================================================================
# Step 2: Apply SUSFS v2.0.0 kernel patch
# =====================================================================
step "Step 2: Apply SUSFS v2.0.0 kernel patch"

echo "Applying susfs-2.0.0.patch to kernel source..."
echo "This patch modifies ~19 kernel files and creates fs/susfs.c, include/linux/susfs.h, include/linux/susfs_def.h"
echo ""

# Use git apply with --reject so partial failures don't block the build
echo "Patch statistics:"
git apply --stat "$SUSFS_PATCH" 2>/dev/null || true
echo ""

if git apply --reject "$SUSFS_PATCH"; then
  echo ""
  echo -e "${GREEN}SUSFS v2.0.0 patch applied cleanly!${NC}"
else
  REJ_COUNT=$(find . -name '*.rej' -not -path './.git/*' 2>/dev/null | wc -l)
  echo ""
  warning "SUSFS patch partially applied ($REJ_COUNT rejected hunks — will be fixed in step 3)."
fi

# Verify SUSFS files were created
echo ""
echo "Verifying SUSFS files exist:"
for f in fs/susfs.c include/linux/susfs.h include/linux/susfs_def.h; do
  if [ -f "$f" ]; then
    echo -e "  ${GREEN}OK${NC}: $f ($(wc -l <"$f") lines)"
  else
    error "$f was not created by the patch — this will cause build failure!"
  fi
done

# =====================================================================
# Step 3: Fix SUSFS v2.0.0 rejected hunks
# =====================================================================
step "Step 3: Fix SUSFS v2.0.0 rejected hunks (automated)"

echo "Running fix-susfs-rejections.sh to apply rejected hunks..."
echo ""

# Source the fix script (it sets FIXES_FAILED variable)
source "$SCRIPT_DIR/scripts/fix-susfs-rejections.sh"

# Check if fixes failed
if [ "${FIXES_FAILED:-1}" -ne 0 ]; then
  error "fix-susfs-rejections.sh failed. Cannot proceed with build."
fi

echo ""
echo -e "${GREEN}All SUSFS rejection fixes applied successfully!${NC}"

# =====================================================================
# Step 4: Apply manual KernelSU hooks for non-GKI
# =====================================================================
step "Step 4: Apply manual KernelSU hooks (non-GKI)"

echo "Running apply-ksu-hooks.sh to apply 7 manual hooks..."
echo ""

# Source the hooks script (it sets HOOKS_FAILED variable)
source "$SCRIPT_DIR/scripts/apply-ksu-hooks.sh"

# Check if hooks failed
if [ "$HOOKS_FAILED" -ne 0 ]; then
  error "Some manual hooks failed to apply. The build cannot succeed."
fi

echo ""
echo -e "${GREEN}All KernelSU manual hooks applied successfully!${NC}"

# =====================================================================
# Step 5: Verify KernelSU driver installation
# =====================================================================
step "Step 5: Verify KernelSU driver installation"

if [ ! -d "drivers/kernelsu" ]; then
  error "KernelSU driver not found at drivers/kernelsu/ — it should have been installed by the workflow before this script."
fi

echo "KernelSU driver found at drivers/kernelsu/"
echo "Contents:"
ls drivers/kernelsu/ | head -20
echo "..."
echo "Total files: $(ls drivers/kernelsu/ | wc -l)"

# Verify Kbuild file exists
if [ ! -f "drivers/kernelsu/Kbuild" ]; then
  error "drivers/kernelsu/Kbuild not found!"
fi

echo ""
echo -e "${GREEN}KernelSU driver verified.${NC}"

# =====================================================================
# Step 6: Verify kernel build system registration
# =====================================================================
step "Step 6: Verify kernel build system registration"

# Check drivers/Makefile
if ! grep -q 'CONFIG_KSU.*kernelsu' drivers/Makefile; then
  warning "KernelSU not registered in drivers/Makefile. Adding it now..."
  echo 'obj-$(CONFIG_KSU) += kernelsu/' >>drivers/Makefile
  echo "Added 'obj-\$(CONFIG_KSU) += kernelsu/' to drivers/Makefile"
else
  echo -e "${GREEN}OK${NC}: KernelSU registered in drivers/Makefile"
fi

# Check drivers/Kconfig
if ! grep -q 'drivers/kernelsu/Kconfig' drivers/Kconfig; then
  warning "KernelSU not registered in drivers/Kconfig. Adding it now..."
  # Insert before the final 'endmenu'
  sed -i '/^endmenu$/i source "drivers/kernelsu/Kconfig"' drivers/Kconfig
  echo "Added 'source \"drivers/kernelsu/Kconfig\"' to drivers/Kconfig"
else
  echo -e "${GREEN}OK${NC}: KernelSU registered in drivers/Kconfig"
fi

# =====================================================================
# Done
# =====================================================================
echo ""
echo "========================================"
echo -e "${GREEN}  SUSFS + KernelSU Setup Complete!${NC}"
echo "========================================"
echo ""
echo "Summary:"
echo "  - SUSFS v2.0.0 patch: Applied"
echo "  - SUSFS rejection fixes: Applied"
echo "  - KernelSU manual hooks: Applied (7 hooks)"
echo "  - KernelSU driver: Verified"
echo "  - Build system: Registered"
echo ""
echo "Next steps:"
echo "  1. Configure kernel with SUSFS options (see sources.yaml)"
echo "  2. Build kernel"
echo ""
