#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <output_image> <boot_partition_image> <rootfs_image>" >&2
    exit 2
fi

output_image=$1
boot_partition_image=$2
rootfs_image=$3

for input_image in "$boot_partition_image" "$rootfs_image"; do
    if [ ! -s "$input_image" ]; then
        echo "Input image is missing or empty: $input_image" >&2
        exit 1
    fi
done

if ! command -v img2simg >/dev/null 2>&1; then
    echo "img2simg is required; install android-sdk-libsparse-utils" >&2
    exit 1
fi

amlimg_version=${AMLIMG_VERSION:-v0.3.1}
tool_cache=${AMLOGIC_TOOL_CACHE:-"$HOME/.cache/onecloud-image"}
amlimg="$tool_cache/AmlImg-$amlimg_version"
uboot_image="$tool_cache/eMMC.burn.img"
work_dir=$(mktemp -d)

cleanup() {
    rm -rf "$work_dir"
}
trap cleanup EXIT

mkdir -p "$tool_cache" "$(dirname "$output_image")"

download() {
    url=$1
    destination=$2
    expected_sha256=$3

    if [ -s "$destination" ] && ! echo "$expected_sha256  $destination" | sha256sum --check --status; then
        rm -f "$destination"
    fi

    if [ ! -s "$destination" ]; then
        temporary_file="$destination.tmp"
        rm -f "$temporary_file"
        wget --quiet --output-document "$temporary_file" "$url"
        echo "$expected_sha256  $temporary_file" | sha256sum --check --status
        mv "$temporary_file" "$destination"
    fi
}

download \
    "https://github.com/hzyitc/AmlImg/releases/download/$amlimg_version/AmlImg_${amlimg_version}_linux_amd64" \
    "$amlimg" \
    'b4c72e35b3ff45fb76c6ed2fd7b4b9235a73cd8558b2b432af3efd5aac78f622'
download \
    "https://github.com/hzyitc/u-boot-onecloud/releases/download/build-20221028-0940/eMMC.burn.img" \
    "$uboot_image" \
    'd33d979d23b8a607447c5af424b1e24003820e7e159e540c7f47c89d45cdc491'
chmod +x "$amlimg"

burn_dir="$work_dir/burn"
verify_dir="$work_dir/verify"

"$amlimg" unpack "$uboot_image" "$burn_dir"
img2simg "$boot_partition_image" "$burn_dir/boot.simg"
img2simg "$rootfs_image" "$burn_dir/rootfs.simg"

printf '%s\n' \
    'PARTITION:boot:sparse:boot.simg' \
    'PARTITION:rootfs:sparse:rootfs.simg' \
    >> "$burn_dir/commands.txt"

"$amlimg" pack "$output_image" "$burn_dir"
"$amlimg" unpack "$output_image" "$verify_dir"

grep -q '^PARTITION:boot:sparse:' "$verify_dir/commands.txt"
grep -q '^PARTITION:rootfs:sparse:' "$verify_dir/commands.txt"

echo "Created and verified Amlogic USB Burning Tool image: $output_image"
