# pkg-linux-qcom-canonical

Mirror and CI build pipeline for Canonical Ubuntu kernel source packages.

---

## End-to-end pipeline

```
SCHEDULE: daily 04:00 UTC  ·  RUNNER: ubuntu-24.04-arm
══════════════════════════════════════════════════════════════════════════════

  Launchpad REST API
  (api.launchpad.net)
         │
         ▼
╔════════════════════════════════════════════════════════════════════════════╗
║  fetch-source-pkg.yml                                                      ║
║                                                                            ║
║  ┌──────────────────────────────────────────────────────────────────────┐ ║
║  │  Job 1 · check-version                                               │ ║
║  │                                                                      │ ║
║  │  Query Launchpad API (ws.size=300, exact source_package_name match)  │ ║
║  │  → latest version: questing X.Y.Z-A.B                               │ ║
║  │                                                                      │ ║
║  │  git ls-remote (authenticated) → tag questing-X.Y.Z-A.B exists?     │ ║
║  │                                                                      │ ║
║  │    YES ──▶  should_sync=false  ──▶  workflow exits cleanly          │ ║
║  │    NO  ──▶  should_sync=true   ──▶  continue ↓                      │ ║
║  └──────────────────────────────────────────────────────────────────────┘ ║
║                            │ should_sync=true                              ║
║                            ▼                                               ║
║  ┌──────────────────────────────────────────────────────────────────────┐ ║
║  │  Job 2 · sync                                                        │ ║
║  │                                                                      │ ║
║  │  Free disk space (~10 GB)                                            │ ║
║  │  git clone --depth=1 Launchpad git @ Ubuntu-X.Y.Z-A.B               │ ║
║  │  Verify >5000 files cloned                                           │ ║
║  │  rsync source → questing branch (orphan)                            │ ║
║  │  git commit + tag questing-X.Y.Z-A.B                                │ ║
║  │  git push branch + tag                                               │ ║
║  └──────────────────────────────────────────────────────────────────────┘ ║
║                            │ sync succeeded                                ║
║                            ▼                                               ║
║  ┌──────────────────────────────────────────────────────────────────────┐ ║
║  │  Job 3 · trigger-build                                               │ ║
║  │                                                                      │ ║
║  │  gh workflow run build-kernel.yml                                    │ ║
║  │    suite=questing  kernel_version=X.Y.Z-A.B  arch=arm64             │ ║
║  └──────────────────────────────────────────────────────────────────────┘ ║
╚════════════════════════════════════════════════════════════════════════════╝
         │
         ▼
╔════════════════════════════════════════════════════════════════════════════╗
║  build-kernel.yml                                                          ║
║                                                                            ║
║  Checkout questing branch  ──▶  kernel-src/                               ║
║  Checkout docker-pkg-build  ──▶  docker-pkg-build/                        ║
║  docker_deb_build.py --rebuild -d questing                                 ║
║                                                                            ║
║  ┌──────────────────────────────────────────────────────────────────────┐ ║
║  │  docker run --privileged ghcr.io/qualcomm-linux/pkg-builder:questing│ ║
║  │                                                                      │ ║
║  │  apt-get build-dep linux                                             │ ║
║  │  fakeroot make -f debian/rules clean            ← setup env         │ ║
║  │  fakeroot debian/rules binary-generic do_skip_checks=true           │ ║
║  └──────────────────────────────────────────────────────────────────────┘ ║
║                                                                            ║
║  Collect .deb files  ──▶  output/                                         ║
╚════════════════════════════════════════════════════════════════════════════╝
         │
         ├──────────────────────┬───────────────────────┐
         ▼                      ▼                       ▼
  ┌──────────────┐    ┌──────────────────┐    ┌──────────────────┐
  │  S3 Bucket   │    │ GitHub Artifact  │    │  GitHub Release  │
  │              │    │                  │    │                  │
  │ qli-prd-     │    │ 90-day retention │    │ questing-X.Y.Z-  │
  │ lecore-gh-   │    │ Actions → run    │    │ A.B              │
  │ artifacts    │    │ → Artifacts      │    │ Releases →       │
  │              │    │                  │    │ Assets           │
  │ self-hosted  │    │ always           │    │ permanent        │
  │ runner only  │    │ available        │    │                  │
  └──────────────┘    └──────────────────┘    └──────────────────┘
```

All jobs run on: `ubuntu-24.04-arm` (GitHub-hosted, Ubuntu 24.04 arm64)  
Target runner: `lecore-prd-u2404-arm64-xlrg-od-ephem` (self-hosted) — pending runner group access

---

## Manual build trigger flows

```
MANUAL: Actions → Build: Canonical Kernel .deb Packages → Run workflow
══════════════════════════════════════════════════════════════════════════════

  Three modes depending on kernel_version input:

  ┌─────────────────────────────────────────────────────────────────────────┐
  │  Mode A — Test / dev build  (kernel_version left empty)                 │
  │                                                                         │
  │  suite=questing  kernel_version=<empty>                                 │
  │         │                                                               │
  │         ▼                                                               │
  │  Checkout questing branch HEAD                                          │
  │  (includes any commits you pushed on top of the synced source)          │
  │         │                                                               │
  │         ▼                                                               │
  │  Build .deb packages                                                    │
  │         │                                                               │
  │         ▼                                                               │
  │  GitHub Actions artifact only (90-day)  ←  no release created          │
  └─────────────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────────────┐
  │  Mode B — Release build for latest synced version                       │
  │                                                                         │
  │  suite=questing  kernel_version=6.17.0-24.24                            │
  │         │                                                               │
  │         ▼                                                               │
  │  Validate tag questing-6.17.0-24.24 exists  (fail fast if not)         │
  │         │                                                               │
  │         ▼                                                               │
  │  Checkout tag questing-6.17.0-24.24  ← exact synced source             │
  │         │                                                               │
  │         ▼                                                               │
  │  Build .deb packages                                                    │
  │         │                                                               │
  │         ▼                                                               │
  │  GitHub Actions artifact (90-day) + GitHub Release questing-6.17.0-24.24│
  └─────────────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────────────┐
  │  Mode C — Rebuild / re-release an older synced version                  │
  │                                                                         │
  │  suite=questing  kernel_version=6.17.0-23.23                            │
  │         │                                                               │
  │         ▼                                                               │
  │  Validate tag questing-6.17.0-23.23 exists  (fail fast if not)         │
  │         │                                                               │
  │         ▼                                                               │
  │  Checkout tag questing-6.17.0-23.23  ← older synced source (not HEAD)  │
  │         │                                                               │
  │         ▼                                                               │
  │  Build .deb packages                                                    │
  │         │                                                               │
  │         ▼                                                               │
  │  GitHub Actions artifact (90-day) + GitHub Release questing-6.17.0-23.23│
  │  (existing release assets are overwritten with --clobber)               │
  └─────────────────────────────────────────────────────────────────────────┘
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
│       Tagged noble-6.8.0-114.114, noble-6.8.0-115.115, …
│
└── <suite> branch  (orphan, added on demand)
    └── Full kernel source for that suite
        e.g. questing, resolute
```

Suite branches are **orphan branches** — they share no history with `main`
and contain only the extracted kernel source tree.

---

## Upstream source

| Resource | URL pattern | Used by |
|----------|-------------|---------|
| Launchpad REST API | `https://api.launchpad.net/1.0/ubuntu/+archive/primary?ws.op=getPublishedSources&source_name=linux&distro_series=/ubuntu/<suite>&ws.size=300` | `check-version` job — queries for the latest published version number |
| Launchpad git repository | `https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/<suite>` | `sync` job — clones the complete source tree at tag `Ubuntu-<version>` |
| GitHub Releases | https://github.com/qualcomm-linux/pkg-linux-qcom-canonical/releases | `build-kernel` job — attaches built `.deb` packages |

**Example (noble suite):**
- Source packages: https://launchpad.net/ubuntu/noble/+source/linux
- Git repository: `https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/noble`

---

## Workflows

### `fetch-source-pkg.yml` — Sync sources to branch

Queries the Launchpad REST API for the latest published `linux` source
package version (exact name match), then clones the Launchpad git
repository at the corresponding tag (`Ubuntu-<version>`) to get the
complete source tree including `debian/rules`, and commits it to the
suite branch.

**Schedule**: daily at **04:00 UTC**  
**Manual trigger**: `Actions → Sync: Canonical Kernel Sources to Branch → Run workflow`  
**Runner**: `ubuntu-24.04-arm` (all three jobs)

**Inputs**:

| Input | Default | Description |
|-------|---------|-------------|
| `suite` | `questing` | Ubuntu suite to sync — one suite per run |
| `force` | `false` | Re-sync even if tag already exists |

**Jobs**:

| Job | What it does |
|-----|-------------|
| `check-version` | Queries Launchpad API (`ws.size=300`) with exact `source_package_name` filter; checks tag existence via authenticated `git ls-remote`; sets `should_sync` flag |
| `sync` | Frees disk space; `git clone --depth=1 --branch Ubuntu-<version>` from Launchpad git; verifies >5000 files; commits to suite branch; creates tag |
| `trigger-build` | Dispatches `build-kernel.yml` with `suite`, `kernel_version`, `arch=arm64`, `flavor=generic` |

**Idempotent**: if the tag for the latest version already exists, the workflow exits cleanly without downloading anything.

---

### `build-kernel.yml` — Build .deb packages

Checks out the suite branch (full kernel source tree) and builds `.deb`
packages inside the suite-matched `ghcr.io/qualcomm-linux/pkg-builder:<suite>`
container using `fakeroot debian/rules binary-<flavor>`.

**Trigger**: dispatched automatically by `fetch-source-pkg.yml`, or
manually via `Actions → Build: Canonical Kernel .deb Packages → Run workflow`.  
**Runner**: `ubuntu-24.04-arm`

**Inputs**:

| Input | Default | Description |
|-------|---------|-------------|
| `suite` | `questing` | Suite branch to build from |
| `kernel_version` | — | Version string for release asset attachment |
| `arch` | `arm64` | Target architecture |
| `flavor` | `generic` | Kernel flavour: `generic`, `lowlatency`, or `all` |
| `runner` | `ubuntu-24.04-arm` | Runner to use — see table below |

**Runner options**:

| Option | Resolves to | Status |
|--------|-------------|--------|
| `ubuntu-24.04-arm` | GitHub-hosted 2-core arm64 | **default** — used by scheduled builds |
| `self-hosted` | `runs-on: self-hosted` — any registered self-hosted runner | interim dev runner |
| `lecore-production` | `runs-on: [self-hosted, lecore-prd-u2404-arm64-xlrg-od-ephem]` | **target** — pending runner group access |

The scheduled daily sync always dispatches with `runner=ubuntu-24.04-arm`. The `lecore-production` runner enables S3 artifact upload (permanent storage) in addition to the GitHub Actions artifact fallback.

**Self-hosted runner requirements:**
- Ubuntu 24.04 arm64
- Docker installed; runner user must have access to `/var/run/docker.sock` (add user to `docker` group or `sudo chmod 666 /var/run/docker.sock`)
- ≥ 25 GB free disk space

**Build steps**:
1. Free up disk space (~10 GB)
2. Checkout suite branch → `kernel-src/`
3. Checkout `qualcomm-linux/docker-pkg-build@main` → `docker-pkg-build/`
4. Build docker image: `docker_deb_build.py --rebuild -d <suite>`
5. Run build inside `ghcr.io/qualcomm-linux/pkg-builder:<suite>` container:
   ```
   apt-get build-dep linux
   fakeroot make -f debian/rules clean
   fakeroot debian/rules binary-<flavor> do_skip_checks=true
   ```
   See [Build container notes](#build-container-notes) for why these exact invocations are used.
6. Collect `.deb` files from workspace root

**Output**:

| Location | How to access | Retention | Notes |
|----------|---------------|-----------|-------|
| **S3** | `s3://qli-prd-lecore-gh-artifacts/<org>/pkg/temp/<repo>/<run-id>/` | Permanent | Self-hosted runner only; skipped gracefully on GitHub-hosted |
| **GitHub Actions artifact** | Actions → workflow run → *Artifacts* | 90 days | Always available |
| **GitHub Release asset** | Releases → `<suite>-X.Y.Z-A.B` → Assets | Permanent | Attached when `kernel_version` is provided |

---

## Setup

### 1. Enable workflows

Go to **Actions** and enable workflows if prompted.

### 2. Configure repository variables *(optional)*

**Settings → Secrets and variables → Actions → Variables**:

| Variable | Default | Description |
|----------|---------|-------------|
| `KERNEL_SUITE` | `questing` | Default suite for scheduled runs |
| `KERNEL_SOURCE` | `linux` | Source package name |

### 3. Run the first sync

```bash
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
# → 6.8.0-114.114
```

### Clone the kernel source (buildable)

```bash
# Clones from Launchpad git at the latest Ubuntu-<version> tag
./scripts/fetch-source-pkg.sh noble linux ./kernel-src/
```

This produces a complete, buildable source tree with `debian/rules` — the same source the CI workflow uses.

### Build kernel packages

```bash
# arm64 generic (native build on arm64 host)
./scripts/build-kernel-deb.sh ./kernel-src/ arm64 generic $(nproc)
```

---

## Source and build notes

### How the sync workflow finds and clones the kernel source

The sync workflow uses two Launchpad services for different purposes:

**Step 1 — Launchpad REST API: find the latest published version**

```
GET https://api.launchpad.net/1.0/ubuntu/+archive/primary
    ?ws.op=getPublishedSources
    &source_name=linux
    &distro_series=/ubuntu/noble
    &status=Published
    &order_by_date=true
    &ws.size=300

Response (JSON):
{
  "entries": [
    {
      "source_package_name": "linux",
      "source_package_version": "6.8.0-114.114",   ← we want this
      "self_link": "https://api.launchpad.net/..."
    },
    ...
  ]
}
```

The API tells us the exact version string of the latest *officially published*
kernel. A git tag might exist before the package is published to the archive,
so the API is the authoritative source for "what is the current release".

**Step 2 — Construct the git tag**

```
VERSION = "6.8.0-114.114"
GIT_TAG = "Ubuntu-6.8.0-114.114"
```

**Step 3 — Clone from Launchpad git at that tag**

```bash
git clone --depth=1 --branch Ubuntu-6.8.0-114.114 \
  https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/noble
```

The git repository has the **complete** `debian/` directory including
`debian/rules`, `debian/scripts/`, `debian/templates/`, etc. — unlike the
source package (`.dsc`/`.orig.tar.gz`/`.diff.gz`) which ships only
`debian.master/` with `rules.d/` fragments and no `debian/rules`.

### Noble branch source tree layout

```
arch/           drivers/        fs/             kernel/
debian/         ← complete Ubuntu packaging (rules, scripts/, templates/, …)
Makefile        net/            scripts/        ...
```

### About the helper scripts

| Script | Purpose | Used by workflow? |
|--------|---------|-------------------|
| `scripts/check-version.sh` | Query latest version from Launchpad API | No (workflow has inline equivalent) |
| `scripts/fetch-source-pkg.sh` | Clone from Launchpad git at latest version tag (buildable source) | No (workflow has inline equivalent) |
| `scripts/build-kernel-deb.sh` | Build kernel `.deb` packages locally | No (workflow has inline equivalent) |

`scripts/fetch-source-pkg.sh` clones from the Launchpad git repository (same
as the CI workflow) and produces a complete, buildable source tree locally.

> **Note**: The Launchpad API `source_name=` parameter does prefix matching,
> returning all `linux-*` packages. The workflow uses `ws.size=300` to ensure
> the full result set is returned, then applies an exact `source_package_name`
> filter in jq to select only `linux` and not `linux-meta`, `linux-hwe-6.8`,
> `linux-raspi`, or other `linux-*` variants.

---

## Versioning scheme

Ubuntu kernel versions follow `X.Y.Z-A.B`:

| Component | Example | Meaning |
|-----------|---------|---------|
| `X.Y.Z` | `6.8.0` | Upstream kernel version |
| `A` | `114` | ABI number |
| `B` | `114` | Upload number |

Tags use `<suite>-X.Y.Z-A.B`, e.g. `noble-6.8.0-114.114`.

---

## Supported suites

| Suite | Codename | Status | Kernel |
|-------|----------|--------|--------|
| `noble` | Noble Numbat | 24.04 LTS — **active** | 6.8 |
| `questing` | Questing Quokka | 25.10 — **active** (daily default) | 6.17 |
| `resolute` | Resolute Ringtail | 26.04 LTS — **active** (intermittent `dtbs_install` failure observed) | 7.0 |

To add a new suite, trigger `fetch-source-pkg.yml` with the desired
`suite` input — the branch and release tag are created automatically:

```bash
gh workflow run fetch-source-pkg.yml \
  --repo qualcomm-linux/pkg-linux-qcom-canonical \
  --field suite=resolute
```

> **Note on resolute builds:** Intermittent build failures have been observed on
> resolute (26.04 LTS) during `dtbs_install`:
> ```
> install: cannot create directory .../device-tree/apm
> ```
> This error is consistent with a parallel job race condition in the kernel's
> `dtbs_install` target (`scripts/Makefile.dtbinst`) — multiple parallel jobs
> racing to create the same vendor subdirectory. The failure is non-deterministic:
> some runs succeed, others fail. It is not exclusive to resolute; it is more
> likely to surface on kernels with a large number of DTB files (such as 7.0)
> because more parallel `install -d` calls increase the probability of a collision.
> If you hit this failure, re-running the build often succeeds. For consistently
> reliable builds, use `suite=questing` or `suite=noble` until this is resolved.

---

## Build container notes

### Build environment setup (`debian/rules clean`)

Before the main kernel compilation starts, the build runs:

```bash
fakeroot make -f debian/rules clean
```

This is the **standard Ubuntu kernel build setup path** — the same entry point
Canonical's own build infrastructure uses. The `clean` target:

- Runs `debian/control` as a dependency, which generates:
  - **`debian/canonical-certs.pem`** — the X.509 certificate embedded into the
    kernel image for module signing. Required by the kernel's
    `certs/x509_certificate_list` make target. Without it the build fails
    immediately:
    ```
    No rule to make target 'debian/canonical-certs.pem',
    needed by 'certs/x509_certificate_list'
    ```
  - **`debian/control`** — the Debian package control stub
- Creates **`debian/changelog → debian.master/changelog`** symlink. The Ubuntu
  kernel source tree does not include `debian/changelog` directly — the
  changelog lives in `debian.master/changelog`. The `dh_installchangelogs`
  debhelper tool (called at the end of `binary-generic`) requires this symlink
  to exist or the build fails after 2+ hours of compilation:
  ```
  dh_installchangelogs: error: cannot open file debian/changelog
  make: *** [debian/rules.d/2-binary-arch.mk:572: binary-generic] Error 25
  ```
- Removes any stale build artifacts

**Why `fakeroot make -f debian/rules` and not `fakeroot debian/rules`?**

`fakeroot` is a shell script (`/usr/bin/fakeroot`) that execs the given command
via `/bin/sh` (dash). Dash reads the shebang of `debian/rules`
(`#!/usr/bin/make -f`) and tries to resolve the interpreter at exec time. In
the container environment this resolution fails silently, producing:

```
/usr/bin/fakeroot: 175: debian/rules: not found   (exit 127)
```

Invoking `make -f debian/rules` explicitly bypasses the shebang lookup
entirely — `make` is resolved directly from PATH and the Makefile is passed
via `-f`.

---

### Skipping the Rust config policy check (`do_skip_checks=true`)

The Ubuntu kernel build system runs a config policy check
(`debian/rules.d/4-checks.mk`) that requires `CONFIG_RUST_IS_AVAILABLE=y`
for all supported architectures including arm64. This check fails in the
`pkg-builder` container because `bindgen-0.65` is not available, so
`CONFIG_RUST_IS_AVAILABLE` is set to `-` instead of `y`:

```
check-config: CONFIG_RUST_IS_AVAILABLE changed from y to -
make: *** [debian/rules.d/4-checks.mk:15: config-prepare-check-generic] Error 1
```

Passing `do_skip_checks=true` to `fakeroot debian/rules` bypasses this policy
check. This is the standard approach for non-official builds and is equivalent
to how Canonical's own CI handles environments where optional toolchains are
unavailable.

---

## License

Scripts and workflows in this repository are licensed under the
[BSD 3-Clause License](LICENSE.txt).

The kernel source code fetched from Launchpad is subject to the
[GNU General Public License v2](https://www.kernel.org/doc/html/latest/process/license-rules.html)
and the individual licences of its components.
