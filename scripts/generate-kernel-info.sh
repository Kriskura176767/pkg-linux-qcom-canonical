#!/usr/bin/env bash
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

usage() {
    echo "Usage: $0 <source-dir> <packages-dir> <output-file>" >&2
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

write_field() {
    local name=$1
    local value=$2

    [[ -n "$value" ]] || die "${name} is empty"
    [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] \
        || die "${name} contains a newline"
    printf '%s: %s\n' "$name" "$value"
}

[[ $# -eq 3 ]] || { usage; exit 2; }

SOURCE_DIR=$1
PACKAGES_DIR=$2
OUTPUT_FILE=$3

: "${KERNEL_VARIANT:?KERNEL_VARIANT is required}"
: "${KERNEL_FLAVOR:?KERNEL_FLAVOR is required}"
: "${KERNEL_SOURCE_REPOSITORY:?KERNEL_SOURCE_REPOSITORY is required}"
: "${KERNEL_SOURCE_REF:?KERNEL_SOURCE_REF is required}"
: "${SUITE:?SUITE is required}"
: "${KERNEL_BUILD_ID:?KERNEL_BUILD_ID is required}"

git -C "$SOURCE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "kernel source checkout not found: $SOURCE_DIR"
[[ -d "$PACKAGES_DIR" ]] || die "packages directory not found: $PACKAGES_DIR"

mapfile -d '' PACKAGE_FILES < <(find "$PACKAGES_DIR" -maxdepth 1 -type f -name '*.deb' -print0)
MATCHING_PACKAGES=()
for package_file in "${PACKAGE_FILES[@]}"; do
    package_name=$(dpkg-deb --field "$package_file" Package)
    if [[ "$package_name" == linux-image-*-"$KERNEL_FLAVOR" ]]; then
        MATCHING_PACKAGES+=("$package_file")
    fi
done

if (( ${#MATCHING_PACKAGES[@]} != 1 )); then
    die "expected exactly one linux-image package for flavor '${KERNEL_FLAVOR}' in ${PACKAGES_DIR}, found ${#MATCHING_PACKAGES[@]}"
fi

PACKAGE_FILE=${MATCHING_PACKAGES[0]}
KERNEL_PACKAGE_NAME=$(dpkg-deb --field "$PACKAGE_FILE" Package)
KERNEL_PACKAGE_VERSION=$(dpkg-deb --field "$PACKAGE_FILE" Version)
KERNEL_PACKAGE_ARCHITECTURE=$(dpkg-deb --field "$PACKAGE_FILE" Architecture)
KERNEL_RELEASE=${KERNEL_PACKAGE_NAME#linux-image-}
KERNEL_SOURCE_SHA=$(git -C "$SOURCE_DIR" rev-parse HEAD)
KERNEL_BUILD_TIMESTAMP_UTC=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

dpkg-deb --contents "$PACKAGE_FILE" \
    | awk -v expected="./boot/vmlinuz-${KERNEL_RELEASE}" \
        '$NF == expected { found = 1 } END { exit !found }' \
    || die "${PACKAGE_FILE} does not contain /boot/vmlinuz-${KERNEL_RELEASE}"

mkdir -p "$(dirname "$OUTPUT_FILE")"
{
    write_field KERNEL_INFO_FORMAT 1
    write_field KERNEL_VARIANT "$KERNEL_VARIANT"
    write_field KERNEL_FLAVOR "$KERNEL_FLAVOR"
    write_field KERNEL_SOURCE_REPOSITORY "$KERNEL_SOURCE_REPOSITORY"
    write_field KERNEL_SOURCE_REF "$KERNEL_SOURCE_REF"
    write_field KERNEL_SOURCE_SHA "$KERNEL_SOURCE_SHA"
    write_field KERNEL_PACKAGING_REPOSITORY "$KERNEL_SOURCE_REPOSITORY"
    write_field KERNEL_PACKAGING_REF "$KERNEL_SOURCE_REF"
    write_field KERNEL_PACKAGING_SHA "$KERNEL_SOURCE_SHA"
    write_field SUITE "$SUITE"
    write_field KERNEL_RELEASE "$KERNEL_RELEASE"
    write_field KERNEL_PACKAGE_NAME "$KERNEL_PACKAGE_NAME"
    write_field KERNEL_PACKAGE_VERSION "$KERNEL_PACKAGE_VERSION"
    write_field KERNEL_PACKAGE_ARCHITECTURE "$KERNEL_PACKAGE_ARCHITECTURE"
    write_field KERNEL_BUILD_ID "$KERNEL_BUILD_ID"
    write_field KERNEL_BUILD_TIMESTAMP_UTC "$KERNEL_BUILD_TIMESTAMP_UTC"
} > "$OUTPUT_FILE"

chmod 0644 "$OUTPUT_FILE"
echo "Generated ${OUTPUT_FILE} from $(basename "$PACKAGE_FILE")"
