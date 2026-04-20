# pkg-linux-qcom-canonical

Mirror and CI build pipeline for Canonical Ubuntu kernel source packages.

---

## End-to-end pipeline

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DAILY (04:00 UTC)                            │
│                                                                     │
│  Launchpad                                                          │
│  api.launchpad.net  ──► fetch-source-pkg.yml                        │
│                              │                                      │
│                    ┌─────────▼──────────┐                           │
│                    │  Job 1: check-version                          │
│                    │  curl Launchpad API │                           │
│                    │  → noble 6.8.0-51.52│                          │
│                    │  tag exists? YES→skip                          │
│                    │             NO ↓   │                           │
│                    └─────────┬──────────┘                           │
│                              │                                      │
│                    ┌─────────▼──────────┐                           │
│                    │  Job 2: sync        │                          │
│                    │  download .dsc      │                          │
│                    │  + .orig.tar.gz     │                          │
│                    │  + .debian.tar.xz   │                          │
│                    │  dpkg-source -x     │                          │
│                    │  → full source tree │                          │
│                    │  commit to noble    │                          │
│                    │  branch + tag       │                          │
│                    └─────────┬──────────┘                           │
│                              │                                      │
│                    ┌─────────▼──────────┐                           │
│                    │  Job 3: trigger     │                          │
│                    │  gh workflow run    │                          │
│                    │  build-kernel.yml   │                          │
│                    └─────────┬──────────┘                           │
│                              │                                      │
│                    ┌─────────▼──────────┐                           │
│                    │  build-kernel.yml   │                          │
│                    │  checkout noble     │                          │
│                    │  branch             │                          │
│                    │  apt-get build-dep  │                          │
│                    │  fakeroot           │                          │
│                    │  debian/rules       │                          │
│                    │  binary-generic     │                          │
│                    └─────────┬──────────┘                           │
│                              │                                      │
│               ┌──────────────┴──────────────┐                       │
│               ▼                             ▼                       │
│   GitHub Actions Artifact         GitHub Release Asset              │
│   (90-day retention)              noble-6.8.0-51.52                 │
│   Actions → run → Artifacts       Releases page → Assets            │
│                                   (permanent)                       │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Repository branch layout

```
pkg-linux-qcom-canonical
│
├── main branch
│   ├── .github/workflows/
│   │   ├── fetch-source-pkg.yml   ← sync Launchpad sources → suite branch
│   │   └── build-kernel.yml       ← build .deb packages from suite branch
│   ├── scripts/
│   │   ├── check-version.sh       ← query latest version from Launchpad
│   │   ├── fetch-source-pkg.sh    ← download source package files
│   │   └── build-kernel-deb.sh    ← build kernel .deb packages locally
│   └── README.md
│
├── noble branch  (orphan)
│   └── Full Ubuntu Noble 24.04 LTS kernel source tree
│       One commit per Canonical upload
│       Tagged noble-6.8.0-51.52, noble-6.8.0-52.53, …
│
└── <suite> branch  (orphan, added on demand)
    └── Full kernel source for that suite
        e.g. questing, resolute
```

Suite branches are **orphan branches** — they share no history with `main`
and contain only the extracted kernel source tree.

---

## Upstream source

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
result to the corresponding suite branch.

**Schedule**: daily at **04:00 UTC**  
**Manual trigger**: `Actions → Sync: Canonical Kernel Sources to Branch → Run workflow`

**Inputs**:

| Input | Default | Description |
|-------|---------|-------------|
| `suite` | `noble` | Ubuntu suite to sync — one suite per run |
| `force` | `false` | Re-sync even if tag already exists |

**Idempotent**: checks for the tag before downloading anything.  
**Auto-triggers**: dispatches `build-kernel.yml` on each new sync.

---

### `build-kernel.yml` — Build .deb packages

Checks out the suite branch (full kernel source tree) and builds `.deb`
packages using the Ubuntu `debian/rules` build system on the native arm64
self-hosted runner.

**Trigger**: dispatched automatically by `fetch-source-pkg.yml`, or
manually via `Actions → Build: Canonical Kernel .deb Packages → Run workflow`.

**Inputs**:

| Input | Default | Description |
|-------|---------|-------------|
| `suite` | `noble` | Suite branch to build from |
| `kernel_version` | — | Version string for release asset attachment |
| `arch` | `arm64` | Target architecture |
| `flavor` | `generic` | Kernel flavour: `generic`, `lowlatency`, or `all` |

**Output — two locations**:

| Location | How to access | Retention |
|----------|---------------|-----------|
| **GitHub Actions artifact** | Actions → workflow run → *Artifacts* | 90 days |
| **GitHub Release asset** | Releases → `noble-6.8.0-X.Y` → Assets | Permanent |

**Runner**: `lecore-prd-u2404-arm64-xlrg-od-ephem`  
Native arm64 build — no cross-compilation.

---

## Setup

### 1. Enable workflows

Go to **Actions** and enable workflows if prompted.

### 2. Configure repository variables *(optional)*

**Settings → Secrets and variables → Actions → Variables**:

| Variable | Default | Description |
|----------|---------|-------------|
| `KERNEL_SUITE` | `noble` | Default suite for scheduled runs |
| `KERNEL_SOURCE` | `linux` | Source package name |

### 3. Run the first sync

```bash
# Sync noble sources to the noble branch (creates it if it doesn't exist)
gh workflow run fetch-source-pkg.yml \
  --repo qualcomm-linux/pkg-linux-qcom-canonical \
  --field suite=noble
```

---

## Local usage

All scripts run on Ubuntu 24.04 arm64.

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
that is committed to the suite branch.

---

## Versioning scheme

Ubuntu kernel versions follow `X.Y.Z-A.B`:

| Component | Example | Meaning |
|-----------|---------|---------|
| `X.Y.Z` | `6.8.0` | Upstream kernel version |
| `A` | `51` | ABI number |
| `B` | `52` | Upload number |

Tags use `<suite>-X.Y.Z-A.B`, e.g. `noble-6.8.0-51.52`.

---

## Supported suites

| Suite | Codename | Status | Kernel |
|-------|----------|--------|--------|
| `noble` | Noble Numbat | 24.04 LTS — **active** | 6.8 |
| `questing` | Questing Quokka | 25.04 — add when available | TBD |
| `resolute` | Resolute Ringtail | 25.10 — add when available | TBD |

To add a new suite, trigger `fetch-source-pkg.yml` with the desired
`suite` input — the branch and release tag are created automatically:

```bash
gh workflow run fetch-source-pkg.yml \
  --repo qualcomm-linux/pkg-linux-qcom-canonical \
  --field suite=questing
```

---

## License

Scripts and workflows in this repository are licensed under the
[BSD 3-Clause License](LICENSE.txt).

The kernel source code fetched from Launchpad is subject to the
[GNU General Public License v2](https://www.kernel.org/doc/html/latest/process/license-rules.html)
and the individual licences of its components.
