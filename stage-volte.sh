#!/usr/bin/env bash
# stage-volte.sh -- build the IMS artifacts this ROM's VoLTE needs out of LG's stock firmware.
#
#   ./stage-volte.sh <firmware.kdz | stock system.image> <aosp-root>
#
# Run for you by the forge's `volte` option (post-patch, after the device patches are applied). Drop
# the KDZ in the repo and never think about this again; see IMS.md "Building the IMS stack from stock
# firmware" for the detail.
#
# A KDZ is accepted directly. LG ships firmware as a KDZ holding a DZ holding the partition images,
# which nothing in AOSP reads, so forge/tools/unpack-lg-kdz.sh drives kdztools to get the `system`
# partition out. That used to be a manual prerequisite and is now automatic. An already-unpacked
# image is still accepted, which is what a build with no network uses.
#
# Everything pulled out of the firmware lands in ONE clearly named directory, STOCK_BLOBS below.
# It is gitignored and carries a README saying what it holds and where it came from. Nothing in it
# may be committed or redistributed: it is LG's proprietary code, which is why this repo ships the
# recipe and not the ingredients. See README.md.
set -euo pipefail
SRC="${1:?usage: stage-volte.sh <firmware.kdz | stock system.image> <aosp-root>}"
AOSP="${2:?usage: stage-volte.sh <firmware.kdz | stock system.image> <aosp-root>}"
[ -f "$SRC" ]  || { echo "!! no such firmware: $SRC" >&2; exit 1; }
[ -d "$AOSP" ] || { echo "!! no such tree: $AOSP" >&2; exit 1; }
command -v debugfs >/dev/null || { echo "!! debugfs (e2fsprogs) not found; it reads the ext4 image" >&2; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
IMS="$AOSP/device/lge/msm8996-common/ims"
[ -x "$IMS/build-ims4.sh" ] || { echo "!! $IMS/build-ims4.sh missing -- device patches not applied yet?" >&2; exit 1; }

# What came out of the stock firmware, kept. Named so that what it holds is obvious from the repo
# listing, and gitignored so it cannot be committed by accident.
STOCK_BLOBS="$HERE/stock-blobs-lg-vs995"
# Both of these hang off the device repo rather than BUILD_ROOT. BUILD_ROOT is not exported into the
# build container, where only the source tree (/aosp) and the device repo (/repo) are mounted, so
# $AOSP/.. is / and unwritable. The previous fallback landed in /tmp, which is a tmpfs on the usual
# build host and is exactly where hundreds of megabytes should not go.
#
# The unpacked partition image is gigabytes, so it stays in the build area rather than beside the
# blobs.
UNPACK="$HERE/build_output/stock-kdz-unpack"
# Derived intermediates, not stock content. Cleared each run.
WORK="$HERE/build_output/tmp/stage-volte"

# 1. firmware container -> partition image
case "$SRC" in
  *.kdz|*.KDZ)
    IMG="$("$HERE/forge/tools/unpack-lg-kdz.sh" "$SRC" "$UNPACK" system)" \
      || { echo "!! could not get a system image out of $(basename "$SRC")" >&2; exit 1; } ;;
  *) IMG="$SRC" ;;
esac
[ -s "$IMG" ] || { echo "!! no usable system image at $IMG" >&2; exit 1; }

mkdir -p "$STOCK_BLOBS/lib" "$STOCK_BLOBS/bin"
rm -rf "$WORK"; mkdir -p "$WORK"

# debugfs exits 0 whether or not the file was there, so success is judged by the destination
# existing and being non-empty, never by the exit status.
pull() {  # pull <path-in-image> <dest>
  [ -s "$2" ] && return 0          # already pulled by an earlier run
  debugfs -R "dump $1 $2" "$IMG" >/dev/null 2>&1
  [ -s "$2" ] || { echo "!! not in this image: $1" >&2
                   echo "!! Wrong variant? vs995 is the Verizon V20; h918/us996 ship a different IMS build." >&2
                   exit 1; }
}

pull_either() {  # pull_either <first-choice> <second-choice> <dest>
  [ -s "$3" ] && return 0
  for src in "$1" "$2"; do
    debugfs -R "dump $src $3" "$IMG" >/dev/null 2>&1
    [ -s "$3" ] && return 0
    rm -f "$3"                      # debugfs leaves an empty file behind on a miss
  done
  echo "!! in neither $1 nor $2 of this image" >&2
  echo "!! Wrong variant? vs995 is the Verizon V20; h918/us996 ship a different IMS build." >&2
  exit 1
}

echo ">> [1/3] pulling the stock IMS pieces into $(basename "$STOCK_BLOBS")/"
pull /priv-app/Ims4/Ims4.apk                  "$STOCK_BLOBS/Ims4.apk"
pull /framework/arm64/boot-ims-common.oat     "$STOCK_BLOBS/boot-ims-common.oat"
pull /framework/arm64/boot-framework.oat      "$STOCK_BLOBS/boot-framework.oat"
pull /bin/ipsecstarter                        "$STOCK_BLOBS/bin/ipsecstarter"
pull /bin/ipsecclient                         "$STOCK_BLOBS/bin/ipsecclient"
# The 32-bit trees only: the 64-bit namesakes in /lib64 and /vendor/lib64 link-fail much later and
# in a way that does not point back here. The list lives in build-ims4.sh so the two cannot drift.
#
# Two trees, because this is a pre-Treble Nougat image: the LG SIP libraries are in /lib, while the
# Qualcomm QMI family it depends on is in /vendor/lib, which on this device is inside the system
# partition rather than a partition of its own. Eight of the nineteen are in the first and eleven in
# the second, so looking in only one finds a partial set and fails on the first miss.
for l in $(sed -n 's/^LG_LIBS="\(.*\)"/\1/p' "$IMS/build-ims4.sh"); do
  pull_either "/lib/$l.so" "/vendor/lib/$l.so" "$STOCK_BLOBS/lib/$l.so"
done

cat > "$STOCK_BLOBS/README.md" <<README
# Stock LG blobs, pulled out of the firmware

**LG's proprietary code. Not covered by this repo's licence. Never commit or redistribute any of it.**

Extracted automatically by \`stage-volte.sh\` from \`$(basename "$SRC")\`, so that the VoLTE build has
the pieces it needs without them living in the repo. This directory is gitignored.

What is here, all taken from the stock \`system\` partition:

- \`Ims4.apk\` -- LG's IMS application, the thing the ROM's VoLTE is built from
- \`boot-ims-common.oat\`, \`boot-framework.oat\` -- stock boot images, deodexed to recover the
  \`com.android.ims\` classes Android 9 deleted
- \`bin/ipsecstarter\`, \`bin/ipsecclient\` -- LG's IPsec helpers, which install the ESP security
  associations the SIP REGISTER needs
- \`lib/*.so\` -- the 32-bit LG SIP and QMI libraries, the list taken from \`LG_LIBS\` in
  \`device/lge/msm8996-common/ims/build-ims4.sh\`

The unpacked \`system.image\` itself is gigabytes, so it is left in the build area rather than copied
here: \`build_output/stock-kdz-unpack/system.image\`.

Delete this directory to pull everything again. To rebuild the reworked app as well, also delete
\`device/lge/msm8996-common/ims/Ims4-reworked.apk\` in the build tree.
README

echo ">> [2/3] deodexing the stock framework (for the real com.android.ims parcelables)"
BUILD_ROOT="${BUILD_ROOT:-$HERE/build_output}" "$HERE/forge/tools/deodex-jar.sh" \
    "$STOCK_BLOBS/boot-framework.oat" "$IMG" "$WORK/framework-smali" >/dev/null

echo ">> [3/3] reworking Ims4 for Android 17 (minutes)"
# BUILD_ROOT matters here as much as for the deodex: build-ims4.sh locates the tree's prebuilts as
# $BUILD_ROOT/src, and its own fallback counts directories up from itself, which lands on / inside
# the build container because the tree is mounted at /aosp rather than sitting under a build root.
FORGE="$HERE/forge" BUILD_ROOT="${BUILD_ROOT:-$HERE/build_output}" "$IMS/build-ims4.sh" \
    "$STOCK_BLOBS/Ims4.apk" "$STOCK_BLOBS/boot-ims-common.oat" "$IMG" "$WORK/framework-smali" \
    "$STOCK_BLOBS/lib" "$IMS/Ims4-reworked.apk" "$STOCK_BLOBS/bin"

# build-ims4.sh stages the IPsec helpers beside the apk itself (its step 7). Verify rather than
# assume: a missing one is a REGISTER that dies at "add policy is failed", hours later.
for f in Ims4-reworked.apk ipsecstarter ipsecclient; do
  [ -s "$IMS/$f" ] || { echo "!! $IMS/$f was not produced" >&2; exit 1; }
done
rm -rf "$WORK"
echo ">> volte: staged Ims4-reworked.apk, ipsecstarter, ipsecclient"
echo ">> volte: stock blobs kept in $(basename "$STOCK_BLOBS")/ (gitignored, see its README)"
