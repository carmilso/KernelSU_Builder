#!/bin/bash
#
# apply-ksu-hooks.sh — Apply manual KernelSU hooks for non-GKI kernels
#
# These hooks are required because 4.19 non-GKI kernels use manual hook
# mode (not kprobes). The wshamroukh Kbuild auto-patches SELinux, seccomp,
# and namespace.c, but the following hooks must be applied manually.
#
# Reference: https://kernelsu.org/guide/how-to-integrate-for-non-gki.html
#
# Hooks 1 (exec), 2 (open), and 4 (stat) have SUSFS-aware variants that
# check susfs_is_current_proc_umounted() before running KSU handlers.
# When a process is "umounted" by SUSFS, the hooks are skipped entirely
# to prevent detection apps from triggering KSU hook behavior.
#
# This script is sourced from apply-susfs.sh and expects to run inside
# the kernel source tree (kernel/). It sets HOOKS_FAILED=1 on error.

HOOKS_FAILED=0
HOOK_NUM=0

apply_hook() {
  local file="$1"
  local marker="$2"
  local description="$3"

  HOOK_NUM=$((HOOK_NUM + 1))
  echo ""
  echo "Hook $HOOK_NUM: $file — $description"

  if grep -q "$marker" "$file" 2>/dev/null; then
    echo "  SKIP: Hook already present"
    return 1 # already applied
  fi
  return 0 # needs applying
}

verify_hook() {
  local file="$1"
  local marker="$2"

  if grep -q "$marker" "$file"; then
    echo "  OK: Hook applied successfully"
  else
    echo "  FAILED: Could not apply hook"
    HOOKS_FAILED=1
  fi
}

# =====================================================================
# Hook 1: fs/exec.c — ksu_handle_execveat in do_execveat_common
# =====================================================================
# When CONFIG_KSU_SUSFS is enabled:
#   - Extern block uses #ifdef CONFIG_KSU_SUSFS with additional externs
#     for susfs_is_boot_completed_triggered and __ksu_is_allow_uid_for_current
#   - Hook body checks susfs_is_current_proc_umounted() first; if umounted,
#     skips all hooks (goto orig_flow). Otherwise conditionally calls hooks.
# When CONFIG_KSU_SUSFS is NOT enabled:
#   - Falls back to plain #ifdef CONFIG_KSU (original behavior)
if apply_hook fs/exec.c "ksu_handle_execveat" "ksu_handle_execveat"; then
  # Insert extern declarations before do_execveat_common (include susfs_def.h in the block)
  sed -i '/^static int do_execveat_common(int fd, struct filename \*filename,$/i\
#if defined(CONFIG_KSU) && !defined(CONFIG_KSU_SUSFS)\
extern bool ksu_execveat_hook __read_mostly;\
extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv,\
\t\t\tvoid *envp, int *flags);\
extern int ksu_handle_execveat_sucompat(int *fd, struct filename **filename_ptr,\
\t\t\t\t void *argv, void *envp, int *flags);\
#endif\
#ifdef CONFIG_KSU_SUSFS\
#include <linux\/susfs_def.h>\
extern bool ksu_execveat_hook __read_mostly;\
extern bool susfs_is_boot_completed_triggered __read_mostly;\
extern bool __ksu_is_allow_uid_for_current(uid_t uid);\
extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv,\
\t\t\tvoid *envp, int *flags);\
extern int ksu_handle_execveat_sucompat(int *fd, struct filename **filename_ptr,\
\t\t\t\t void *argv, void *envp, int *flags);\
#endif' fs/exec.c

  # Insert hook calls inside do_execveat_common, before the return
  sed -i '/^static int do_execveat_common/,/^}/ {
    /return __do_execve_file(fd, filename, argv, envp, flags, NULL);/i\
#if defined(CONFIG_KSU) && !defined(CONFIG_KSU_SUSFS)\
\tif (unlikely(ksu_execveat_hook))\
\t\tksu_handle_execveat(\&fd, \&filename, \&argv, \&envp, \&flags);\
\telse\
\t\tksu_handle_execveat_sucompat(\&fd, \&filename, \&argv, \&envp, \&flags);\
#endif\
#ifdef CONFIG_KSU_SUSFS\
\tif (likely(susfs_is_current_proc_umounted())) {\
\t\tgoto orig_exec_flow;\
\t}\
\tif (unlikely(ksu_execveat_hook || !susfs_is_boot_completed_triggered)) {\
\t\tksu_handle_execveat(\&fd, \&filename, \&argv, \&envp, \&flags);\
\t} else if (__ksu_is_allow_uid_for_current(current_uid().val)) {\
\t\tksu_handle_execveat_sucompat(\&fd, \&filename, \&argv, \&envp, \&flags);\
\t}\
orig_exec_flow:\
#endif
  }' fs/exec.c

  verify_hook fs/exec.c "ksu_handle_execveat"
fi

# =====================================================================
# Hook 2: fs/open.c — ksu_handle_faccessat in do_faccessat
# =====================================================================
# SUSFS-aware: checks susfs_is_current_proc_umounted() and
# __ksu_is_allow_uid_for_current() before calling ksu_handle_faccessat.
if apply_hook fs/open.c "ksu_handle_faccessat" "ksu_handle_faccessat"; then
  # Insert extern declarations before do_faccessat (include susfs_def.h in the block)
  sed -i '/^long do_faccessat(int dfd, const char __user \*filename, int mode)$/i\
#if defined(CONFIG_KSU) && !defined(CONFIG_KSU_SUSFS)\
extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode,\
\t\t\t int *flags);\
#endif\
#ifdef CONFIG_KSU_SUSFS\
#include <linux\/susfs_def.h>\
extern bool __ksu_is_allow_uid_for_current(uid_t uid);\
extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode,\
\t\t\t int *flags);\
#endif' fs/open.c

  # Insert hook calls inside do_faccessat, after lookup_flags
  sed -i '/^long do_faccessat/,/^}/ {
    /unsigned int lookup_flags = LOOKUP_FOLLOW;/a\
\n#if defined(CONFIG_KSU) && !defined(CONFIG_KSU_SUSFS)\
\tksu_handle_faccessat(\&dfd, \&filename, \&mode, NULL);\
#endif\
#ifdef CONFIG_KSU_SUSFS\
\tif (likely(susfs_is_current_proc_umounted())) {\
\t\tgoto orig_faccessat_flow;\
\t}\
\tif (unlikely(__ksu_is_allow_uid_for_current(current_uid().val))) {\
\t\tksu_handle_faccessat(\&dfd, \&filename, \&mode, NULL);\
\t}\
orig_faccessat_flow:\
#endif
  }' fs/open.c

  verify_hook fs/open.c "ksu_handle_faccessat"
fi

# =====================================================================
# Hook 3: fs/read_write.c — ksu_handle_vfs_read in vfs_read
# =====================================================================
# No SUSFS guard needed — vfs_read hook is for ksud binary detection
# and should always run regardless of umount state.
if apply_hook fs/read_write.c "ksu_handle_vfs_read" "ksu_handle_vfs_read"; then
  sed -i '/^ssize_t vfs_read(struct file \*file, char __user \*buf, size_t count, loff_t \*pos)$/i\
#ifdef CONFIG_KSU\
extern bool ksu_vfs_read_hook __read_mostly;\
extern int ksu_handle_vfs_read(struct file **file_ptr, char __user **buf_ptr,\
\t\t\tsize_t *count_ptr, loff_t **pos);\
#endif' fs/read_write.c

  sed -i '/^ssize_t vfs_read(struct file \*file, char __user \*buf/,/^}/ {
    /ssize_t ret;/a\
\n#ifdef CONFIG_KSU\
\tif (unlikely(ksu_vfs_read_hook))\
\t\tksu_handle_vfs_read(\&file, \&buf, \&count, \&pos);\
#endif
  }' fs/read_write.c

  verify_hook fs/read_write.c "ksu_handle_vfs_read"
fi

# =====================================================================
# Hook 4: fs/stat.c — ksu_handle_stat in vfs_statx
# =====================================================================
# SUSFS-aware: checks susfs_is_current_proc_umounted() and
# __ksu_is_allow_uid_for_current() before calling ksu_handle_stat.
# Note: generic_fillattr() SUSFS hooks (SUS_KSTAT) are applied by the
# SUSFS patch itself — we only handle the vfs_statx hook here.
if apply_hook fs/stat.c "ksu_handle_stat" "ksu_handle_stat"; then
  # Insert extern declarations before vfs_statx (include susfs_def.h in the block)
  sed -i '/^int vfs_statx(int dfd, const char __user \*filename, int flags,$/i\
#if defined(CONFIG_KSU) && !defined(CONFIG_KSU_SUSFS)\
extern int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);\
#endif\
#ifdef CONFIG_KSU_SUSFS\
#include <linux\/susfs_def.h>\
extern bool __ksu_is_allow_uid_for_current(uid_t uid);\
extern int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);\
#endif' fs/stat.c

  # Insert hook calls inside vfs_statx, after lookup_flags
  sed -i '/^int vfs_statx/,/^}/ {
    /unsigned int lookup_flags = LOOKUP_FOLLOW | LOOKUP_AUTOMOUNT;/a\
\n#if defined(CONFIG_KSU) && !defined(CONFIG_KSU_SUSFS)\
\tksu_handle_stat(\&dfd, \&filename, \&flags);\
#endif\
#ifdef CONFIG_KSU_SUSFS\
\tif (likely(susfs_is_current_proc_umounted())) {\
\t\tgoto orig_statx_flow;\
\t}\
\tif (unlikely(__ksu_is_allow_uid_for_current(current_uid().val))) {\
\t\tksu_handle_stat(\&dfd, \&filename, \&flags);\
\t}\
orig_statx_flow:\
#endif
  }' fs/stat.c

  verify_hook fs/stat.c "ksu_handle_stat"
fi

# =====================================================================
# Hook 5: drivers/input/input.c — ksu_handle_input_handle_event
# =====================================================================
# No SUSFS guard needed — input hook is for volume key trigger
# and should always run.
if apply_hook drivers/input/input.c "ksu_handle_input_handle_event" "ksu_handle_input_handle_event"; then
  sed -i '/^static void input_handle_event(struct input_dev \*dev,$/i\
#ifdef CONFIG_KSU\
extern bool ksu_input_hook __read_mostly;\
extern int ksu_handle_input_handle_event(unsigned int *type, unsigned int *code, int *value);\
#endif' drivers/input/input.c

  sed -i '/^static void input_handle_event/,/^}/ {
    /int disposition = input_get_disposition(dev, type, code, &value);/a\
\n#ifdef CONFIG_KSU\
\tif (unlikely(ksu_input_hook))\
\t\tksu_handle_input_handle_event(\&type, \&code, \&value);\
#endif
  }' drivers/input/input.c

  verify_hook drivers/input/input.c "ksu_handle_input_handle_event"
fi

# =====================================================================
# Hook 6: fs/devpts/inode.c — ksu_handle_devpts
# =====================================================================
# No SUSFS guard needed.
if apply_hook fs/devpts/inode.c "ksu_handle_devpts" "ksu_handle_devpts"; then
  sed -i '/^void \*devpts_get_priv(struct dentry \*dentry)$/i\
#ifdef CONFIG_KSU\
extern int ksu_handle_devpts(struct inode *);\
#endif' fs/devpts/inode.c

  sed -i '/^void \*devpts_get_priv/,/^}/ {
    /if (dentry->d_sb->s_magic != DEVPTS_SUPER_MAGIC)/i\
#ifdef CONFIG_KSU\
\tksu_handle_devpts(dentry->d_inode);\
#endif
  }' fs/devpts/inode.c

  verify_hook fs/devpts/inode.c "ksu_handle_devpts"
fi

# =====================================================================
# Hook 7: kernel/reboot.c — ksu_handle_sys_reboot for SUSFS supercalls
# =====================================================================
# This hook is CRITICAL for SUSFS functionality. The wshamroukh KSU-Next
# driver dispatches ALL SUSFS configuration commands (add_sus_path,
# add_try_umount, set_uname, spoof_cmdline, etc.) through the reboot
# syscall using magic numbers. Without this hook, SUSFS features exist
# in the kernel but can never be configured at runtime.
#
# The kprobe for __sys_reboot is NOT registered when MANUAL_HOOK mode
# is active (our case), so we must hook it manually.
#
# ksu_handle_sys_reboot() always returns 0 regardless of whether it
# handled the call or not. We check magic1 == 0xDEADBEEF ourselves
# to decide whether to short-circuit the syscall.
#
# Hook placement: at the very top of SYSCALL_DEFINE4(reboot, ...),
# BEFORE the CAP_SYS_BOOT check (KSU supercalls don't need that cap).
if apply_hook kernel/reboot.c "ksu_handle_sys_reboot" "ksu_handle_sys_reboot (SUSFS supercalls)"; then
  # Insert extern declaration before SYSCALL_DEFINE4(reboot, ...)
  sed -i '/^SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,$/i\
#ifdef CONFIG_KSU\
extern int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd,\
\t\t\t\t void __user **arg);\
#endif' kernel/reboot.c

  # Insert hook call inside the function, right after variable declarations
  # and before the CAP_SYS_BOOT check.
  # Target: the line "int ret = 0;" which is the last local variable declaration.
  # We insert after it so all declarations are before our code (C89 compat).
  sed -i '/^SYSCALL_DEFINE4(reboot, int, magic1/,/^}/ {
    /int ret = 0;/a\
\n#ifdef CONFIG_KSU\
\t/* KSU supercall dispatch via reboot syscall */\
\tif (magic1 == 0xDEADBEEF) {\
\t\tksu_handle_sys_reboot(magic1, magic2, cmd, (void __user **)&arg);\
\t\treturn 0;\
\t}\
#endif
  }' kernel/reboot.c

  verify_hook kernel/reboot.c "ksu_handle_sys_reboot"
fi

echo ""
echo "========================================"
echo "  KernelSU Manual Hooks — Summary"
echo "========================================"
echo ""
if [ "$HOOKS_FAILED" -eq 0 ]; then
  echo "All KernelSU manual hooks applied successfully!"
else
  echo "WARNING: Some hooks failed to apply."
  echo "         Check the output above for details."
fi
echo ""
