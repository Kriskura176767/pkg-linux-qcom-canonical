# pkg-linux-qcom-canonical

Mirror and CI build pipeline for Canonical Ubuntu kernel source packages.

---

## End-to-end pipeline

```
SCHEDULE: daily 04:00 UTC  ·  RUNNER: ubuntu-24.04-arm
══════════════════════════════════════════════════════════════════════════════

  Ubuntu-qcom Launchpad repository
  (git.launchpad.net/~carmel-team/ubuntu/+source/linux/+git/resolute)
         │
         ▼  git ls-remote --tags → latest Ubuntu-qcom-* tag → version X.Y.Z-A.B
╔════════════════════════════════════════════════════════════════════════════╗
║  fetch-source-pkg.yml                                                      ║
║                                                                            ║
║  ┌──────────────────────────────────────────────────────────────────────┐ ║
║  │  Job 1 · check-version                                               │ ║
║  │                                                                      │ ║
║  │  git ls-remote resolute-qcom repo → latest Ubuntu-qcom-* tag        │ ║
║  │  → latest version: resolute-qcom X.Y.Z-A.B                          │ ║
║  │                                                                      │ ║
║  │  git ls-remote (authenticated) → tag resolute-qcom-X.Y.Z-A.B exists?│ ║
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
║  │  git clone --depth=1 resolute-qcom repo @ Ubuntu-qcom-X.Y.Z-A.B     │ ║
║  │  Verify >5000 files cloned                                           │ ║
║  │  rsync source → resolute-qcom branch (orphan)                       │ ║
║  │  git commit + tag resolute-qcom-X.Y.Z-A.B                           │ ║
║  │  git push branch + tag                                               │ ║
║  └──────────────────────────────────────────────────────────────────────┘ ║
║                            │ sync succeeded                                ║
║                            ▼                                               ║
║  ┌──────────────────────────────────────────────────────────────────────┐ ║
║  │  Job 3 · trigger-build                                               │ ║
║  │                                                                      │ ║
║  │  gh workflow run build-kernel.yml                                    │ ║
║  │    suite=resolute-qcom  kernel_version=X.Y.Z-A.B  arch=arm64        │ ║
║  └──────────────────────────────────────────────────────────────────────┘ ║
╚════════════════════════════════════════════════════════════════════════════╝
         │
         ▼
╔════════════════════════════════════════════════════════════════════════════╗
║  build-kernel.yml                                                          ║
║                                                                            ║
║  Checkout resolute-qcom branch  ──▶  kernel-src/                          ║
║  Checkout docker-pkg-build      ──▶  docker-pkg-build/                    ║
║  docker_deb_build.py --rebuild -d resolute   ← base suite derived         ║
║                                                                            ║
║  ┌──────────────────────────────────────────────────────────────────────┐ ║
║  │  docker run --privileged ghcr.io/qualcomm-linux/pkg-builder:resolute│ ║
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
  │ qli-prd-     │    │ 90-day retention │    │ resolute-qcom-   │
  │ lecore-gh-   │    │ Actions → run    │    │ X.Y.Z-A.B        │
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
  │  suite=resolute-qcom  kernel_version=<empty>                            │
  │         │                                                               │
  │         ▼                                                               │
  │  Checkout resolute-qcom branch HEAD                                     │
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
  │  suite=resolute-qcom  kernel_version=7.0.0-5.5                          │
  │         │                                                               │
  │         ▼                                                               │
  │  Validate tag resolute-qcom-7.0.0-5.5 exists  (fail fast if not)       │
  │         │                                                               │
  │         ▼                                                               │
  │  Checkout tag resolute-qcom-7.0.0-5.5  ← exact synced source           │
  │         │                                                               │
  │         ▼                                                               │
  │  Build .deb packages                                                    │
  │         │                                                               │
  │         ▼                                                               │
  │  GitHub Actions artifact (90-day) + GitHub Release resolute-qcom-7.0.0-5.5│
  └─────────────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────────────┐
  │  Mode C — Rebuild / re-release an older synced version                  │
  │                                                                         │
  │  suite=resolute-qcom  kernel_version=7.0.0-4.4                          │
  │         │                                                               │
  │         ▼                                                               │
  │  Validate tag resolute-qcom-7.0.0-4.4 exists  (fail fast if not)       │
  │         │                                                               │
  │         ▼                                                               │
  │  Checkout tag resolute-qcom-7.0.0-4.4  ← older synced source (not HEAD)│
  │         │                                                               │
  │         ▼                                                               │
  │  Build .deb packages                                                    │
  │         │                                                               │
  │         ▼                                                               │
  │  GitHub Actions artifact (90-day) + GitHub Release resolute-qcom-7.0.0-4.4│
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
│   │   ├── fetch-source-pkg.yml   ← sync Launchpad sources → branch
│   │   └── build-kernel.yml       ← build .deb packages from branch
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
├── resolute-qcom branch  (orphan)
│   └── Full resolute-qcom kernel source tree (daily default)
│       One commit per upstream tag
│       Tagged resolute-qcom-7.0.0-X.X, …
│
└── <suite> branch  (orphan, added on demand)
    └── Full kernel source for that suite
        e.g. questing, resolute
```

Suite branches are **orphan branches** — they share no history with `main`
and contain only the extracted kernel source tree.

---

## Resolute Qcom kernel source

The daily scheduled build syncs from a custom resolute kernel repository
maintained separately from the official Ubuntu kernel tree. This repository
is referred to as the **resolute-qcom** source.

| Resource | URL |
|----------|-----|
| Git repository | `https://git.launchpad.net/~carmel-team/ubuntu/+source/linux/+git/resolute` |

**How version discovery works for resolute-qcom:**

Unlike the official Ubuntu kernel path (which queries the Launchpad REST API
for the latest published source package), the resolute-qcom path queries the
git repository directly:

```bash
git ls-remote --tags \
  https://git.launchpad.net/~carmel-team/ubuntu/+source/linux/+git/resolute \
  'refs/tags/Ubuntu-*'
```

Tags are sorted with `sort -V` (version sort) and the latest `Ubuntu-qcom-*` tag
is selected. The version is extracted from the tag name:

```
Ubuntu-qcom-7.0.0-1003.3  →  version: 7.0.0-1003.3
                           →  branch tag: resolute-qcom-7.0.0-1003.3
```

The Launchpad REST API is **not used** for resolute-qcom — the git tags are
the authoritative source of version information for this repository.

**Branch and tag naming:**

| Item | Pattern | Example |
|------|---------|---------|
| Upstream git tag | `Ubuntu-qcom-X.Y.Z-A.B` | `Ubuntu-qcom-7.0.0-1003.3` |
| Branch in this repo | `resolute-qcom` | `resolute-qcom` |
| Tag in this repo | `resolute-qcom-X.Y.Z-A.B` | `resolute-qcom-7.0.0-1003.3` |
| Docker container | `pkg-builder:resolute` | base suite derived automatically |

---

## Upstream source

| Resource | URL pattern | Used by |
|----------|-------------|---------|
| Launchpad REST API | `https://api.launchpad.net/1.0/ubuntu/+archive/primary?ws.op=getPublishedSources&source_name=linux&distro_series=/ubuntu/<suite>&ws.size=300` | `check-version` job — queries for the latest published version number (official suites only; bypassed for resolute-qcom) |
| Launchpad git repository | `https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/<suite>` | `sync` job — clones the complete source tree at tag `Ubuntu-<version>` (official suites only) |
| Resolute Qcom git repository | `https://git.launchpad.net/~carmel-team/ubuntu/+source/linux/+git/resolute` | `sync` job — daily default; version discovered via `git ls-remote` |
| GitHub Releases | https://github.com/qualcomm-linux/pkg-linux-qcom-canonical/releases | `build-kernel` job — attaches built `.deb` packages |

**Example (noble suite — official upstream):**
- Source packages: https://launchpad.net/ubuntu/noble/+source/linux
- Git repository: `https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/noble`

---

## Workflows

### `fetch-source-pkg.yml` — Sync sources to branch

Queries the git repository for the latest `Ubuntu-*` tag (resolute-qcom, daily
default) or the Launchpad REST API (official suites), then clones the source
tree at the corresponding tag to get the complete source including `debian/rules`,
and commits it to the branch.

**Schedule**: daily at **04:00 UTC**  
**Manual trigger**: `Actions → Sync: Canonical Kernel Sources to Branch → Run workflow`  
**Runner**: `ubuntu-24.04-arm` (all three jobs)

**Inputs**:

| Input | Default | Description |
|-------|---------|-------------|
| `suite` | `resolute-qcom` | Branch name to sync into (e.g. `noble`, `questing`, `resolute`, `resolute-qcom`). Becomes the branch and tag prefix in this repo. The base suite (`resolute`) is derived automatically from the first component for Docker container selection. |
| `force` | `false` | Re-sync even if tag already exists |
| `custom_git_url` | `https://git.launchpad.net/~carmel-team/ubuntu/+source/linux/+git/resolute` | Custom Launchpad git URL to clone from. Defaults to the Ubuntu-qcom Launchpad repository. When set, the Launchpad REST API is bypassed — the latest `Ubuntu-qcom-*` tag is discovered directly from the repo via `git ls-remote`. |

**Jobs**:

| Job | What it does |
|-----|-------------|
| `check-version` | For resolute-qcom: queries tags via `git ls-remote` on the custom repo. For official suites: queries Launchpad API (`ws.size=300`). Checks tag existence; sets `should_sync` flag. |
| `sync` | Frees disk space; `git clone --depth=1 --branch Ubuntu-<version>` from the resolved git URL; verifies >5000 files; commits to branch; creates tag |
| `trigger-build` | Dispatches `build-kernel.yml` with `suite`, `kernel_version`, `arch=arm64`, `flavor=generic` |

**Idempotent**: if the tag for the latest version already exists, the workflow exits cleanly without downloading anything.

---

### `build-kernel.yml` — Build .deb packages

Checks out the branch (full kernel source tree) and builds `.deb`
packages inside the base-suite-matched `ghcr.io/qualcomm-linux/pkg-builder:<base_suite>`
container using `fakeroot debian/rules binary-<flavor>`.

**Trigger**: dispatched automatically by `fetch-source-pkg.yml`, or
manually via `Actions → Build: Canonical Kernel .deb Packages → Run workflow`.  
**Runner**: `ubuntu-24.04-arm`

**Inputs**:

| Input | Default | Description |
|-------|---------|-------------|
| `suite` | `resolute-qcom` | Branch to build from (e.g. `noble`, `questing`, `resolute`, `resolute-qcom`). The base suite is derived automatically for Docker container selection. |
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
2. Checkout branch → `kernel-src/`
3. Checkout `qualcomm-linux/docker-pkg-build@main` → `docker-pkg-build/`
4. Derive `BASE_SUITE` from branch name (e.g. `resolute-qcom` → `resolute`)
5. Build docker image: `docker_deb_build.py --rebuild -d <base_suite>`
6. Run build inside `ghcr.io/qualcomm-linux/pkg-builder:<base_suite>` container:
   ```
   apt-get build-dep linux
   fakeroot make -f debian/rules clean
   fakeroot debian/rules binary-<flavor> do_skip_checks=true
   ```
   See [Build container notes](#build-container-notes) for why these exact invocations are used.
7. Collect `.deb` files from workspace root

**Output**:

| Location | How to access | Retention | Notes |
|----------|---------------|-----------|-------|
| **S3** | `s3://qli-prd-lecore-gh-artifacts/<org>/pkg/temp/<repo>/<run-id>/` | Permanent | Self-hosted runner only; skipped gracefully on GitHub-hosted |
| **GitHub Actions artifact** | Actions → workflow run → *Artifacts* | 90 days | Always available |
| **GitHub Release asset** | Releases → `<branch>-X.Y.Z-A.B` → Assets | Permanent | Attached when `kernel_version` is provided |

---

## Setup

### 1. Enable workflows

Go to **Actions** and enable workflows if prompted.

### 2. Configure repository variables *(optional)*

**Settings → Secrets and variables → Actions → Variables**:

| Variable | Default | Description |
|----------|---------|-------------|
| `KERNEL_SUITE` | `resolute-qcom` | Default branch name for scheduled runs |
| `KERNEL_SOURCE` | `linux` | Source package name |
| `KERNEL_CUSTOM_GIT_URL` | `https://git.launchpad.net/~carmel-team/ubuntu/+source/linux/+git/resolute` | Default custom git URL for scheduled runs |

### 3. Run the first sync

```bash
gh workflow run fetch-source-pkg.yml \
  --repo qualcomm-linux/pkg-linux-qcom-canonical \
  --field suite=resolute-qcom
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

The sync workflow supports two paths depending on whether a custom git URL is configured:

**Path A — Resolute Qcom (daily default): version from git tags**

```bash
git ls-remote --tags \
  https://git.launchpad.net/~carmel-team/ubuntu/+source/linux/+git/resolute \
  'refs/tags/Ubuntu-*'
# → sort -V | tail -1 → Ubuntu-7.0.0-5.5
# → VERSION=7.0.0-5.5
```

The latest `Ubuntu-*` tag in the custom repo is the authoritative version source.
The Launchpad REST API is not used.

**Path B — Official suites (noble, questing, resolute): version from Launchpad REST API**

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

**Clone step (both paths):**

```bash
git clone --depth=1 --branch Ubuntu-<version> <git_url>
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

Tags use `<branch>-X.Y.Z-A.B`, e.g. `resolute-qcom-7.0.0-1003.3`.

---

## Supported suites

Official Ubuntu suites supported by this pipeline:

| Suite | Codename | Ubuntu | Kernel |
|-------|----------|--------|--------|
| `noble` | Noble Numbat | 24.04 LTS — **active** | 6.8 |
| `questing` | Questing Quokka | 25.10 — **active** | 6.17 |
| `resolute` | Resolute Ringtail | 26.04 LTS — **active** | 7.0 |

To sync an official suite, trigger `fetch-source-pkg.yml` with the desired
`suite` input — the branch and release tag are created automatically:

```bash
gh workflow run fetch-source-pkg.yml \
  --repo qualcomm-linux/pkg-linux-qcom-canonical \
  --field suite=resolute
```

## Custom branches

In addition to official Ubuntu suites, this repo supports custom branches
that track non-upstream kernel repositories. Custom branches use a
`<base_suite>-<suffix>` naming convention so the base suite can be derived
automatically for Docker container selection.

| Branch | Base suite | Source | Daily default |
|--------|-----------|--------|---------------|
| `resolute-qcom` | `resolute` | `https://git.launchpad.net/~carmel-team/ubuntu/+source/linux/+git/resolute` | ✅ yes |

Custom branches are **not** Ubuntu suite names — they are branch names in
this repository that happen to be based on a particular Ubuntu suite's kernel.
The `suite` input in both workflows accepts either an official suite name or
a custom branch name.

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
