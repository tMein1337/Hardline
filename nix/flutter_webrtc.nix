# Custom pub source-builder for flutter_webrtc (Blocker 1).
#
# flutter_webrtc's linux/third_party/CMakeLists.txt downloads a prebuilt
# libwebrtc release zip at CMake-configure time (from libwebrtc_version.ini) and
# extracts it into third_party/libwebrtc/. That network fetch is impossible in
# the Nix build sandbox.
#
# Fix: fetch the exact release as a fixed-output derivation and pre-populate the
# package source with BOTH the zip (so the `if(NOT EXISTS ${ZIPFILE})` download
# guard is skipped) AND the already-extracted third_party/libwebrtc/ tree (so no
# write into the read-only store path is attempted at build time). CMake then
# does nothing: no download, no extraction.
#
# Version/URL are pinned to what flutter_webrtc 1.6.0 requests
# (libwebrtc_version.ini: binary_version = libwebrtc.m144.7559.09). If the plugin
# is bumped, re-read that manifest and re-pin url + hash.
{
  lib,
  stdenv,
  fetchurl,
  unzip,
}:

{ version, src, ... }:

let
  libwebrtcZip = fetchurl {
    url = "https://github.com/webrtc-sdk/libwebrtc/releases/download/libwebrtc.m144.7559.09/libwebrtc-linux-x64-release.zip";
    hash = "sha256-eWvXZV5r6nb4UfBCByH38Bf+NcWsvvRrSckIoIAZSa8=";
  };
in
stdenv.mkDerivation {
  pname = "flutter_webrtc";
  inherit version src;
  inherit (src) passthru;

  nativeBuildInputs = [ unzip ];

  installPhase = ''
    runHook preInstall

    cp -r "$src" "$out"
    chmod -R u+w "$out"

    # 1. Place the release zip where the CMake download guard looks for it.
    mkdir -p "$out/third_party/downloads"
    cp "${libwebrtcZip}" "$out/third_party/downloads/libwebrtc-linux-x64-release.zip"

    # 2. Pre-extract it exactly the way third_party/CMakeLists.txt would: the
    #    archive has a single top-level dir (linux-x64-release/) holding include/
    #    and lib/libwebrtc.so, which CMake renames to third_party/libwebrtc/.
    tmp=$(mktemp -d)
    unzip -q "${libwebrtcZip}" -d "$tmp"
    rm -rf "$out/third_party/libwebrtc"
    mv "$tmp"/linux-x64-release "$out/third_party/libwebrtc"
    rm -rf "$tmp"

    runHook postInstall
  '';
}
