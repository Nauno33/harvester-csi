# harvester-csi — Talos-compatible build

Custom build of [harvester/harvester-csi-driver](https://github.com/harvester/harvester-csi-driver) with patches to make it work on **Talos OS**.

Images are published to `ghcr.io/nauno33/harvester-csi` and versioned to match upstream releases.

---

## The Problem

The official image `rancher/harvester-csi-driver` is based on `bci-micro`, an ultra-minimal SUSE image. On standard distributions (RKE2, K3s), the node plugin uses `nsenter` to enter the kubelet's mount namespace and execute host binaries (`blkid`, `mountpoint`, `mkfs`).

**On Talos OS, this is impossible for two reasons:**

1. Talos is an immutable, minimal OS — these binaries do not exist on the host, even with the `util-linux-tools` extension installed
2. Talos extension binaries are installed in an overlay (`/usr/local/sbin`) that is not accessible from the kubelet's mount namespace

This results in two distinct failures:

| Operation | Symptom |
|-----------|---------|
| `NodeStageVolume` (attach) | `blkid` and `mkfs.ext4` not found — volume cannot be formatted |
| `NodeUnstageVolume` (detach) | `nsenter: failed to execute mountpoint: No such file or directory` — VolumeAttachment stuck in `attached=true` |

The inability to delete volumes when a PVC is deleted violates the `Delete` reclaim policy of the StorageClass and makes dynamic PVC management unusable on Talos.

---

## Patches Applied

### Fix 1 — NodeUnstageVolume: replace nsenter call

The driver calls `nsenter → mountpoint` to check if a path is still mounted before unmounting. On Talos, this always fails.

The fix replaces this with a direct read of `/proc/mounts` via `mounter.IsLikelyNotMountPoint()` — a pure Go implementation with no dependency on any host binary.

### Fix 2 — NodeStageVolume: missing binaries in the image

The official `bci-micro` image does not include the block device management tools needed: `blkid`, `mkfs.ext4`, `mkfs.xfs`.

The fix rebases the image on `bci-base` (SLES 15.7) and installs `e2fsprogs`, `xfsprogs`, and `util-linux` directly into the container.

```
Official image (bci-micro)
├── attach : ✅ works
└── detach : ❌ nsenter → mountpoint not found on Talos

This image (bci-base + tools + patch)
├── attach : ✅ blkid and mkfs bundled in the container
└── detach : ✅ /proc/mounts read directly in Go
```

---

## Images

Images are published automatically on each upstream release:

```
ghcr.io/nauno33/harvester-csi:v0.2.4
```

The tag matches the upstream release tag exactly.

---

## Usage

### Helm

```yaml
# values.yaml
image:
  harvester:
    csiDriver:
      repository: ghcr.io/nauno33/harvester-csi
      tag: "v0.2.4"
kubeletRootDir: /var/lib/kubelet
```

```bash
helm repo add harvester https://charts.harvesterhci.io/
helm repo update

helm upgrade --install harvester-csi-driver harvester/harvester-csi-driver \
  --namespace kube-system \
  --values values.yaml
```

---

## Build Locally

Test that patches apply cleanly against a given upstream tag:

```bash
./test-patches.sh v0.2.4
```

---

## CI — Automated Builds

A GitHub Actions workflow runs daily at 6:00 AM UTC. It:

1. Fetches the latest upstream release tag
2. Skips if the image already exists in the registry
3. Clones the upstream source at that tag
4. Applies all patches from `patches/`
5. Reads the Go version required from `go.mod` and updates the Dockerfile automatically
6. Builds and pushes the image to `ghcr.io/nauno33/harvester-csi`

To trigger a build manually for a specific tag, go to **Actions → Auto-build on upstream release → Run workflow** and set `upstream_tag`.

If a patch fails to apply (upstream breaking change), the workflow opens a GitHub issue automatically.

---

## Contributing

If you maintain a similar patch or have found another incompatibility with Talos, feel free to open an issue or a PR.

---

## Acknowledgements

- [@ganawaj](https://github.com/ganawaj/harvester-csi-driver) for the initial `mountpoint` fix (branch `change-deps`)
- [harvester/harvester-csi-driver](https://github.com/harvester/harvester-csi-driver) upstream project