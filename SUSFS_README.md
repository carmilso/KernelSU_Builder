# KernelSU + SUSFS Integration

This project now supports building kernels with **KernelSU-Next** and **SUSFS** (Systemless UID and FileSystem Spoofing) for enhanced root hiding capabilities.

## Overview

### What's SUSFS?

SUSFS (Systemless UID and FileSystem Spoofing) is a kernel-level root hiding solution that works in conjunction with KernelSU. It provides advanced features to hide root access from detection mechanisms:

- **Path hiding (SUS_PATH)**: Hide specific files and directories from root detection apps
- **Mount hiding (SUS_MOUNT)**: Hide suspicious mount points
- **Kstat spoofing (SUS_KSTAT)**: Spoof file statistics (inode, device ID, etc.)
- **Try umount support (TRY_UMOUNT)**: Automatically unmount suspicious mounts for specific UIDs
- **Uname spoofing**: Spoof kernel version information
- **Symbol hiding**: Hide KernelSU/SUSFS symbols from /proc/kallsyms
- **Cmdline/bootconfig spoofing**: Spoof kernel command line and boot config
- **Open redirect**: Redirect file opens to alternative paths
- **Map hiding (SUS_MAP)**: Hide memory mappings from /proc/[pid]/maps

### Version Support

| Kernel Version | KernelSU Type | SUSFS | Hook Method | Configuration |
|----------------|---------------|-------|-------------|---------------|
| LineageOS 23.0 | Standard KernelSU-Next | ❌ No | kprobes | `LineageOS-23-kebab` |
| LineageOS 23.2 | KernelSU-Next-SUSFS | ✅ Yes | manual hooks | `LineageOS-23.2-kebab` |

## Architecture

### Modular Design

The SUSFS integration is designed to be modular and retrocompatible:

1. **sources.yaml**: Configuration file defines which versions use SUSFS
2. **Workflow detection**: Automatically detects SUSFS flag and executes appropriate steps
3. **Separate scripts**: Each component has its own script for maintainability

### File Structure

```
KernelSU_Builder/
├── scripts/                     # SUSFS integration scripts
│   ├── kernelSU-susfs.sh       # Install KernelSU-Next-SUSFS driver
│   ├── apply-susfs.sh          # Main SUSFS coordinator script
│   ├── fix-susfs-rejections.sh # Fix rejected patch hunks
│   ├── apply-ksu-hooks.sh      # Apply 7 manual KernelSU hooks
│   ├── configure-susfs.sh      # Configure KernelSU + SUSFS options
│   └── check-susfs-version.sh  # Check for new SUSFS patch versions
├── susfs-2.0.0.patch           # SUSFS kernel patch (from TheSillyOk)
└── sources.yaml                # Configuration with SUSFS support
```

## Configuration

### sources.yaml Structure for SUSFS

```yaml
LineageOS-23.2-kebab:
  kernel:
    - git clone --depth=1 https://github.com/LineageOS/android_kernel_oneplus_sm8250.git -b lineage-23.2
  
  # KernelSU-Next-SUSFS driver (wshamroukh's pre-patched legacy with SUSFS glue)
  kernelSU:
    type: susfs-legacy
    repo: https://github.com/wshamroukh/KernelSU-Next-SUSFS-kernelv4.19
    branch: legacy
  
  # SUSFS v2.0.0 patch and hooks
  susfs:
    enabled: true
    patch: susfs-2.0.0.patch
  
  config:
    - make O=out ARCH=arm64 LLVM=1 ...
  
  # Note: SUSFS config options are applied via configure-susfs.sh script
  # No need to list them in sources.yaml
```

### Build Flow

#### Standard KernelSU (LineageOS 23.0)
```
1. Clone kernel
2. Install standard KernelSU-Next (via setup.sh)
3. Configure with kprobes hooks
4. Build
```

#### KernelSU + SUSFS (LineageOS 23.2)
```
1. Clone kernel
2. Install KernelSU-Next-SUSFS driver (wshamroukh variant)
3. Apply SUSFS v2.0.0 kernel patch
4. Fix rejected patch hunks (automated)
5. Apply 7 manual KernelSU hooks for non-GKI
6. Configure with manual hooks + SUSFS options
7. Build
```

## Scripts Documentation

### kernelSU-susfs.sh

Installs the wshamroukh KernelSU-Next-SUSFS driver:

- Clones the driver repository
- Copies driver files to `drivers/kernelsu/`
- Computes and injects proper KSU version into Kbuild
- Saves version to `ksu_version.txt`

### apply-susfs.sh

Main coordinator script:

1. **Clean kernel tree**: Restore all patched files to pristine state
2. **Apply SUSFS patch**: Apply susfs-2.0.0.patch with `--reject`
3. **Fix rejections**: Call fix-susfs-rejections.sh
4. **Apply hooks**: Call apply-ksu-hooks.sh
5. **Verify installation**: Check KernelSU driver and build system registration

### configure-susfs.sh

Configures kernel with KernelSU + SUSFS options:

- Enables KSU and disables debug mode
- Sets manual hook mode (disables kprobes)
- Enables all 11 SUSFS feature flags
- Runs olddefconfig to resolve dependencies
- Verifies all critical options are set correctly

This script is called automatically by the workflow after base kernel config is generated.

### fix-susfs-rejections.sh

Fixes rejected hunks from SUSFS patch:

- **10 files** with targeted fixes for LineageOS 4.19 differences
- Uses combination of `sed` and `python3` for complex replacements
- Verifies each fix with markers

Fixed files:
1. fs/Makefile
2. include/linux/mount.h
3. fs/proc_namespace.c
4. fs/proc/cmdline.c
5. kernel/kallsyms.c
6. fs/notify/fdinfo.c
7. fs/proc/base.c
8. fs/namei.c (4 functions)
9. fs/proc/task_mmu.c
10. fs/namespace.c (5 functions)

### apply-ksu-hooks.sh

Applies 7 manual KernelSU hooks for non-GKI kernels:

1. **fs/exec.c**: ksu_handle_execveat (SUSFS-aware)
2. **fs/open.c**: ksu_handle_faccessat (SUSFS-aware)
3. **fs/read_write.c**: ksu_handle_vfs_read
4. **fs/stat.c**: ksu_handle_stat (SUSFS-aware)
5. **drivers/input/input.c**: ksu_handle_input_handle_event
6. **fs/devpts/inode.c**: ksu_handle_devpts
7. **kernel/reboot.c**: ksu_handle_sys_reboot (CRITICAL for SUSFS supercalls)

SUSFS-aware hooks check `susfs_is_current_proc_umounted()` to skip KSU handlers when a process is umounted by SUSFS.

### check-susfs-version.sh

Checks for new SUSFS patch versions:

- Downloads upstream patch from TheSillyOk repository
- Compares SHA256 hashes
- Reports differences
- Sets GitHub Actions output variables for workflow notifications

## Build Options

### Vanilla Kernel (Optional)

By default, the workflow **only builds the KernelSU-enabled kernel** to save time and resources. The vanilla kernel (without KernelSU) is now **optional** and disabled by default.

#### When to Build Vanilla Kernel

Enable vanilla kernel build for:
- **Debugging**: Compare behavior between vanilla and KernelSU versions
- **Testing**: Verify base kernel functionality
- **Troubleshooting**: Isolate issues to kernel base vs KernelSU

#### How to Enable

1. **Via GitHub UI** (Manual workflow):
   - Go to Actions tab → KernelSU Next Builder
   - Click "Run workflow"
   - Check the box "Build kernel without KernelSU"
   - Click "Run workflow"

2. **Default Behavior**:
   - Push events: Only KernelSU kernel ✓
   - Automatic triggers: Only KernelSU kernel ✓
   - Manual trigger (unchecked): Only KernelSU kernel ✓

#### Performance Impact

| Build Mode | Compilation Time | Actions Minutes | Output ZIPs |
|------------|-----------------|-----------------|-------------|
| Default (KernelSU only) | ~30-45 min | 1x | 1 per version |
| With vanilla kernel | ~60-90 min | 2x | 2 per version |

**Savings**: ~50% reduction in build time and CI/CD minutes!

## Workflow Integration

The GitHub Actions workflow automatically detects SUSFS configuration:

```yaml
- name: Check if SUSFS is enabled for this version
  id: check-susfs
  run: |
    json=$(python -c "import sys, yaml, json; json.dump(yaml.safe_load(sys.stdin), sys.stdout)" < sources.yaml)
    susfs_enabled=$(echo "$json" | jq -r --arg v "$VERSION" '.[$v].susfs.enabled // false')
    echo "susfs_enabled=$susfs_enabled" >> $GITHUB_OUTPUT

- name: Add KernelSU-Next-SUSFS support to kernel
  if: steps.check-susfs.outputs.susfs_enabled == 'true'
  run: ./kernelSU-susfs.sh

- name: Apply SUSFS patches and hooks
  if: steps.check-susfs.outputs.susfs_enabled == 'true'
  run: ./apply-susfs.sh
```

## Adding SUSFS to a New Kernel Version

To add SUSFS support to a new kernel configuration:

1. **Update sources.yaml**:
   ```yaml
   YourKernel-Version:
     kernelSU:
       type: susfs-legacy
       repo: https://github.com/wshamroukh/KernelSU-Next-SUSFS-kernelv4.19
       branch: legacy
     
     susfs:
       enabled: true
       patch: susfs-2.0.0.patch
     
     config:
       - make O=out ARCH=arm64 ... your_defconfig
     
     # Note: SUSFS options are automatically applied via configure-susfs.sh
     # No need to manually list them here
   ```

2. **Test the build**: Push to trigger workflow

3. **Verify**:
   - Check workflow logs for SUSFS application
   - Look for "Configuring KernelSU + SUSFS" step
   - Verify kernel config includes `CONFIG_KSU_SUSFS=y`
   - Test kernel with KernelSU Manager

## Troubleshooting

### Build Fails at SUSFS Patch Application

**Problem**: SUSFS patch fails to apply cleanly

**Solution**: 
- Check `fix-susfs-rejections.sh` output for specific failures
- Kernel may have different structure than expected
- May need to update fix script for your kernel version

### Manual Hooks Not Applied

**Problem**: `apply-ksu-hooks.sh` reports hook failures

**Solution**:
- Hooks depend on specific function signatures
- Check if function names/signatures changed in your kernel
- Update hook patterns in `apply-ksu-hooks.sh` if needed

### CONFIG_KSU_SUSFS Not Enabled

**Problem**: Verification fails with "CONFIG_KSU_SUSFS not enabled"

**Solution**:
- Check `susfs-config` section in sources.yaml
- Ensure all SUSFS options are being applied
- Run `make menuconfig` locally to verify dependencies

### KernelSU Version Shows as "1" or "v0.0.1"

**Problem**: KernelSU Manager shows wrong version

**Solution**:
- This happens when Kbuild git detection fails
- `kernelSU-susfs.sh` should fix this automatically
- Check that the script successfully updated `drivers/kernelsu/Kbuild`

## References

- [KernelSU Documentation](https://kernelsu.org/)
- [KernelSU Non-GKI Integration Guide](https://kernelsu.org/guide/how-to-integrate-for-non-gki.html)
- [SUSFS Original (sidex15)](https://github.com/sidex15/SUSFS4KSU)
- [SUSFS v2.0.0 Patch (TheSillyOk)](https://github.com/TheSillyOk/kernel_ls_patches)
- [KernelSU-Next-SUSFS Driver (wshamroukh)](https://github.com/wshamroukh/KernelSU-Next-SUSFS-kernelv4.19)

## Credits

- **KernelSU Team**: Original KernelSU implementation
- **sidex15**: Original SUSFS concept and implementation
- **TheSillyOk**: SUSFS v2.0.0 kernel patches
- **wshamroukh**: KernelSU-Next-SUSFS integration and driver modifications

## License

This project follows the same license as the Linux kernel (GPL-2.0).
