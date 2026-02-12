# Dependency Tracking Files

This directory contains SHA and version tracking files used by the `watch_ksu.yml` workflow to detect updates in upstream dependencies.

## Tracked Dependencies

- **lineage-23.0.sha**: LineageOS kernel lineage-23.0 branch commit SHA
- **lineage-23.2.sha**: LineageOS kernel lineage-23.2 branch commit SHA
- **kernelsu-next-legacy.sha**: KernelSU-Next legacy branch commit SHA
- **kernelsu-susfs-legacy.sha**: KernelSU-Next-SUSFS legacy branch commit SHA
- **susfs-patch.version**: SUSFS patch version (e.g., "2.0.0")

## How It Works

1. The `watch_ksu.yml` workflow runs every 6 hours
2. It fetches the latest commit SHAs from upstream repositories
3. Compares them with the values stored in these files
4. If a difference is detected, it updates the file and triggers a kernel build
5. Changes are committed and pushed automatically by GitHub Actions

## Manual Trigger

To force a rebuild even without upstream changes, you can:
1. Modify any of these files manually
2. Commit and push the changes
3. Or use the workflow_dispatch option in GitHub Actions
