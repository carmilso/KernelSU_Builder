# KernelSU Builder

An automated CI/CD pipeline for building Android kernels with optional KernelSU-Next support using GitHub Actions. Features intelligent caching, parallel builds, and comprehensive error handling for efficient kernel compilation.

> **Note:** This is a fork adapted for OnePlus 8T (kebab) from the original [KernelSU Builder by HowWof](https://github.com/HowWof/KernelSU_Builder).

[![Build Kernel](https://github.com/carmilso/KernelSU_Builder/actions/workflows/build_kernel.yml/badge.svg)](https://github.com/carmilso/KernelSU_Builder/actions/workflows/build_kernel.yml)
[![Latest Release](https://img.shields.io/github/v/release/carmilso/KernelSU_Builder?label=Latest%20Release)](https://github.com/carmilso/KernelSU_Builder/releases/latest)
[![Watch KernelSU](https://github.com/carmilso/KernelSU_Builder/actions/workflows/watch_ksu.yml/badge.svg)](https://github.com/carmilso/KernelSU_Builder/actions/workflows/watch_ksu.yml)

## Table of Contents

- [Key Features](#key-features)
- [How It Works](#how-it-works)
  - [Workflow Overview](#workflow-overview)
  - [Build Pipeline](#build-pipeline)
  - [Detailed Build Steps](#detailed-build-steps)
- [Performance Optimizations](#performance-optimizations)
  - [ccache (Compiler Cache)](#ccache-compiler-cache)
  - [Apt Package Cache](#apt-package-cache)
  - [Clang Toolchain Cache](#clang-toolchain-cache)
- [Configuration](#configuration)
  - [sources.yaml Structure](#sourcesyaml-structure)
  - [Customizing for Your Device](#customizing-for-your-device)
  - [Environment Variables](#environment-variables)
- [Building Kernel](#building-kernel)
- [Flashing the Kernel](#flashing-the-kernel)
- [Troubleshooting](#troubleshooting)
  - [Build Artifacts](#build-artifacts)
  - [Common Issues](#common-issues)
  - [Viewing Logs](#viewing-logs)

## Key Features

- 🚀 **Optimized Build Times**: ccache integration for 3-5x faster incremental builds
- 🔄 **Dual Compilation**: Builds both vanilla and KernelSU-enabled kernel variants
- 📦 **Smart Caching**: Caches Clang toolchain, ccache, and apt packages
- ✅ **Robust Error Handling**: Strict validation and early failure detection
- 🎯 **Matrix Builds**: Parallel compilation of multiple kernel versions
- 📊 **Build Artifacts**: Automatic upload of .config files for debugging
- 🏷️ **Semantic Releases**: Descriptive tags and release notes
- 🔧 **LLVM Compilation**: Full Clang/LLVM toolchain integration
- 🎣 **KernelSU kprobes**: Uses kprobes hook method for KernelSU-Next

## How It Works

### Workflow Overview

The build process consists of two main compilation cycles:

1. **Vanilla Kernel Build** - Clean kernel without KernelSU
2. **KernelSU Build** - Kernel with KernelSU-Next integration (kprobes method)

Both builds are performed for each version defined in the matrix (LineageOS 23.0 and 23.2).

### Build Pipeline

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Environment Setup                                         │
│    ├─ Cache apt packages (~1-2 min saved)                   │
│    ├─ Install dependencies (Python, build tools)            │
│    ├─ Restore Clang r547379 from cache                      │
│    └─ Setup ccache (2GB, per-version key)                   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. First Build (Vanilla Kernel)                             │
│    ├─ Clone kernel source from sources.yaml                 │
│    ├─ Generate .config (defconfig + overlay)                │
│    ├─ Compile with Clang/LLVM                               │
│    ├─ Package with AnyKernel3                               │
│    └─ Save to outw/false/                                   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. Clean & Prepare for KernelSU                             │
│    ├─ Clean out directory                                   │
│    ├─ Restore git-modified files                            │
│    └─ Install KernelSU-Next (legacy branch)                 │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. Second Build (KernelSU Kernel)                           │
│    ├─ Regenerate .config from sources.yaml                  │
│    ├─ Inject KernelSU config via scripts/config:            │
│    │   • CONFIG_KSU=y                                       │
│    │   • CONFIG_KSU_KPROBES_HOOK=y                          │
│    │   • CONFIG_KSU_MANUAL_HOOK=n                           │
│    ├─ Verify configuration (strict validation)              │
│    ├─ Compile with Clang/LLVM                               │
│    ├─ Show ccache statistics                                │
│    └─ Package with AnyKernel3                               │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. Release Creation                                          │
│    ├─ Upload build artifacts (.config files)                │
│    ├─ Create release with both kernels                      │
│    └─ Tag: v{KERNELSU_VERSION}-{RUN_NUMBER}                │
└─────────────────────────────────────────────────────────────┘
```

### Detailed Build Steps

#### Configuration Generation

The kernel configuration is generated using commands defined in `sources.yaml`:

```bash
# Step 1: Apply defconfig and overlays
make O=out ARCH=arm64 LLVM=1 \
     CROSS_COMPILE=aarch64-linux-gnu- \
     CLANG_TRIPLE=aarch64-linux-gnu- \
     vendor/kona-perf_defconfig vendor/oplus.config
```

For KernelSU builds, additional configuration is injected using the kernel's `scripts/config` tool:

```bash
# Step 2: Enable KernelSU with kprobes hook
scripts/config --file out/.config --enable KSU
scripts/config --file out/.config --disable KSU_MANUAL_HOOK
scripts/config --file out/.config --enable KSU_KPROBES_HOOK

# Step 3: Resolve all dependencies
make O=out ARCH=arm64 LLVM=1 \
     CROSS_COMPILE=aarch64-linux-gnu- \
     CLANG_TRIPLE=aarch64-linux-gnu- \
     olddefconfig
```

#### Compilation Process

All compilation uses:
- **Compiler**: Clang r547379 (Android toolchain)
- **Out-of-tree build**: `O=out` directory for clean separation
- **LLVM**: Full LLVM toolchain integration (`LLVM=1`)
- **ccache**: Compiler cache for faster rebuilds
- **Parallel jobs**: `-j$(nproc --all)` for maximum CPU utilization

Environment variables set during build:
- `KBUILD_BUILD_HOST`: Github-Action
- `KBUILD_BUILD_USER`: KernelSU_Builder

#### Error Handling

The workflow includes strict error checking:

1. **Early Exit**: `set -e` stops execution on any command failure
2. **Config Verification**: Validates KSU options are properly set before building
3. **Toolchain Verification**: Ensures Clang is available in PATH
4. **Build Validation**: Checks kernel image exists after compilation

If KernelSU configuration fails, the build stops immediately with a clear error message, preventing wasted build time.

## Performance Optimizations

### ccache (Compiler Cache)

**How it works:**
- Caches compiled object files (`.o`) based on source code hash
- Subsequent builds with unchanged files retrieve cached objects instantly
- Separate cache per kernel version (`LineageOS-23-kebab`, `LineageOS-23.2-kebab`)
- Maximum size: 2GB per cache

**Performance Impact:**

| Build Type | First Build | Subsequent Builds | Speedup |
|------------|-------------|-------------------|---------|
| Full clean build | ~25-30 min  | ~8-12 min        | **3x faster** |
| Incremental (small changes) | ~25-30 min | ~3-5 min | **6-8x faster** |
| KernelSU rebuild only | ~5-8 min | ~2-3 min | **2-3x faster** |

**ccache Statistics:**

View cache hit rates in workflow logs under "ccache statistics" sections. A hit rate above 80% indicates effective caching.

Example output:
```
cache hit (direct):     4523
cache miss:              477
cache hit rate:        90.46 %
```

### Apt Package Cache

GitHub Actions caches all build dependencies to avoid re-downloading:

- **Packages cached**: ~40 build tools and libraries (gcc, binutils, etc.)
- **Time saved**: 1-2 minutes per build
- **Cache persistence**: Until package versions update

### Clang Toolchain Cache

The Clang r547379 toolchain (~2GB) is cached between builds:

- **First download**: ~3-5 minutes
- **Cached restoration**: ~30 seconds
- **Cache key**: `clang-r547379`
- **Shared across**: All workflow runs

## Configuration

### sources.yaml Structure

The `sources.yaml` file defines all build parameters for each kernel variant:

```yaml
LineageOS-23.2-kebab:
  kernel:
    # Clone kernel source repository
    - git clone --depth=1 <kernel-repo> -b <branch>
  
  clang:
    # Download and extract Clang toolchain
    - mkdir -p clang && wget -qO- <clang-url> | tar -C clang -zxf -
  
  config:
    # Generate kernel configuration
    - make O=out ARCH=arm64 LLVM=1 \
      CROSS_COMPILE=aarch64-linux-gnu- \
      CLANG_TRIPLE=aarch64-linux-gnu- \
      vendor/kona-perf_defconfig vendor/oplus.config
  
  build:
    # Compile kernel
    - make -j$(nproc --all) O=out ARCH=arm64 LLVM=1 \
      CROSS_COMPILE=aarch64-linux-gnu- \
      CLANG_TRIPLE=aarch64-linux-gnu-
  
  target:
    # Kernel image output path
    - out/arch/arm64/boot/Image
  
  anykernel:
    # Device codename for AnyKernel3
    - kebab
  
  kernelSU:
    # KernelSU version: next-legacy, next-stable, or next-latest
    - next-legacy
```

### Customizing for Your Device

To adapt this builder for another device:

1. **Add your kernel version** to `sources.yaml`:
   ```yaml
   MyDevice-12:
     kernel:
       - git clone --depth=1 https://github.com/user/kernel -b android-12
     clang:
       - mkdir -p clang && wget -qO- <clang-url> | tar -C clang -zxf -
     config:
       - make O=out ARCH=arm64 LLVM=1 mydevice_defconfig
     build:
       - make -j$(nproc --all) O=out ARCH=arm64 LLVM=1
     target:
       - out/arch/arm64/boot/Image.gz
     anykernel:
       - mydevice
     kernelSU:
       - next-stable
   ```

2. **Update the workflow matrix** in `.github/workflows/build_kernel.yml`:
   ```yaml
   strategy:
     matrix:
       version: ["MyDevice-12", "MyDevice-13"]
   ```

3. **Configure AnyKernel3** for your device in `anykernel_config.sh`

4. **Adjust defconfig paths** if your kernel uses different locations

### Environment Variables

**Global (job-level):**
- `VERSION`: Current build variant from matrix (e.g., `LineageOS-23.2-kebab`)

**Per-step (compilation only):**
- `KBUILD_BUILD_HOST`: Set to `Github-Action` for build identification
- `KBUILD_BUILD_USER`: Set to `KernelSU_Builder` for build identification

**Dynamic (set during workflow):**
- `KERNELSU_VERSION`: Read from `ksu_version.txt` file
- `ZIP_NO_KSU`: Filename for vanilla kernel zip
- `ZIP_KSU`: Filename for KernelSU kernel zip

## Building Kernel

Follow these steps to use this builder:

### Prerequisites

1. Fork this repository
2. Set up repository secrets (optional):
   - `GH_PAT`: Personal access token with `repo` scope (for advanced features)

### Triggering a Build

The workflow can be triggered in three ways:

1. **Automatic (on push)**: Push any changes to the repository
   ```bash
   git push origin main
   ```

2. **Manual (workflow_dispatch)**: 
   - Go to Actions tab
   - Select "KernelSU Next Builder - OnePlus 8T"
   - Click "Run workflow"

3. **Repository dispatch**: Trigger remotely via API
   ```bash
   curl -X POST \
     -H "Authorization: token $GH_PAT" \
     -H "Accept: application/vnd.github.v3+json" \
     https://api.github.com/repos/USER/REPO/dispatches \
     -d '{"event_type":"trigger-KernelSU-build"}'
   ```

### Build Process

1. Workflow clones sources defined in `sources.yaml`
2. Compiles kernel **without** KernelSU (vanilla variant)
3. Cleans build environment
4. Installs KernelSU-Next from GitHub
5. Compiles kernel **with** KernelSU integration
6. Packages both kernels with AnyKernel3
7. Creates a GitHub release with both zip files

### Build Output

Each successful build produces:
- `{VERSION}-NoKernelSU.zip` - Vanilla kernel
- `{VERSION}-KernelSU-Next-{VERSION}.zip` - KernelSU kernel
- Build artifacts (`.config` files) for 7 days

## Flashing the Kernel

To flash the kernel onto your OnePlus 8T:

### Requirements
- Unlocked bootloader
- Custom recovery (TWRP, OrangeFox, etc.) or root access
- Backup of current boot partition (recommended)

### Installation Steps

1. **Download the kernel**:
   - Go to [Releases](https://github.com/carmilso/KernelSU_Builder/releases/latest)
   - Download the zip matching your LineageOS version:
     - `LineageOS-23-kebab` for LineageOS 23.0
     - `LineageOS-23.2-kebab` for LineageOS 23.2
   - Choose KernelSU variant if you want root access

2. **Flash via recovery**:
   - Reboot to recovery mode
   - Select "Install" or "Install ZIP"
   - Navigate to the downloaded kernel zip
   - Swipe to confirm flash
   - Reboot system

3. **Flash via ADB sideload** (alternative):
   ```bash
   adb reboot sideload
   adb sideload LineageOS-23.2-kebab-KernelSU-Next-*.zip
   ```

4. **Verify installation**:
   - Check kernel version: `uname -r`
   - For KernelSU: Install KernelSU Manager app

### Compatibility

- **Device**: OnePlus 8T (kebab)
- **ROM**: LineageOS 23.0/23.2 (Android 14)
- **Kernel**: 4.19 (SM8250/kona)
- **KernelSU**: Next (legacy branch) with kprobes hook

⚠️ **Warning**: Flashing custom kernels can brick your device. Ensure you have a backup and understand the risks. This kernel is specifically built for OnePlus 8T - do not flash on other devices.

## Troubleshooting

### Build Artifacts

Every build automatically uploads diagnostic artifacts (retained for 7 days):

**Contents**:
- `kernel/out/.config` - Final kernel configuration
- `kernel/out/include/config/auto.conf` - Generated configuration

**To access**:
1. Go to the workflow run page on GitHub Actions
2. Scroll to the bottom "Artifacts" section
3. Download `kernel-{version}-build-info.zip`
4. Extract and inspect `.config` files

**Use cases**:
- Compare configurations between builds
- Debug configuration issues
- Verify KernelSU options are enabled
- Check for unexpected config changes

### Common Issues

#### Issue: Build fails with "CONFIG_KSU not enabled in .config!"

**Cause**: KernelSU configuration injection failed

**Solution**:
1. Check `ksu_version.txt` exists and is readable
2. Verify internet connectivity for KernelSU download
3. Ensure kernel version is compatible (use `next-legacy` for 4.x kernels)
4. Check KernelSU installation logs in workflow output

#### Issue: ccache hit rate is 0%

**Possible causes**:
- First build (expected behavior)
- GitHub Actions cache was cleared/expired
- Major kernel source changes
- Different `VERSION` in matrix (separate caches)

**Solution**: 
- Hit rate should improve on second build
- Check "Setup ccache" step shows "Cache restored"

#### Issue: Build timeout or runs too long

**Possible causes**:
- ccache not working properly
- Clang cache failed to restore
- Network issues downloading sources

**Solution**:
1. Check ccache statistics in logs
2. Verify "Restore Clang toolchain from cache" shows cache hit
3. Look for "Cache restored successfully" messages
4. Check for hung processes in build logs

#### Issue: Kernel doesn't boot after flashing

**Possible causes**:
- Wrong variant for your ROM version
- Incompatible ROM build
- Corrupted download

**Solution**:
1. Verify you downloaded the correct variant:
   - Check your ROM version: Settings → About phone
   - Match with kernel variant (23.0 vs 23.2)
2. Re-download and verify checksum
3. Flash vanilla variant to test
4. Check kernel logs: `adb shell dmesg`

#### Issue: "Clang not found in PATH"

**Cause**: Clang toolchain setup failed

**Solution**:
1. Check "Clone clang and kernel sources" step completed
2. Verify "Add Clang to PATH" shows correct path
3. Look for download errors in "Clone" step
4. Clang cache may be corrupted - clear and retry

### Viewing Logs

Build logs contain detailed information at multiple checkpoints:

**Configuration phase**:
```
=== Generating kernel config ===
=== Configuring KernelSU ===
=== Resolving config dependencies ===
=== Verifying KernelSU configuration ===
```

**Build phase**:
```
=== Building kernel ===
=== ccache statistics ===
=== Kernel build completed successfully ===
```

**ccache statistics sections**:
- After configuration (initial state)
- After KernelSU build (build impact)
- Final summary (overall efficiency)

**Kernel size information**:
```
Kernel Image:
Size: 25M
```

**What to look for**:
- ✅ "KernelSU configuration verified successfully"
- ✅ High ccache hit rate (>80% on subsequent builds)
- ✅ "Kernel build completed successfully"
- ❌ Any lines starting with "ERROR:"
- ⚠️ Any lines starting with "WARNING:"

---

## License

This project inherits the license from the [original KernelSU Builder](https://github.com/HowWof/KernelSU_Builder).

## Disclaimer

This workflow is provided as-is without any warranties. Use it at your own risk. Ensure compatibility and follow device-specific guidelines before flashing custom kernels. The maintainers are not responsible for any damage to your device.

---

## Credits

- **Original KernelSU Builder**: [HowWof](https://github.com/HowWof)
- **KernelSU-Next**: [KernelSU-Next Team](https://github.com/KernelSU-Next/KernelSU-Next)
- **LineageOS**: [LineageOS Project](https://github.com/LineageOS)
- **Clang/LLVM**: [Android Toolchain Team](https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/)
- **AnyKernel3**: [osm0sis](https://github.com/osm0sis/AnyKernel3)

Adapted for OnePlus 8T (kebab) by [carmilso](https://github.com/carmilso).
