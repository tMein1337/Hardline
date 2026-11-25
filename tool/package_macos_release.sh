#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Mein1337
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Stages a complete, legally shippable macOS release and wraps it in a .dmg.
# The macOS counterpart of tool/package_windows_release.ps1, with the same
# checks and the same documents beside the application:
#
#   Hardline.app            the application bundle
#   LICENSE                 the AGPL text
#   THIRD_PARTY_NOTICES.md  every dependency and its own licence
#   PRIVACY.md              what is stored and what is sent
#   SOURCE.md               how to get the source for THIS binary
#   README.txt              a short orientation, including how to open an
#                           unsigned build
#
# Usage (from the repository root, after `flutter build macos --release`):
#
#   tool/package_macos_release.sh <version> <tag> [--skip-build-check]
#
# Signing is not done here. When the build is signed, sign the .app before
# running this and notarize the .dmg afterwards (see RELEASING.md).

set -euo pipefail

fail() { echo "error: $*" >&2; exit 1; }

[[ $# -ge 2 ]] || fail "usage: $0 <version> <tag> [--skip-build-check]"
version=$1
tag=$2
skip_build_check=false
[[ ${3:-} == --skip-build-check ]] && skip_build_check=true

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
[[ -f pubspec.yaml ]] || fail "pubspec.yaml not found."

# ── Sanity: the version must be the one that was built ───────────────────
pubspec_version=$(sed -n 's/^version:[[:space:]]*\([^+]*\).*/\1/p' pubspec.yaml | head -n1)
[[ $pubspec_version == "$version" ]] ||
  fail "pubspec.yaml says $pubspec_version but the version given is $version."

commit=$(git rev-parse HEAD)

# ── Sanity: the tree the binary came from ────────────────────────────────
# Same rule as on Windows: lib/core/build_info.dart is the one file the
# documented procedure leaves modified; anything else means the binary does not
# correspond to a commit.
if ! $skip_build_check; then
  dirty=$(git status --porcelain -- . ':(exclude)lib/core/build_info.dart')
  [[ -z $dirty ]] || fail "working tree is not clean:"$'\n'"$dirty"
  head_tag=$(git describe --tags --exact-match HEAD 2>/dev/null || true)
  [[ $head_tag == "$tag" ]] || fail "HEAD is not tagged $tag."

  stamp_commit=$(sed -n "s/.*buildCommit = '\([^']*\)'.*/\1/p" lib/core/build_info.dart)
  stamp_tag=$(sed -n "s/.*buildTag = '\([^']*\)'.*/\1/p" lib/core/build_info.dart)
  [[ $stamp_commit == "$commit" ]] ||
    fail "build_info.dart names commit '$stamp_commit' but HEAD is '$commit'. Run tool/write_build_info.dart and rebuild."
  [[ $stamp_tag == "$tag" ]] ||
    fail "build_info.dart names tag '$stamp_tag' but this release is '$tag'. Run tool/write_build_info.dart and rebuild."
fi

# ── Inputs ───────────────────────────────────────────────────────────────
app="build/macos/Build/Products/Release/Hardline.app"
[[ -d $app ]] || fail "no build output at $app. Run: flutter build macos --release"
[[ -x $app/Contents/MacOS/Hardline ]] || fail "$app has no executable. Did the build succeed?"

for doc in LICENSE THIRD_PARTY_NOTICES.md PRIVACY.md SOURCE.md; do
  [[ -f $doc ]] || fail "$doc is missing from the repository root. A release must carry it."
done

dart run tool/generate_third_party_notices.dart --check ||
  fail "THIRD_PARTY_NOTICES.md is out of date with pubspec.lock."

# ── Stage ────────────────────────────────────────────────────────────────
name="hardline-$version-macos"
dist="$root/dist"
stage="$dist/$name"
rm -rf "$stage"
mkdir -p "$stage"

# ditto, not cp -R: it keeps the bundle's symlinks, extended attributes and
# code signature intact. cp -R can break a signed framework.
ditto "$app" "$stage/Hardline.app"
cp LICENSE THIRD_PARTY_NOTICES.md PRIVACY.md "$stage/"

sed -e "s/VERSION_PLACEHOLDER/$version/g" \
    -e "s/TAG_PLACEHOLDER/$tag/g" \
    -e "s/COMMIT_PLACEHOLDER/$commit/g" SOURCE.md > "$stage/SOURCE.md"
if grep -q '_PLACEHOLDER' "$stage/SOURCE.md"; then
  fail "a placeholder survived in SOURCE.md. Do not publish this package."
fi

cat > "$stage/README.txt" <<EOF
Hardline $version
An independent desktop client for the Matrix protocol.

Drag Hardline.app into Applications, then open it from there.

If macOS says the app "cannot be opened" or "is damaged", this build is not
notarized by Apple. Open it anyway like this:
  macOS 15 and later: try to open it once, then System Settings > Privacy &
    Security > scroll down > "Open Anyway".
  macOS 14 and earlier: right-click Hardline.app > Open > Open.
Check the SHA-256 on the release page before you do.

Copyright (C) 2026 Mein1337
Licensed under the GNU Affero General Public License, version 3 or later.
This program comes with ABSOLUTELY NO WARRANTY.

  LICENSE                 the full licence text
  THIRD_PARTY_NOTICES.md  the components this is built from, and their licences
  PRIVACY.md              what is stored locally, and what is sent where
  SOURCE.md               how to obtain the source code for THIS build

Source for this exact build:
  https://github.com/tMein1337/hardline/tree/$commit

Release page:
  https://github.com/tMein1337/hardline/releases/tag/$tag

Hardline is not affiliated with, endorsed by, or sponsored by The Matrix.org
Foundation C.I.C. or by Google LLC.
EOF

# The usual drag-to-install shortcut.
ln -s /Applications "$stage/Applications"

# ── Disk image ───────────────────────────────────────────────────────────
dmg="$dist/$name.dmg"
rm -f "$dmg"
echo "Building $dmg ..."
hdiutil create -volname "Hardline $version" -srcfolder "$stage" \
  -fs HFS+ -format UDZO -ov "$dmg" >/dev/null

# ── Checksums ────────────────────────────────────────────────────────────
(cd "$dist" && shasum -a 256 "$name.dmg" > SHA256SUMS-macos.txt)

echo
echo "Staged:    $stage"
echo "Image:     $dmg"
echo "Checksums: $dist/SHA256SUMS-macos.txt"
cat "$dist/SHA256SUMS-macos.txt"
