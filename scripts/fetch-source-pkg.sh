#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
#
# fetch-source-pkg.sh - Download a Canonical Ubuntu kernel source package
#                       from Launchpad
#
# Usage:
#   fetch-source-pkg.sh [SERIES] [SOURCE_NAME] [OUTPUT_DIR]
#
# Arguments:
#   SERIES       Ubuntu series (default: noble)
#   SOURCE_NAME  Source package name (default: linux)
#   OUTPUT_DIR   Directory to write files into (default: .)
#
# The script queries the Launchpad REST API to find the latest published
# source, then downloads all constituent files (.dsc, .orig.tar.gz,
# .debian.tar.xz, etc.) and writes a version.env summary file.
#
# Environment variables (override defaults):
#   LAUNCHPAD_API   Base URL for the Launchpad API (default: https://api.launchpad.net/1.0)

set -euo pipefail

SERIES="${1:-noble}"
SOURCE_NAME="${2:-linux}"
OUTPUT_DIR="${3:-.}"

LAUNCHPAD_API="${LAUNCHPAD_API:-https://api.launchpad.net/1.0}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
hr()   { log "$(printf '%0.s─' {1..60})"; }

# ---------------------------------------------------------------------------
# 1. Query Launchpad for the latest published source
# ---------------------------------------------------------------------------
hr
log "Querying Launchpad for latest '${SOURCE_NAME}' in Ubuntu ${SERIES}..."

API_URL="${LAUNCHPAD_API}/ubuntu/+archive/primary"
API_URL+="?ws.op=getPublishedSources"
API_URL+="&source_name=${SOURCE_NAME}"
API_URL+="&distro_series=/ubuntu/${SERIES}"
API_URL+="&status=Published"
API_URL+="&order_by_date=true"

RESPONSE=$(curl -fsSL "${API_URL}") \
  || die "Launchpad API request failed: ${API_URL}"

VERSION=$(echo "$RESPONSE"   | jq -r '.entries[0].source_package_version // empty')
SELF_LINK=$(echo "$RESPONSE" | jq -r '.entries[0].self_link // empty')

[ -n "$VERSION"   ] || die "No published source found for '${SOURCE_NAME}' in '${SERIES}'"
[ -n "$SELF_LINK" ] || die "Could not retrieve self_link for '${SOURCE_NAME}' ${VERSION}"

# Upstream version: strip Ubuntu revision suffix (e.g. "6.8.0-51.52" → "6.8.0")
UPSTREAM_VERSION=$(echo "${VERSION}" | cut -d'-' -f1)

log "Found:  ${SOURCE_NAME} ${VERSION}  (upstream: ${UPSTREAM_VERSION})"
log "Link:   ${SELF_LINK}"

# ---------------------------------------------------------------------------
# 2. Retrieve per-file download URLs
# ---------------------------------------------------------------------------
hr
log "Fetching file list..."

FILE_URLS=$(curl -fsSL "${SELF_LINK}?ws.op=sourceFileUrls" | jq -r '.[]') \
  || die "Failed to retrieve file URLs from ${SELF_LINK}"

[ -n "$FILE_URLS" ] || die "No files listed for ${SOURCE_NAME} ${VERSION}"

FILE_COUNT=$(echo "$FILE_URLS" | wc -l)
log "Files to download: ${FILE_COUNT}"

# ---------------------------------------------------------------------------
# 3. Download each file
# ---------------------------------------------------------------------------
hr
mkdir -p "${OUTPUT_DIR}"

IDX=0
while IFS= read -r url; do
  IDX=$((IDX + 1))
  FILENAME=$(basename "${url%%\?*}")   # strip any query string
  DEST="${OUTPUT_DIR}/${FILENAME}"

  log "[${IDX}/${FILE_COUNT}] ${FILENAME}"
  curl -fsSL --progress-bar -o "${DEST}" "${url}" \
    || die "Download failed: ${url}"

  SIZE=$(du -sh "${DEST}" | cut -f1)
  log "  → ${SIZE}  ${DEST}"
done <<< "$FILE_URLS"

# ---------------------------------------------------------------------------
# 4. Write version metadata
# ---------------------------------------------------------------------------
hr
VERSION_ENV="${OUTPUT_DIR}/version.env"
cat > "${VERSION_ENV}" <<EOF
SOURCE_NAME=${SOURCE_NAME}
SERIES=${SERIES}
VERSION=${VERSION}
UPSTREAM_VERSION=${UPSTREAM_VERSION}
LAUNCHPAD_SELF_LINK=${SELF_LINK}
FETCH_DATE=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
EOF

log "Metadata written to ${VERSION_ENV}"
hr
log "Download complete.  Output directory: ${OUTPUT_DIR}"
log ""
ls -lh "${OUTPUT_DIR}/"
