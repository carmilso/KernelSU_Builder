#!/bin/bash
# fix-susfs-rejections.sh — Fix SUSFS v2.0.0 patch rejected hunks for LineageOS 4.19
#
# This script is sourced by apply-susfs.sh AFTER the main susfs-2.0.0.patch
# is applied with --reject. It manually applies the hunks that failed due to context
# differences between the upstream kernel (that the patch was written for) and the
# LineageOS 4.19 kernel (which has backports and vendor changes).
#
# Must run from inside the kernel tree directory.
#
# Files fixed:
#   1.  fs/Makefile            — add susfs.o build target
#   2.  include/linux/mount.h  — add susfs_mnt_id_backup field to struct vfsmount
#   3.  fs/proc_namespace.c    — add include + extern
#   4.  fs/proc/cmdline.c      — add cmdline spoofing hook
#   5.  kernel/kallsyms.c      — add symbol hiding in s_show
#   6.  fs/notify/fdinfo.c     — add include + inotify kstat spoofing block
#   7.  fs/proc/base.c         — add BIT_SUS_MAPS filter in proc_map_files_readdir
#   8.  fs/namei.c             — add include + SUSFS in __lookup_hash, lookup_slow,
#                                 lookup_open, do_filp_open variable declaration
#   9.  fs/proc/task_mmu.c     — add include + extern + show_smap mods + pagemap block
#   10. fs/namespace.c         — add includes/globals + susfs_mnt_alloc_id + modify
#                                 mnt_free_id, mnt_alloc_group_id, mnt_release_group_id,
#                                 vfs_create_mount
#
# Skipped (already present in kernel):
#   - fs/seq_file.c            — seq_put_hex_ll() already exists
#   - include/linux/seq_file.h — seq_put_hex_ll() declaration already exists

set -e

FIXES_FAILED=0

fix_file() {
  local file="$1"
  local description="$2"
  echo ""
  echo "  Fixing: $file — $description"
}

verify_fix() {
  local file="$1"
  local marker="$2"
  if grep -q "$marker" "$file" 2>/dev/null; then
    echo "    OK: verified"
  else
    echo "    FAILED: marker '$marker' not found after fix!"
    FIXES_FAILED=1
  fi
}

# =====================================================================
# 1. fs/Makefile — add obj-$(CONFIG_KSU_SUSFS) += susfs.o
# =====================================================================
fix_file "fs/Makefile" "add susfs.o build target"

if ! grep -q 'CONFIG_KSU_SUSFS.*susfs\.o' fs/Makefile; then
  # Insert after the obj-y block (after line with 'fs_context.o fs_parser.o')
  sed -i '/fs_context\.o fs_parser\.o$/a\
\
obj-$(CONFIG_KSU_SUSFS) += susfs.o' fs/Makefile
  verify_fix "fs/Makefile" "CONFIG_KSU_SUSFS.*susfs"
else
  echo "    SKIP: already present"
fi

# =====================================================================
# 2. include/linux/mount.h — add susfs_mnt_id_backup field
# =====================================================================
fix_file "include/linux/mount.h" "add susfs_mnt_id_backup to struct vfsmount"

if ! grep -q 'susfs_mnt_id_backup' include/linux/mount.h; then
  # Insert after 'void *data;' inside struct vfsmount, before ANDROID_KABI_RESERVE
  sed -i '/^\tint mnt_flags;/{N;s/\(int mnt_flags;\n\tvoid \*data;\)/\1\n#ifdef CONFIG_KSU_SUSFS\n\tu64 susfs_mnt_id_backup;\n#endif/}' include/linux/mount.h
  verify_fix "include/linux/mount.h" "susfs_mnt_id_backup"
else
  echo "    SKIP: already present"
fi

# =====================================================================
# 3. fs/proc_namespace.c — add include + extern
# =====================================================================
fix_file "fs/proc_namespace.c" "add susfs_def.h include + extern"

if ! grep -q 'susfs_def\.h' fs/proc_namespace.c; then
  # Add include after '#include <linux/sched/task.h>'
  sed -i '/#include <linux\/sched\/task\.h>/a\
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\
#include <linux\/susfs_def.h>\
#endif' fs/proc_namespace.c
  verify_fix "fs/proc_namespace.c" "susfs_def.h"
fi

if ! grep -q 'extern bool susfs_hide_sus_mnts_for_all_procs' fs/proc_namespace.c; then
  # Add extern after '#include "internal.h"'
  sed -i '/#include "internal\.h"/a\
\
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\
extern bool susfs_hide_sus_mnts_for_all_procs;\
#endif' fs/proc_namespace.c
  verify_fix "fs/proc_namespace.c" "extern bool susfs_hide_sus_mnts_for_all_procs"
fi

# =====================================================================
# 4. fs/proc/cmdline.c — add cmdline spoofing hook
# =====================================================================
fix_file "fs/proc/cmdline.c" "add cmdline spoofing"

if ! grep -q 'susfs_spoof_cmdline_or_bootconfig' fs/proc/cmdline.c; then
  # Add extern after #include <linux/seq_file.h>
  sed -i '/#include <linux\/seq_file\.h>/a\
\
#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG\
extern int susfs_spoof_cmdline_or_bootconfig(struct seq_file *m);\
#endif' fs/proc/cmdline.c

  # Add hook inside cmdline_proc_show, before seq_puts
  sed -i '/static int cmdline_proc_show(struct seq_file \*m, void \*v)/,/^}/ {
    /seq_puts(m, saved_command_line);/i\
#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG\
\tif (!susfs_spoof_cmdline_or_bootconfig(m)) {\
\t\tseq_putc(m, '"'"'\\n'"'"');\
\t\treturn 0;\
\t}\
#endif
  }' fs/proc/cmdline.c
  verify_fix "fs/proc/cmdline.c" "susfs_spoof_cmdline_or_bootconfig"
else
  echo "    SKIP: already present"
fi

# =====================================================================
# 5. kernel/kallsyms.c — add symbol hiding in s_show
# =====================================================================
fix_file "kernel/kallsyms.c" "add KSU/SUSFS symbol hiding"

if ! grep -q 'susfs_starts_with' kernel/kallsyms.c; then
  # Add extern before s_show function
  sed -i '/^static int s_show(struct seq_file \*m, void \*p)$/i\
#ifdef CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS\
extern bool susfs_starts_with(const char *str, const char *prefix);\
#endif\
' kernel/kallsyms.c

  # Use a Python script for this complex replacement since sed struggles with multi-line
  python3 -c "
import re

with open('kernel/kallsyms.c', 'r') as f:
    content = f.read()

old = '''\t} else
\t\tseq_printf(m, \"%px %c %s\\\\n\", value,
\t\t\t   iter->type, iter->name);
\treturn 0;
}'''

new = '''\t} else
#ifndef CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS
\t\tseq_printf(m, \"%px %c %s\\\\n\", value,
\t\t\t   iter->type, iter->name);
#else
\t{
\t\tif (susfs_starts_with(iter->name, \"ksu_\") ||
\t\t\tsusfs_starts_with(iter->name, \"__ksu_\") ||
\t\t\tsusfs_starts_with(iter->name, \"susfs_\") ||
\t\t\tsusfs_starts_with(iter->name, \"ksud\") ||
\t\t\tsusfs_starts_with(iter->name, \"is_ksu_\") ||
\t\t\tsusfs_starts_with(iter->name, \"is_manager_\") ||
\t\t\tsusfs_starts_with(iter->name, \"escape_to_\") ||
\t\t\tsusfs_starts_with(iter->name, \"setup_selinux\") ||
\t\t\tsusfs_starts_with(iter->name, \"track_throne\") ||
\t\t\tsusfs_starts_with(iter->name, \"on_post_fs_data\") ||
\t\t\tsusfs_starts_with(iter->name, \"try_umount\") ||
\t\t\tsusfs_starts_with(iter->name, \"kernelsu\") ||
\t\t\tsusfs_starts_with(iter->name, \"__initcall__kmod_kernelsu\") ||
\t\t\tsusfs_starts_with(iter->name, \"apply_kernelsu\") ||
\t\t\tsusfs_starts_with(iter->name, \"handle_sepolicy\") ||
\t\t\tsusfs_starts_with(iter->name, \"getenforce\") ||
\t\t\tsusfs_starts_with(iter->name, \"setenforce\") ||
\t\t\tsusfs_starts_with(iter->name, \"is_zygote\"))
\t\t{
\t\t\treturn 0;
\t\t}
\t\tseq_printf(m, \"%px %c %s\\\\n\", value,
\t\t\t   iter->type, iter->name);
\t}
#endif
\treturn 0;
}'''

if old in content:
    content = content.replace(old, new, 1)
    with open('kernel/kallsyms.c', 'w') as f:
        f.write(content)
    print('    OK: s_show replacement applied')
else:
    print('    WARNING: Could not find exact s_show pattern to replace')
"
  verify_fix "kernel/kallsyms.c" "susfs_starts_with"
else
  echo "    SKIP: already present"
fi

# =====================================================================
# 6. fs/notify/fdinfo.c — add include + inotify kstat spoofing
# =====================================================================
fix_file "fs/notify/fdinfo.c" "add susfs_def.h include + inotify kstat spoofing"

if ! grep -q 'susfs_def\.h' fs/notify/fdinfo.c; then
  # Add include after '#include <linux/exportfs.h>'
  sed -i '/#include <linux\/exportfs\.h>/a\
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\
#include <linux\/susfs_def.h>\
#endif' fs/notify/fdinfo.c
  verify_fix "fs/notify/fdinfo.c" "susfs_def.h"
fi

if ! grep -q 'BIT_SUS_KSTAT' fs/notify/fdinfo.c; then
  # Add kstat spoofing block inside inotify_fdinfo, after 'if (inode) {'
  python3 -c "
with open('fs/notify/fdinfo.c', 'r') as f:
    content = f.read()

# Find the pattern in inotify_fdinfo: 'if (inode) {' followed by seq_printf
old = '''\tif (inode) {
\t\tseq_printf(m, \"inotify wd:%x ino:%lx sdev:%x mask:%x ignored_mask:0 \",
\t\t\t   inode_mark->wd, inode->i_ino, inode->i_sb->s_dev,
\t\t\t   inotify_mark_user_mask(mark));
\t\tshow_mark_fhandle(m, inode);
\t\tseq_putc(m, '\\\\n');
\t\tiput(inode);'''

new = '''\tif (inode) {
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
\t\tif (likely(susfs_is_current_proc_umounted()) &&
\t\t\t\tunlikely(inode->i_mapping->flags & BIT_SUS_KSTAT)) {
\t\t\tstruct path path;
\t\t\tchar *pathname = kmalloc(PAGE_SIZE, GFP_KERNEL);
\t\t\tchar *dpath;
\t\t\tif (!pathname) {
\t\t\t\tgoto out_seq_printf;
\t\t\t}
\t\t\tdpath = d_path(&file->f_path, pathname, PAGE_SIZE);
\t\t\tif (!dpath) {
\t\t\t\tgoto out_free_pathname;
\t\t\t}
\t\t\tif (kern_path(dpath, 0, &path)) {
\t\t\t\tgoto out_free_pathname;
\t\t\t}
\t\t\tseq_printf(m, \"inotify wd:%x ino:%lx sdev:%x mask:%x ignored_mask:0 \",
\t\t\t   inode_mark->wd, path.dentry->d_inode->i_ino, path.dentry->d_inode->i_sb->s_dev,
\t\t\t   inotify_mark_user_mask(mark));
\t\tshow_mark_fhandle(m, path.dentry->d_inode);
\t\tseq_putc(m, '\\\\n');
\t\tiput(inode);
\t\tpath_put(&path);
\t\tkfree(pathname);
\t\treturn;
out_free_pathname:
\t\tkfree(pathname);
\t}
out_seq_printf:
#endif
\t\tseq_printf(m, \"inotify wd:%x ino:%lx sdev:%x mask:%x ignored_mask:0 \",
\t\t\t   inode_mark->wd, inode->i_ino, inode->i_sb->s_dev,
\t\t\t   inotify_mark_user_mask(mark));
\t\tshow_mark_fhandle(m, inode);
\t\tseq_putc(m, '\\\\n');
\t\tiput(inode);'''

if old in content:
    content = content.replace(old, new, 1)
    with open('fs/notify/fdinfo.c', 'w') as f:
        f.write(content)
    print('    OK: inotify kstat spoofing applied')
else:
    print('    WARNING: Could not find exact inotify_fdinfo pattern')
"
  verify_fix "fs/notify/fdinfo.c" "BIT_SUS_KSTAT"
else
  echo "    SKIP: already present"
fi

# =====================================================================
# 7. fs/proc/base.c — add BIT_SUS_MAPS filter in proc_map_files_readdir
# =====================================================================
fix_file "fs/proc/base.c" "add BIT_SUS_MAPS filter in proc_map_files_readdir"

if ! grep -q 'BIT_SUS_MAPS.*proc_map_files_readdir\|proc_map_files_readdir.*BIT_SUS_MAPS' fs/proc/base.c 2>/dev/null; then
  # Check if BIT_SUS_MAPS is already in the readdir loop area (near flex_array_put)
  if ! grep -A2 'if (!vma->vm_file)' fs/proc/base.c | grep -q 'BIT_SUS_MAPS'; then
    # Insert SUSFS filter after 'if (!vma->vm_file)\n\t\t\t\tcontinue;' in the VMA loop
    python3 -c "
with open('fs/proc/base.c', 'r') as f:
    content = f.read()

# The pattern is inside proc_map_files_readdir's second VMA loop
old = '''\t\t\tif (!vma->vm_file)
\t\t\t\tcontinue;
\t\t\tif (++pos <= ctx->pos)
\t\t\t\tcontinue;

\t\t\tinfo.start = vma->vm_start;'''

new = '''\t\t\tif (!vma->vm_file)
\t\t\t\tcontinue;
#ifdef CONFIG_KSU_SUSFS_SUS_MAP
\t\t\tif (unlikely(file_inode(vma->vm_file)->i_mapping->flags & BIT_SUS_MAPS) &&
\t\t\t\tsusfs_is_current_proc_umounted())
\t\t\t{
\t\t\t\tcontinue;
\t\t\t}
#endif
\t\t\tif (++pos <= ctx->pos)
\t\t\t\tcontinue;

\t\t\tinfo.start = vma->vm_start;'''

if old in content:
    content = content.replace(old, new, 1)
    with open('fs/proc/base.c', 'w') as f:
        f.write(content)
    print('    OK: BIT_SUS_MAPS filter applied in proc_map_files_readdir')
else:
    print('    WARNING: Could not find exact proc_map_files_readdir pattern')
"
    verify_fix "fs/proc/base.c" "BIT_SUS_MAPS.*proc"
  else
    echo "    SKIP: BIT_SUS_MAPS already in readdir loop"
  fi
else
  echo "    SKIP: already present"
fi

# =====================================================================
# 8. fs/namei.c — add include + SUSFS logic in 4 functions
# =====================================================================
fix_file "fs/namei.c" "add susfs_def.h include + SUSFS logic in __lookup_hash, __lookup_slow, lookup_open, do_filp_open"

# 8a. Add susfs_def.h include (after uaccess.h)
if ! grep -q 'susfs_def\.h' fs/namei.c; then
  sed -i '/#include <linux\/uaccess\.h>/a\
#if defined(CONFIG_KSU_SUSFS_SUS_PATH) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\
#include <linux\/susfs_def.h>\
#endif' fs/namei.c
  verify_fix "fs/namei.c" "susfs_def.h"
fi

# The complex namei.c modifications are in a separate Python block
python3 << 'PYEOF'
with open('fs/namei.c', 'r') as f:
    content = f.read()

# 8b. __lookup_hash — replace the function body with SUSFS version
old_lookup_hash = '''static struct dentry *__lookup_hash(const struct qstr *name,
		struct dentry *base, unsigned int flags)
{
	struct dentry *dentry = lookup_dcache(name, base, flags);
	struct dentry *old;
	struct inode *dir = base->d_inode;

	if (dentry)
		return dentry;

	/* Don't create child dentry for a dead directory. */
	if (unlikely(IS_DEADDIR(dir)))
		return ERR_PTR(-ENOENT);

	dentry = d_alloc(base, name);
	if (unlikely(!dentry))
		return ERR_PTR(-ENOMEM);

	old = dir->i_op->lookup(dir, dentry, flags);
	if (unlikely(old)) {
		dput(dentry);
		dentry = old;
	}
	return dentry;
}'''

new_lookup_hash = '''static struct dentry *__lookup_hash(const struct qstr *name,
		struct dentry *base, unsigned int flags)
{
#ifdef CONFIG_KSU_SUSFS_SUS_PATH
	struct dentry *dentry;
	struct dentry *old;
	struct inode *dir = base->d_inode;
	bool found_sus_path = false;

	if (base && base->d_inode && !found_sus_path) {
		if (susfs_is_base_dentry_android_data_dir(base) &&
			susfs_is_sus_android_data_d_name_found(name->name))
		{
			dentry = lookup_dcache(&susfs_fake_qstr_name, base, flags);
			found_sus_path = true;
			goto retry;
		} else if (susfs_is_base_dentry_sdcard_dir(base) &&
				   susfs_is_sus_sdcard_d_name_found(name->name))
		{
			dentry = lookup_dcache(&susfs_fake_qstr_name, base, flags);
			found_sus_path = true;
			goto retry;
		}
	}
	dentry = lookup_dcache(name, base, flags);
retry:
#else
	struct dentry *dentry = lookup_dcache(name, base, flags);
	struct dentry *old;
	struct inode *dir = base->d_inode;
#endif

	if (dentry)
#ifdef CONFIG_KSU_SUSFS_SUS_PATH
	{
		if (!found_sus_path && !IS_ERR(dentry) && dentry->d_inode && susfs_is_inode_sus_path(dentry->d_inode)) {
			dput(dentry);
			dentry = lookup_dcache(&susfs_fake_qstr_name, base, flags);
			found_sus_path = true;
			goto retry;
		}
		return dentry;
	}
#else
		return dentry;
#endif

	/* Don't create child dentry for a dead directory. */
	if (unlikely(IS_DEADDIR(dir)))
		return ERR_PTR(-ENOENT);

#ifdef CONFIG_KSU_SUSFS_SUS_PATH
	if (found_sus_path) {
		dentry = d_alloc(base, &susfs_fake_qstr_name);
		goto skip_orig_flow;
	}
#endif
	dentry = d_alloc(base, name);
#ifdef CONFIG_KSU_SUSFS_SUS_PATH
skip_orig_flow:
#endif
	if (unlikely(!dentry))
		return ERR_PTR(-ENOMEM);

	old = dir->i_op->lookup(dir, dentry, flags);
	if (unlikely(old)) {
		dput(dentry);
		dentry = old;
	}
	return dentry;
}'''

if old_lookup_hash in content:
    content = content.replace(old_lookup_hash, new_lookup_hash, 1)
    print('    OK: __lookup_hash SUSFS applied')
else:
    print('    WARNING: Could not find exact __lookup_hash pattern')

# 8c. __lookup_slow — add SUSFS logic
old_lookup_slow = '''static struct dentry *__lookup_slow(const struct qstr *name,
				    struct dentry *dir,
				    unsigned int flags)
{
	struct dentry *dentry, *old;
	struct inode *inode = dir->d_inode;
	DECLARE_WAIT_QUEUE_HEAD_ONSTACK(wq);

	/* Don't go there if it's already dead */
	if (unlikely(IS_DEADDIR(inode)))
		return ERR_PTR(-ENOENT);
again:
	dentry = d_alloc_parallel(dir, name, &wq);
	if (IS_ERR(dentry))
		return dentry;
	if (unlikely(!d_in_lookup(dentry))) {'''

new_lookup_slow = '''static struct dentry *__lookup_slow(const struct qstr *name,
				    struct dentry *dir,
				    unsigned int flags)
{
	struct dentry *dentry, *old;
	struct inode *inode = dir->d_inode;
	DECLARE_WAIT_QUEUE_HEAD_ONSTACK(wq);
#ifdef CONFIG_KSU_SUSFS_SUS_PATH
	DECLARE_WAIT_QUEUE_HEAD_ONSTACK(sus_wq);
	bool found_sus_path = false;
	bool is_nd_flags_lookup_last = (flags & ND_FLAGS_LOOKUP_LAST);
#endif

	/* Don't go there if it's already dead */
	if (unlikely(IS_DEADDIR(inode)))
		return ERR_PTR(-ENOENT);
again:
#ifdef CONFIG_KSU_SUSFS_SUS_PATH
	if (found_sus_path) {
		dentry = d_alloc_parallel(dir, &susfs_fake_qstr_name, &sus_wq);
		goto retry;
	}
	if (is_nd_flags_lookup_last && !found_sus_path) {
		if (susfs_is_base_dentry_android_data_dir(dir) &&
			susfs_is_sus_android_data_d_name_found(name->name))
		{
			dentry = d_alloc_parallel(dir, &susfs_fake_qstr_name, &sus_wq);
			found_sus_path = true;
			goto retry;
		} else if (susfs_is_base_dentry_sdcard_dir(dir) &&
				susfs_is_sus_sdcard_d_name_found(name->name))
		{
			dentry = d_alloc_parallel(dir, &susfs_fake_qstr_name, &sus_wq);
			found_sus_path = true;
			goto retry;
		}
	}
#endif
	dentry = d_alloc_parallel(dir, name, &wq);
#ifdef CONFIG_KSU_SUSFS_SUS_PATH
retry:
#endif
	if (IS_ERR(dentry))
		return dentry;
	if (unlikely(!d_in_lookup(dentry))) {'''

if old_lookup_slow in content:
    content = content.replace(old_lookup_slow, new_lookup_slow, 1)
    print('    OK: __lookup_slow SUSFS (top half) applied')
else:
    print('    WARNING: Could not find exact __lookup_slow top pattern')

# Add the post-lookup filter in __lookup_slow
old_slow_end = '''		dentry = old;
		}
	}
	return dentry;
}

static struct dentry *lookup_slow(const struct qstr *name,'''

new_slow_end = '''		dentry = old;
		}
	}
#ifdef CONFIG_KSU_SUSFS_SUS_PATH
	if (is_nd_flags_lookup_last && !found_sus_path) {
		if (dentry && !IS_ERR(dentry) && dentry->d_inode) {
			if (susfs_is_inode_sus_path(dentry->d_inode)) {
				dput(dentry);
				dentry = d_alloc_parallel(dir, &susfs_fake_qstr_name, &sus_wq);
				found_sus_path = true;
				goto retry;
			}
		}
	}
#endif
	return dentry;
}

static struct dentry *lookup_slow(const struct qstr *name,'''

if old_slow_end in content:
    content = content.replace(old_slow_end, new_slow_end, 1)
    print('    OK: __lookup_slow SUSFS (bottom half) applied')
else:
    print('    WARNING: Could not find exact __lookup_slow bottom pattern')

# 8d. lookup_open — add SUSFS logic
old_lookup_open = '''	file->f_mode &= ~FMODE_CREATED;
	dentry = d_lookup(dir, &nd->last);
	for (;;) {
		if (!dentry) {
			dentry = d_alloc_parallel(dir, &nd->last, &wq);
			if (IS_ERR(dentry))
				return PTR_ERR(dentry);
		}'''

new_lookup_open = '''	file->f_mode &= ~FMODE_CREATED;
#ifdef CONFIG_KSU_SUSFS_SUS_PATH
	if (nd->state & ND_STATE_OPEN_LAST) {
		if (susfs_is_base_dentry_android_data_dir(dir) &&
			susfs_is_sus_android_data_d_name_found(nd->last.name))
		{
			dentry = d_lookup(dir, &susfs_fake_qstr_name);
			found_sus_path = true;
			goto skip_orig_flow1;
		} else if (susfs_is_base_dentry_sdcard_dir(dir) &&
			susfs_is_sus_sdcard_d_name_found(nd->last.name))
		{
			dentry = d_lookup(dir, &susfs_fake_qstr_name);
			found_sus_path = true;
			goto skip_orig_flow1;
		}
	}
#endif
	dentry = d_lookup(dir, &nd->last);
#ifdef CONFIG_KSU_SUSFS_SUS_PATH
	if ((nd->state & ND_STATE_OPEN_LAST) && dentry && !IS_ERR(dentry) && dentry->d_inode) {
		if (susfs_is_inode_sus_path(dentry->d_inode)) {
			dput(dentry);
			dentry = d_lookup(dir, &susfs_fake_qstr_name);
			found_sus_path = true;
		}
	}
skip_orig_flow1:
#endif
	for (;;) {
		if (!dentry) {
#ifdef CONFIG_KSU_SUSFS_SUS_PATH
			if (found_sus_path) {
				dentry = d_alloc_parallel(dir, &susfs_fake_qstr_name, &wq);
				goto skip_orig_flow2;
			}
#endif
			dentry = d_alloc_parallel(dir, &nd->last, &wq);
#ifdef CONFIG_KSU_SUSFS_SUS_PATH
skip_orig_flow2:
#endif
			if (IS_ERR(dentry))
				return PTR_ERR(dentry);
		}'''

if old_lookup_open in content:
    content = content.replace(old_lookup_open, new_lookup_open, 1)
    print('    OK: lookup_open SUSFS applied')
else:
    print('    WARNING: Could not find exact lookup_open pattern')

# Add variable declarations at the top of lookup_open
old_lookup_open_vars = '''	struct dentry *dentry;
	int error, create_error = 0;
	umode_t mode = op->mode;
	DECLARE_WAIT_QUEUE_HEAD_ONSTACK(wq);

	if (unlikely(IS_DEADDIR(dir_inode)))'''

new_lookup_open_vars = '''	struct dentry *dentry;
	int error, create_error = 0;
	umode_t mode = op->mode;
	DECLARE_WAIT_QUEUE_HEAD_ONSTACK(wq);
#ifdef CONFIG_KSU_SUSFS_SUS_PATH
	bool found_sus_path = false;
#endif

	if (unlikely(IS_DEADDIR(dir_inode)))'''

if old_lookup_open_vars in content:
    content = content.replace(old_lookup_open_vars, new_lookup_open_vars, 1)
    print('    OK: lookup_open SUSFS variable declarations applied')
else:
    print('    WARNING: Could not find exact lookup_open variable pattern')

# 8e. do_filp_open — add extern + variable declaration for OPEN_REDIRECT
old_do_filp_open_pre = '''struct file *do_filp_open(int dfd, struct filename *pathname,
		const struct open_flags *op)
{
	struct nameidata nd;
	int flags = op->lookup_flags;
	struct file *filp;

	set_nameidata(&nd, dfd, pathname);'''

new_do_filp_open_pre = '''#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT
extern struct filename* susfs_get_redirected_path(unsigned long ino);
#endif

struct file *do_filp_open(int dfd, struct filename *pathname,
		const struct open_flags *op)
{
	struct nameidata nd;
	int flags = op->lookup_flags;
	struct file *filp;
#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT
	struct filename *fake_pathname;
#endif

	set_nameidata(&nd, dfd, pathname);'''

if old_do_filp_open_pre in content:
    content = content.replace(old_do_filp_open_pre, new_do_filp_open_pre, 1)
    print('    OK: do_filp_open extern + variable declaration applied')
else:
    print('    WARNING: Could not find exact do_filp_open pre pattern')

with open('fs/namei.c', 'w') as f:
    f.write(content)
PYEOF

verify_fix "fs/namei.c" "susfs_get_redirected_path"

# Continue with remaining fixes in next comment due to length...
echo ""
echo "  Continuing with fs/proc/task_mmu.c and fs/namespace.c fixes..."

# =====================================================================
# 9. fs/proc/task_mmu.c — add include + extern + show_smap + pagemap
# =====================================================================
fix_file "fs/proc/task_mmu.c" "add susfs include/extern + show_smap + pagemap modifications"

python3 << 'PYEOF'
with open('fs/proc/task_mmu.c', 'r') as f:
    content = f.read()

changes = 0

# 9a. Add include after '#include <linux/ctype.h>'
if '#include <linux/susfs_def.h>' not in content:
    old = '#include <linux/ctype.h>\n'
    new = '#include <linux/ctype.h>\n#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP)\n#include <linux/susfs_def.h>\n#endif\n'
    if old in content:
        content = content.replace(old, new, 1)
        changes += 1
        print('    OK: susfs_def.h include added')
    else:
        print('    WARNING: Could not find ctype.h include')

# 9b. Add extern after '#include "internal.h"'
if 'extern void susfs_sus_ino_for_show_map_vma' not in content:
    old = '#include "internal.h"\n'
    new = '#include "internal.h"\n\n#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\nextern void susfs_sus_ino_for_show_map_vma(unsigned long ino, dev_t *out_dev, unsigned long *out_ino);\n#endif\n'
    if old in content:
        content = content.replace(old, new, 1)
        changes += 1
        print('    OK: susfs_sus_ino extern added')
    else:
        print('    WARNING: Could not find internal.h include for extern')

# 9c. Modify show_smap — add SUS_MAP bypass for Size/KernelPageSize/MMUPageSize
if 'bypass_orig_flow2' not in content:
    old_show_smap = '''\tSEQ_PUT_DEC("Size:           ", vma->vm_end - vma->vm_start);
\tSEQ_PUT_DEC(" kB\\nKernelPageSize: ", vma_kernel_pagesize(vma));
\tSEQ_PUT_DEC(" kB\\nMMUPageSize:    ", vma_mmu_pagesize(vma));
\tseq_puts(m, " kB\\n");

\t__show_smap(m, &mss);

\tseq_printf(m, "THPeligible:    %d\\n", transparent_hugepage_enabled(vma));

\tif (arch_pkeys_enabled())
\t\tseq_printf(m, "ProtectionKey:  %8u\\n", vma_pkey(vma));
\tshow_smap_vma_flags(m, vma);'''

    new_show_smap = '''\tSEQ_PUT_DEC("Size:           ", vma->vm_end - vma->vm_start);
#ifdef CONFIG_KSU_SUSFS_SUS_MAP
\tif (vma->vm_file &&
\t\tunlikely(file_inode(vma->vm_file)->i_mapping->flags & BIT_SUS_MAPS) &&
\t\tsusfs_is_current_proc_umounted())
\t{
\t\tseq_puts(m, " kB\\nKernelPageSize:     4 kB\\nMMUPageSize:        4 kB\\n");
\t\tgoto bypass_orig_flow;
\t}
#endif
\tSEQ_PUT_DEC(" kB\\nKernelPageSize: ", vma_kernel_pagesize(vma));
\tSEQ_PUT_DEC(" kB\\nMMUPageSize:    ", vma_mmu_pagesize(vma));
\tseq_puts(m, " kB\\n");

\t__show_smap(m, &mss);

\tseq_printf(m, "THPeligible:    %d\\n", transparent_hugepage_enabled(vma));

\tif (arch_pkeys_enabled())
\t\tseq_printf(m, "ProtectionKey:  %8u\\n", vma_pkey(vma));
#ifdef CONFIG_KSU_SUSFS_SUS_MAP
\tif (vma->vm_file &&
\t\tunlikely(file_inode(vma->vm_file)->i_mapping->flags & BIT_SUS_MAPS) &&
\t\tsusfs_is_current_proc_umounted())
\t{
\t\tseq_puts(m, "VmFlags: mr mw me");
\t\tseq_putc(m, '\\n');
\t\tgoto bypass_orig_flow2;
\t}
#endif
\tshow_smap_vma_flags(m, vma);'''

    if old_show_smap in content:
        content = content.replace(old_show_smap, new_show_smap, 1)
        changes += 1
        print('    OK: show_smap SUS_MAP bypass applied')
    else:
        print('    WARNING: Could not find exact show_smap SEQ_PUT_DEC pattern')

    # Add bypass_orig_flow labels after show_smap_vma_flags
    old_after_flags = '''\tshow_smap_vma_flags(m, vma);

\tm_cache_vma(m, vma);

\treturn 0;
}'''

    new_after_flags = '''\tshow_smap_vma_flags(m, vma);
#ifdef CONFIG_KSU_SUSFS_SUS_MAP
bypass_orig_flow2:
#endif

\tm_cache_vma(m, vma);
#ifdef CONFIG_KSU_SUSFS_SUS_MAP
bypass_orig_flow:
#endif

\treturn 0;
}'''

    if old_after_flags in content:
        content = content.replace(old_after_flags, new_after_flags, 1)
        changes += 1
        print('    OK: show_smap bypass labels applied')
    else:
        print('    WARNING: Could not find show_smap end pattern for bypass labels')

# 9d. Modify pagemap_read — add SUS_MAP zeroing after walk_page_range
if 'pm.buffer->pme = 0' not in content:
    old_pagemap = '''\t\tret = walk_page_range(start_vaddr, end, &pagemap_walk);
\t\tmmap_read_unlock(mm);
\t\tstart_vaddr = end;'''

    new_pagemap = '''\t\tret = walk_page_range(start_vaddr, end, &pagemap_walk);
\t\tmmap_read_unlock(mm);
#ifdef CONFIG_KSU_SUSFS_SUS_MAP
\t\tvma = find_vma(mm, start_vaddr);
\t\tif (vma && vma->vm_file) {
\t\t\tstruct inode *inode = file_inode(vma->vm_file);
\t\t\tif (unlikely(inode->i_mapping->flags & BIT_SUS_MAPS) && susfs_is_current_proc_umounted()) {
\t\t\t\tpm.show_pfn = false;
\t\t\t\tpm.buffer->pme = 0;
\t\t\t}
\t\t}
#endif
\t\tstart_vaddr = end;'''

    if old_pagemap in content:
        content = content.replace(old_pagemap, new_pagemap, 1)
        changes += 1
        print('    OK: pagemap_read SUS_MAP zeroing applied')
    else:
        print('    WARNING: Could not find exact pagemap_read pattern')

if changes > 0:
    with open('fs/proc/task_mmu.c', 'w') as f:
        f.write(content)
    print(f'    Total changes: {changes}')
else:
    print('    No changes made')
PYEOF

verify_fix "fs/proc/task_mmu.c" "susfs_def.h"

# =====================================================================
# 10. fs/namespace.c — add includes/globals + susfs_mnt_alloc_id + modifications
# =====================================================================
fix_file "fs/namespace.c" "add SUSFS includes/globals + susfs_mnt_alloc_id + modify 4 functions"

python3 << 'PYEOF'
with open('fs/namespace.c', 'r') as f:
    content = f.read()

changes = 0

# 10a. Add SUSFS include after '#include <linux/sched/task.h>'
if '#include <linux/susfs_def.h>' not in content:
    old = '#include <linux/sched/task.h>\n#include <linux/fs_context.h>\n\n#include "pnode.h"\n#include "internal.h"'
    new = '#include <linux/sched/task.h>\n#include <linux/fs_context.h>\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n#include <linux/susfs_def.h>\n#endif // #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\n#include "pnode.h"\n#include "internal.h"'
    if old in content:
        content = content.replace(old, new, 1)
        changes += 1
        print('    OK: susfs_def.h include added')
    else:
        print('    WARNING: Could not find includes block for susfs_def.h')

# 10b. Add SUSFS externs and static variables after '#include "internal.h"'
if 'susfs_mnt_id_ida' not in content:
    old = '#include "pnode.h"\n#include "internal.h"\n\n/* Maximum number of mounts'
    new = '''#include "pnode.h"
#include "internal.h"

#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
extern bool susfs_is_current_ksu_domain(void);
extern bool susfs_is_current_zygote_domain(void);
extern bool susfs_is_boot_completed_triggered;
static DEFINE_IDA(susfs_mnt_id_ida);
static DEFINE_IDA(susfs_mnt_group_ida);
static atomic64_t susfs_ksu_mounts = ATOMIC64_INIT(0);
static int susfs_mnt_id_start = DEFAULT_KSU_MNT_ID;
static int susfs_mnt_group_start = DEFAULT_KSU_MNT_GROUP_ID;

#define CL_ZYGOTE_COPY_MNT_NS BIT(24) /* used by copy_mnt_ns() */
#define CL_COPY_MNT_NS BIT(25) /* used by copy_mnt_ns() */
#endif // #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT

/* Maximum number of mounts'''
    if old in content:
        content = content.replace(old, new, 1)
        changes += 1
        print('    OK: SUSFS externs and static vars added')
    else:
        print('    WARNING: Could not find internal.h block for SUSFS globals')

# 10c. Add susfs_mnt_alloc_id function before mnt_alloc_id
if 'susfs_mnt_alloc_id' not in content or content.count('susfs_mnt_alloc_id') <= 1:
    old = 'static int mnt_alloc_id(struct mount *mnt)\n{\n\tint res = ida_alloc(&mnt_id_ida, GFP_KERNEL);'
    new = '''#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
// Our own mnt_alloc_id() that assigns mnt_id starting from DEFAULT_KSU_MNT_ID
static int susfs_mnt_alloc_id(struct mount *mnt)
{
\tint res = ida_alloc_min(&susfs_mnt_id_ida, susfs_mnt_id_start, GFP_KERNEL);

\tif (res < 0)
\t\treturn res;
\tmnt->mnt_id = res;
\tsusfs_mnt_id_start = mnt->mnt_id + 1;
\treturn 0;
}
#endif

static int mnt_alloc_id(struct mount *mnt)
{
\tint res = ida_alloc(&mnt_id_ida, GFP_KERNEL);'''
    if old in content:
        content = content.replace(old, new, 1)
        changes += 1
        print('    OK: susfs_mnt_alloc_id function added (ida_alloc_min API)')
    else:
        print('    WARNING: Could not find mnt_alloc_id for susfs insertion')

# 10d. Modify mnt_free_id — add SUSFS backup ID handling
old_mnt_free = '''static void mnt_free_id(struct mount *mnt)
{
\tida_free(&mnt_id_ida, mnt->mnt_id);
}'''

new_mnt_free = '''static void mnt_free_id(struct mount *mnt)
{
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
\tint mnt_id_backup = mnt->mnt.susfs_mnt_id_backup;
\t// Check if mnt_id_backup is DEFAULT_KSU_MNT_ID_FOR_KSU_PROC_UNSHARE
\t// if so, these mnt_id were not assigned by mnt_alloc_id() so we don't need to free it.
\tif (unlikely(mnt_id_backup == DEFAULT_KSU_MNT_ID_FOR_KSU_PROC_UNSHARE)) {
\t\treturn;
\t}
\t// If mnt_id is sus (>= DEFAULT_KSU_MNT_ID), free from susfs_mnt_id_ida
\tif (unlikely(mnt->mnt_id >= DEFAULT_KSU_MNT_ID)) {
\t\tida_free(&susfs_mnt_id_ida, mnt->mnt_id);
\t\tif (susfs_mnt_id_start > mnt->mnt_id)
\t\t\t\tsusfs_mnt_id_start = mnt->mnt_id;
\t\treturn;
\t}
\t// If mnt_id_backup is not 0, it contains the original mnt_id (mnt_id was spoofed)
\tif (likely(mnt_id_backup)) {
\t\tida_free(&mnt_id_ida, mnt_id_backup);
\t\treturn;
\t}
#endif
\tida_free(&mnt_id_ida, mnt->mnt_id);
}'''

if old_mnt_free in content:
    content = content.replace(old_mnt_free, new_mnt_free, 1)
    changes += 1
    print('    OK: mnt_free_id SUSFS modifications applied')
else:
    print('    WARNING: Could not find exact mnt_free_id pattern')

# 10e. Modify mnt_alloc_group_id — add SUSFS sus group ID allocation
old_group_alloc = '''static int mnt_alloc_group_id(struct mount *mnt)
{
\tint res = ida_alloc_min(&mnt_group_ida, 1, GFP_KERNEL);

\tif (res < 0)
\t\treturn res;
\tmnt->mnt_group_id = res;
\treturn 0;
}'''

new_group_alloc = '''static int mnt_alloc_group_id(struct mount *mnt)
{
\tint res;

#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
\tif (mnt->mnt_id >= DEFAULT_KSU_MNT_ID) {
\t\tres = ida_alloc_min(&susfs_mnt_group_ida, susfs_mnt_group_start, GFP_KERNEL);
\t\tif (res < 0)
\t\t\treturn res;
\t\tmnt->mnt_group_id = res;
\t\tsusfs_mnt_group_start = mnt->mnt_group_id + 1;
\t\treturn 0;
\t}
#endif
\tres = ida_alloc_min(&mnt_group_ida, 1, GFP_KERNEL);

\tif (res < 0)
\t\treturn res;
\tmnt->mnt_group_id = res;
\treturn 0;
}'''

if old_group_alloc in content:
    content = content.replace(old_group_alloc, new_group_alloc, 1)
    changes += 1
    print('    OK: mnt_alloc_group_id SUSFS modifications applied')
else:
    print('    WARNING: Could not find exact mnt_alloc_group_id pattern')

# 10f. Modify mnt_release_group_id — add SUSFS sus group ID freeing
old_group_release = '''void mnt_release_group_id(struct mount *mnt)
{
\tida_free(&mnt_group_ida, mnt->mnt_group_id);
\tmnt->mnt_group_id = 0;
}'''

new_group_release = '''void mnt_release_group_id(struct mount *mnt)
{
\tint id = mnt->mnt_group_id;
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
\tif (id >= DEFAULT_KSU_MNT_GROUP_ID) {
\t\tida_free(&susfs_mnt_group_ida, id);
\t\tif (susfs_mnt_group_start > id)
\t\t\tsusfs_mnt_group_start = id;
\t\tmnt->mnt_group_id = 0;
\t\treturn;
\t}
#endif
\tida_free(&mnt_group_ida, id);
\tmnt->mnt_group_id = 0;
}'''

if old_group_release in content:
    content = content.replace(old_group_release, new_group_release, 1)
    changes += 1
    print('    OK: mnt_release_group_id SUSFS modifications applied')
else:
    print('    WARNING: Could not find exact mnt_release_group_id pattern')

# 10g. Modify vfs_create_mount — fix alloc_vfsmnt call and add zygote reorder
old_vfs_create = '''\tmnt = alloc_vfsmnt(fc->source ?: "none");
\tif (!mnt)
\t\treturn ERR_PTR(-ENOMEM);'''

new_vfs_create = '''#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
\t// For newly created mounts, the only caller process we care is KSU
\tif (unlikely(susfs_is_current_ksu_domain())) {
\t\tmnt = alloc_vfsmnt(fc->source ?: "none", true, 0);
\t\tgoto bypass_orig_flow;
\t}
\tmnt = alloc_vfsmnt(fc->source ?: "none", false, 0);
bypass_orig_flow:
#else
\tmnt = alloc_vfsmnt(fc->source ?: "none");
#endif
\tif (!mnt)
\t\treturn ERR_PTR(-ENOMEM);'''

if old_vfs_create in content:
    content = content.replace(old_vfs_create, new_vfs_create, 1)
    changes += 1
    print('    OK: vfs_create_mount alloc_vfsmnt SUSFS fix applied')
else:
    print('    WARNING: Could not find exact vfs_create_mount alloc_vfsmnt pattern')

# Add zygote mnt_id reorder after mount setup in vfs_create_mount
old_vfs_mount_end = '''\tmnt->mnt_mountpoint\t= mnt->mnt.mnt_root;
\tmnt->mnt_parent\t\t= mnt;

\tlock_mount_hash();
\tlist_add_tail(&mnt->mnt_instance, &mnt->mnt.mnt_sb->s_mounts);
\tunlock_mount_hash();
\treturn &mnt->mnt;
}
EXPORT_SYMBOL(vfs_create_mount);'''

new_vfs_mount_end = '''\tmnt->mnt_mountpoint\t= mnt->mnt.mnt_root;
\tmnt->mnt_parent\t\t= mnt;

#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
\t// If caller process is zygote, then it is a normal mount, so we just reorder the mnt_id
\tif (susfs_is_current_zygote_domain()) {
\t\tmnt->mnt.susfs_mnt_id_backup = mnt->mnt_id;
\t\tmnt->mnt_id = current->susfs_last_fake_mnt_id++;
\t}
#endif

\tlock_mount_hash();
\tlist_add_tail(&mnt->mnt_instance, &mnt->mnt.mnt_sb->s_mounts);
\tunlock_mount_hash();
\treturn &mnt->mnt;
}
EXPORT_SYMBOL(vfs_create_mount);'''

if old_vfs_mount_end in content:
    content = content.replace(old_vfs_mount_end, new_vfs_mount_end, 1)
    changes += 1
    print('    OK: vfs_create_mount zygote mnt_id reorder applied')
else:
    print('    WARNING: Could not find exact vfs_create_mount end pattern')

if changes > 0:
    with open('fs/namespace.c', 'w') as f:
        f.write(content)
    print(f'    Total changes: {changes}')
else:
    print('    No changes made')
PYEOF

verify_fix "fs/namespace.c" "susfs_mnt_alloc_id"

# =====================================================================
# Additional fixes for fs/susfs.c and include/linux/susfs.h
# =====================================================================
fix_file "fs/susfs.c" "fix unused cur_uid variable warnings"

if [ -f "fs/susfs.c" ]; then
  python3 -c "
import re
with open('fs/susfs.c', 'r') as f:
    content = f.read()
content = content.replace(
    'uid_t cur_uid = current_uid().val;\n\treturn (likely(susfs_is_current_proc_umounted()) &&\n\t\tunlikely(current_uid().val != i_uid));',
    'uid_t cur_uid = current_uid().val;\n\treturn (likely(susfs_is_current_proc_umounted()) &&\n\t\tunlikely(cur_uid != i_uid));'
)
with open('fs/susfs.c', 'w') as f:
    f.write(content)
print('    OK: cur_uid usage fixed')
" 2>/dev/null || echo "    SKIP: fs/susfs.c not found yet"
fi

# Add susfs_try_umount functions if not present
fix_file "fs/susfs.c" "add susfs_try_umount + susfs_add_try_umount (sidex15 approach)"

if [ -f "fs/susfs.c" ] && ! grep -q 'void susfs_try_umount' fs/susfs.c; then
  cat >> fs/susfs.c << 'TRYUMOUNT_EOF'

#ifdef CONFIG_KSU_SUSFS_TRY_UMOUNT
static DEFINE_SPINLOCK(susfs_spin_lock_try_umount);
extern void try_umount(const char *mnt, int flags);
static LIST_HEAD(LH_TRY_UMOUNT_PATH);

void susfs_add_try_umount(void __user **user_info) {
	struct st_susfs_try_umount info = {0};
	struct st_susfs_try_umount_list *new_list = NULL;

	if (copy_from_user(&info, (struct st_susfs_try_umount __user*)*user_info, sizeof(info))) {
		info.err = -EFAULT;
		goto out_copy_to_user;
	}

	if (info.mnt_mode == TRY_UMOUNT_DEFAULT) {
		info.mnt_mode = 0;
	} else if (info.mnt_mode == TRY_UMOUNT_DETACH) {
		info.mnt_mode = MNT_DETACH;
	} else {
		SUSFS_LOGE("Unsupported mnt_mode: %d\n", info.mnt_mode);
		info.err = -EINVAL;
		goto out_copy_to_user;
	}

	new_list = kmalloc(sizeof(struct st_susfs_try_umount_list), GFP_KERNEL);
	if (!new_list) {
		info.err = -ENOMEM;
		goto out_copy_to_user;
	}

	memcpy(&new_list->info, &info, sizeof(info));

	INIT_LIST_HEAD(&new_list->list);
	spin_lock(&susfs_spin_lock_try_umount);
	list_add_tail(&new_list->list, &LH_TRY_UMOUNT_PATH);
	spin_unlock(&susfs_spin_lock_try_umount);
	SUSFS_LOGI("target_pathname: '%s', umount options: %d, is successfully added to LH_TRY_UMOUNT_PATH\n",
		new_list->info.target_pathname, new_list->info.mnt_mode);
	info.err = 0;
out_copy_to_user:
	if (copy_to_user(&((struct st_susfs_try_umount __user*)*user_info)->err, &info.err, sizeof(info.err))) {
		info.err = -EFAULT;
	}
	SUSFS_LOGI("CMD_SUSFS_ADD_TRY_UMOUNT -> ret: %d\n", info.err);
}

void susfs_try_umount(uid_t uid) {
	struct st_susfs_try_umount_list *cursor = NULL;

	/* Umount in reverse order */
	list_for_each_entry_reverse(cursor, &LH_TRY_UMOUNT_PATH, list) {
		SUSFS_LOGI("umounting '%s' for uid: %u\n", cursor->info.target_pathname, uid);
		try_umount(cursor->info.target_pathname, cursor->info.mnt_mode);
	}
}
#endif /* CONFIG_KSU_SUSFS_TRY_UMOUNT */
TRYUMOUNT_EOF
  verify_fix "fs/susfs.c" "void susfs_try_umount"
else
  echo "    SKIP: already present or file not found"
fi

# Add structs to include/linux/susfs.h
fix_file "include/linux/susfs.h" "add try_umount structs and prototypes"

if [ -f "include/linux/susfs.h" ] && ! grep -q 'st_susfs_try_umount' include/linux/susfs.h; then
  sed -i '/\/\* susfs_init \*\//i\
/* try_umount */\
#ifdef CONFIG_KSU_SUSFS_TRY_UMOUNT\
struct st_susfs_try_umount {\
\tchar                                    target_pathname[SUSFS_MAX_LEN_PATHNAME];\
\tint                                     mnt_mode;\
\tint                                     err;\
};\
\
struct st_susfs_try_umount_list {\
\tstruct list_head                        list;\
\tstruct st_susfs_try_umount              info;\
};\
\
void susfs_add_try_umount(void __user **user_info);\
void susfs_try_umount(uid_t uid);\
#endif /* CONFIG_KSU_SUSFS_TRY_UMOUNT */\
' include/linux/susfs.h
  verify_fix "include/linux/susfs.h" "st_susfs_try_umount"
else
  echo "    SKIP: structs already present or file not found"
fi

# Fix susfs_reorder_mnt_id to skip sus mounts
fix_file "fs/namespace.c" "fix susfs_reorder_mnt_id to skip sus mounts + WRITE_ONCE/READ_ONCE"

python3 -c "
import re
with open('fs/namespace.c', 'r') as f:
    content = f.read()

# Find and replace the list_for_each_entry loop inside susfs_reorder_mnt_id
old_loop = '''\tlist_for_each_entry(mnt, &mnt_ns->list, mnt_list) {
\t\tmnt->mnt.susfs_mnt_id_backup = mnt->mnt_id;
\t\tmnt->mnt_id = first_mnt_id++;
\t}'''

new_loop = '''\tlist_for_each_entry(mnt, &mnt_ns->list, mnt_list) {
\t\t/* Skip sus mounts that haven't been umounted yet */
\t\tif (mnt->mnt_id >= DEFAULT_KSU_MNT_ID) {
\t\t\tcontinue;
\t\t}
\t\tWRITE_ONCE(mnt->mnt.susfs_mnt_id_backup, READ_ONCE(mnt->mnt_id));
\t\tWRITE_ONCE(mnt->mnt_id, first_mnt_id++);
\t}'''

if old_loop in content:
    content = content.replace(old_loop, new_loop)
    with open('fs/namespace.c', 'w') as f:
        f.write(content)
    print('    OK: susfs_reorder_mnt_id patched with DEFAULT_KSU_MNT_ID skip + WRITE_ONCE/READ_ONCE')
elif 'DEFAULT_KSU_MNT_ID' in content and 'susfs_reorder_mnt_id' in content:
    print('    SKIP: susfs_reorder_mnt_id already patched')
else:
    print('    INFO: susfs_reorder_mnt_id will be patched after SUSFS patch applied')
" 2>/dev/null || true

# Add atomic64_inc counter increment
fix_file "fs/namespace.c" "add atomic64_inc(&susfs_ksu_mounts) in vfs_create_mount"

python3 -c "
with open('fs/namespace.c', 'r') as f:
    content = f.read()

old_block = '''\t\tmnt = alloc_vfsmnt(fc->source ?: \"none\", true, 0);
\t\tgoto bypass_orig_flow;'''

new_block = '''\t\tmnt = alloc_vfsmnt(fc->source ?: \"none\", true, 0);
\t\tatomic64_inc(&susfs_ksu_mounts);
\t\tgoto bypass_orig_flow;'''

if old_block in content and 'atomic64_inc(&susfs_ksu_mounts)' not in content:
    content = content.replace(old_block, new_block)
    with open('fs/namespace.c', 'w') as f:
        f.write(content)
    print('    OK: atomic64_inc(&susfs_ksu_mounts) added in vfs_create_mount')
elif 'atomic64_inc(&susfs_ksu_mounts)' in content:
    print('    SKIP: atomic64_inc already present')
else:
    print('    INFO: atomic64_inc will be added after SUSFS patch applied')
" 2>/dev/null || true

# =====================================================================
# Clean up .rej files
# =====================================================================
echo ""
echo "  Cleaning up .rej files..."
find . -name '*.rej' -not -path './.git/*' -delete 2>/dev/null || true
REJ_REMAINING=$(find . -name '*.rej' -not -path './.git/*' 2>/dev/null | wc -l)
echo "  Remaining .rej files: $REJ_REMAINING"

# =====================================================================
# Summary
# =====================================================================
echo ""
echo "========================================"
echo "  Fix SUSFS rejected hunks — Summary"
echo "========================================"
echo ""

if [ "$FIXES_FAILED" -ne 0 ]; then
  echo "WARNING: Some fixes failed to apply. Check the output above."
  echo "         The build will likely fail."
else
  echo "All SUSFS rejection fixes applied successfully!"
fi
echo ""
