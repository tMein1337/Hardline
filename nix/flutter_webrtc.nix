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
# Version/URL are pinned to what flutter_webrtc 1.6.3 requests
# (third_party/libwebrtc_version.ini: binary_version = libwebrtc.m150.7871.07).
# If the plugin is bumped, re-read that manifest and re-pin url + hash. A stale
# pin does not fail loudly: CMake finds *a* zip and skips the download, so the
# plugin's headers and the prebuilt library would silently disagree.
{
  lib,
  stdenv,
  fetchurl,
  unzip,
}:

{ version, src, ... }:

let
  libwebrtcZip = fetchurl {
    url = "https://github.com/webrtc-sdk/libwebrtc/releases/download/libwebrtc.m150.7871.07/libwebrtc-linux-x64-release.zip";
    hash = "sha256-7zgFJs+WFoSLwLl7JJkMvyrYUcIJ1dzpPMPrudN4n7w=";
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

    # 2. Pre-extract it exactly the way third_party/CMakeLists.txt would: a
    #    single top-level directory (whatever it is called) becomes
    #    third_party/libwebrtc/; an archive with files at its root is wrapped
    #    in one instead.
    tmp=$(mktemp -d)
    unzip -q "${libwebrtcZip}" -d "$tmp"
    rm -rf "$out/third_party/libwebrtc"
    entries=("$tmp"/*)
    if [ "''${#entries[@]}" -eq 1 ] && [ -d "''${entries[0]}" ]; then
      mv "''${entries[0]}" "$out/third_party/libwebrtc"
    else
      mkdir "$out/third_party/libwebrtc"
      mv "$tmp"/* "$out/third_party/libwebrtc/"
    fi
    rm -rf "$tmp"
    test -f "$out/third_party/libwebrtc/lib/libwebrtc.so"

    runHook postInstall
  '';
}
