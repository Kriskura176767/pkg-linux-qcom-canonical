# pkg-linux-qcom-canonical

Mirror and CI build pipeline for Canonical Ubuntu kernel source packages.

---

## Repository layout

```
main branch (this branch)
├── .github/workflows/
│   ├── fetch-source-pkg.yml   ← sync Launchpad sources → series branch
│   ├── build-kernel.yml       ← build .deb packages from series branch
│   └── mirror-git.yml         ← optional: full git history mirror
├── scripts/
│   ├── check-version.sh       ← query latest version from Launchpad
│   ├── fetch-source-pkg.sh    ← download source package files
│   └── build-kernel-deb.sh    ← build kernel .deb packages locally
└── README.md

noble branch  ← Ubuntu Noble (24.04 LTS) kernel source tree, one commit per upload
<series>      ← additional series added on demand (questing, resolute, …)
```

Series branches are **orphan branches** — they share no history with `main`
and contain only the extracted kernel source tree.

Each upload is tagged `<series>-<version>`, e.g. `noble-6.8.0-51.52`.

---

## Upstream sources

| Resource | URL |
|----------|-----|
| Launchpad source packages | https://launchpad.net/ubuntu/noble/+source/linux |
| Launchpad git repository | `https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/noble` |
| Launchpad REST API | https://api.launchpad.net/1.0/ |
| GitHub Releases | https://github.com/qualcomm-linux/pkg-linux-qcom-canonical/releases |

---

## Workflows

### `fetch-source-pkg.yml` — Sync sources to branch

Queries the Launchpad REST API for the latest published `linux` source
package, downloads the `.dsc` + tarballs, extracts the full source tree
with `dpkg-source -x` (applying all Ubuntu patches), and commits the
result to the corresponding series branch.

```
Launchpad archive
  linux_6.8.0.orig.tar.gz          ─┐
  linux_6.8.0-51.52.debian.tar.xz   ├─ dpkg-source -x ──► noble branch commit
  linux_6.8.0-51.52.dsc            ─┘                      tagged noble-6.8.0-51.52
```

**Schedule**: daily at **04:00 UTC**  
**Manual trigger**: `Actions → Sync: Canonical Kernel Sources to Branch → Run workflow`

**Inputs** (manual dispatch):

| Input | Default | Description |
|-------|---------|-------------|
| `series` | `noble` | Ubuntu series to sync |
| `force` | `false` | Re-sync even if tag already exists |

**Idempotent**: checks for the tag before downloading anything.  
**Auto-triggers**: dispatches `build-kernel.yml` on each new sync.

---

### `build-kernel.yml` — Build .deb packages

Checks out the series branch (which contains the full kernel source tree)
and builds `.deb` packages using the Ubuntu `debian/rules` build system.

**Trigger**: dispatched automatically by `fetch-source-pkg.yml`, or
manually via `Actions → Build: Canonical Kernel .deb Packages → Run workflow`.

**Inputs** (manual dispatch):

| Input | Default | Description |
|-------|---------|-------------|
| `series` | `noble` | Series branch to build from |
| `kernel_version` | — | Version string for artifact naming |
| `arch` | `arm64` | Target architecture: `arm64` or `amd64` |
| `flavor` | `generic` | Kernel flavour: `generic`, `lowlatency`, or `all` |

**Output — two locations**:

| Location | How to access | Retention |
|----------|---------------|-----------|
| **GitHub Actions artifact** | Actions → workflow run → *Artifacts* section at the bottom | 90 days |
| **GitHub Release asset** | Releases page → tag `noble-6.8.0-X.Y` → Assets | Permanent |

The `.deb` files are attached to the release tag automatically when `kernel_version` is provided (which `fetch-source-pkg.yml` always does).

**Resource requirements**:

| Resource | Requirement |
|----------|-------------|
| Disk space | ~20 GB (runner is cleaned before build) |
| Wall-clock | ~60–90 min (generic, 2 vCPU GitHub runner) |
| RAM | ~4 GB |

> **Runner**: `lecore-prd-u2404-arm64-xlrg-od-ephem` (Ubuntu 24.04 arm64, native build — no cross-compilation).

---

### `mirror-git.yml` — Full git history mirror *(optional)*

Mirrors the complete Canonical Ubuntu kernel git tree from Launchpad to a
separate GitHub repository, preserving every intermediate commit made by
the Ubuntu kernel team between uploads.

This is complementary to `fetch-source-pkg.yml`: the series branch gives
you one clean snapshot per upload; the git mirror gives you the full
development history.

**Schedule**: daily at **03:00 UTC**  
**Required secret**: `MIRROR_PUSH_TOKEN` (PAT with `repo` scope on the target repo)  
**Required variable**: `MIRROR_TARGET_REPO` (e.g. `qualcomm-linux/linux-noble`)

---

## Setup

### 1. Enable workflows

Go to **Actions** and enable workflows if prompted.

### 2. Configure repository variables *(optional)*

**Settings → Secrets and variables → Actions → Variables**:

| Variable | Default | Description |
|----------|---------|-------------|
| `KERNEL_SERIES` | `noble` | Default series for scheduled runs |
| `KERNEL_SOURCE` | `linux` | Source package name |
| `MIRROR_TARGET_REPO` | `qualcomm-linux/linux-noble` | Target repo for git mirror |

### 3. Configure secrets *(only needed for git mirror)*

**Settings → Secrets and variables → Actions → Secrets**:

| Secret | Description |
|--------|-------------|
| `MIRROR_PUSH_TOKEN` | GitHub PAT with `repo` scope on `MIRROR_TARGET_REPO` |

### 4. Run the first sync

```bash
# Sync noble sources to the noble branch (creates it if it doesn't exist)
gh workflow run fetch-source-pkg.yml \
  --repo qualcomm-linux/pkg-linux-qcom-canonical \
  --field series=noble

# Or trigger a build manually from an existing series branch
gh workflow run build-kernel.yml \
  --repo qualcomm-linux/pkg-linux-qcom-canonical \
  --field series=noble \
  --field arch=arm64 \
  --field flavor=generic
```

---

## Local usage

All scripts run on Ubuntu 22.04 / 24.04.

### Check the latest version

```bash
./scripts/check-version.sh noble linux
# → 6.8.0-51.52
```

### Download the source package

```bash
./scripts/fetch-source-pkg.sh noble linux ./source-pkg/
```

### Build kernel packages

```bash
# arm64 generic (native build on arm64 host)
./scripts/build-kernel-deb.sh ./kernel-src/ arm64 generic $(nproc)
```

---

## Source package anatomy

The Ubuntu kernel source package is a standard Debian 3.0 (quilt) source package:

| File | Size | Description |
|------|------|-------------|
| `linux_X.Y.Z-A.B.dsc` | ~10 KB | Source descriptor with SHA256 checksums |
| `linux_X.Y.Z.orig.tar.gz` | ~200 MB | Pristine upstream kernel tarball |
| `linux_X.Y.Z-A.B.debian.tar.xz` | ~5 MB | Ubuntu packaging overlay + patches |

`dpkg-source -x` applies all patches and produces the full source tree
that is committed to the series branch.

## Versioning scheme

Ubuntu kernel versions follow `X.Y.Z-A.B`:

| Component | Example | Meaning |
|-----------|---------|---------|
| `X.Y.Z` | `6.8.0` | Upstream kernel version |
| `A` | `51` | ABI number |
| `B` | `52` | Upload number |

Tags in this repository use `<series>-X.Y.Z-A.B`, e.g. `noble-6.8.0-51.52`.

---

## Supported series

| Series | Codename | Status | Kernel |
|--------|----------|--------|--------|
| `noble` | Noble Numbat | 24.04 LTS — **active** | 6.8 |
| `questing` | Questing Quokka | 25.04 — add when available | TBD |
| `resolute` | Resolute Ringtail | 25.10 — add when available | TBD |

To add a new series, trigger `fetch-source-pkg.yml` with the desired
`series` input — the branch and release tag are created automatically:

```bash
gh workflow run fetch-source-pkg.yml \
  --repo qualcomm-linux/pkg-linux-qcom-canonical \
  --field series=questing
```

---

## License

Scripts and workflows in this repository are licensed under the
[BSD 3-Clause License](LICENSE.txt).

The kernel source code fetched from Launchpad is subject to the
[GNU General Public License v2](https://www.kernel.org/doc/html/latest/process/license-rules.html)
and the individual licences of its components.
