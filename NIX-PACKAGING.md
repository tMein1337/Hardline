<!--
SPDX-FileCopyrightText: 2026 Mein1337
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Packaging Hardline for Nix / nixpkgs

This documents the Nix support: a hermetic `packages.default` that anyone can run
with `nix run github:tMein1337/Hardline`, plus the `devShell` used for local work.

## Status: `nix run` works (`flake.nix`)

`packages.default` is a hermetic `flutter.buildFlutterApplication`. Both
network-fetching build steps are pinned; the build runs with no network in the
sandbox and the result is self-contained (verified: it loads every native lib and
reaches GTK display init). The Flutter version is **not** an issue: the pinned
nixpkgs ships Flutter 3.44.4 / Dart 3.12.2, which satisfies `sdk: ^3.12.2`.

How the two blockers are solved — via nixpkgs' pub **source builders**
(`customSourceBuilders` in `flake.nix`, files under `nix/`):

- **libwebrtc (Blocker 1)** — `nix/flutter_webrtc.nix` pre-fetches the exact
  prebuilt release as a fixed-output derivation and drops both the zip and the
  pre-extracted `third_party/libwebrtc/` into the package source, so the plugin's
  CMake download guard is skipped and nothing is written at build time.
- **cargokit / rustup (Blocker 2)** — `super_native_extensions` is handled by
  nixpkgs' built-in source builder; `flutter_vodozemac` 0.6.0 is not (its map
  stops at 0.5.0), so `nix/flutter_vodozemac.nix` mirrors the upstream builder and
  adds the 0.6.0 `cargoHash`. Both compile the Rust with
  `rustPlatform.buildRustPackage` (offline, vendored) and replace cargokit's
  rustup-driven `cargokit.cmake` with a stub — so **no rustup and no crate
  downloads** happen during the Flutter build.

Runtime self-containment (replacing the devShell's `LD_LIBRARY_PATH`): the wrapper
adds the runtime libs, `/run/opengl-driver/lib` and the app's bundled `lib/`, and
`NIX_LDFLAGS = -rpath …` bakes the libwebrtc DT_NEEDED libs (libgbm/libdrm/X11/…)
into the binaries — which is also what lets the final executable *link* against
the prebuilt `libwebrtc.so` (GNU ld resolves a transitive shared-lib dep via
-rpath, not `-L`). NixOS-first; non-NixOS users launch via nixGL (see README).

---

## Appendix: original investigation notes

The material below is the pre-implementation analysis. It is kept for context; the
shipped approach above (nixpkgs source builders) supersedes the hand-rolled
`patchelf` / `importCargoLock` sketch here.

## What works today (`flake.nix`)

`nix develop` (or direnv via `.envrc`) gives a shell where `flutter run -d linux`
both **builds and runs** (verified: the window shows and E2EE initialises). It
fixes five distinct NixOS breakages, each of which failed differently:

1. **Rust toolchain for cargokit** *(build fails loudly).* `flutter_vodozemac`
   and `super_native_extensions` compile Rust through *cargokit*, which invokes
   `rustup` directly. The shell provides `rustup` and installs a default `stable`
   toolchain on first entry. (nix-ld — already enabled on this host — is what
   lets rustup's downloaded binaries run.)
2. **`libwebrtc.so`'s native link deps** *(link fails loudly).* flutter_webrtc
   ships a prebuilt `libwebrtc.so` whose `DT_NEEDED` list (`libgbm.so.1`,
   `libdrm.so.2`, the `libX11*` set, glib, libstdc++) isn't on NixOS' default
   search path → `undefined reference to gbm_create_device` / `drmGetDevices2`.
   On `LD_LIBRARY_PATH` (nix-ld reads it at runtime too). `libpulse` is included
   as well — enables flutter_webrtc's system-audio loopback and silences its
   CMake warning.
3. **GPU driver for rendering** *(silent — app runs, no window).* Foreign GL
   apps need the system's mesa driver at `/run/opengl-driver/lib`; without it EGL
   has no backend, Flutter renders no frame, and on Wayland a bufferless surface
   is never shown. Prepended to `LD_LIBRARY_PATH`.
4. **`libsqlite3.so`** *(silent — throws before `runApp`, so no window).*
   `sqflite_common_ffi` opens the Matrix store via a bare-name `dlopen`. Added
   via `pkgs.sqlite`. See "The store cipher is missing on Nix" below for what
   that costs.
5. **The app's own bundled Rust libs** *(silent — E2EE quietly disabled).*
   `libvodozemac_bindings_dart.so` lives in `build/…/bundle/lib` and is
   `dlopen`'d by bare name, but the Flutter runner leaves the executable with no
   usable RUNPATH under Nix. The shell adds the bundle lib dirs to
   `LD_LIBRARY_PATH`.

This is the reproducible *build+run environment*. The `devShell` is intentionally
inert on non-NixOS distros, where these libraries live in standard paths.

> The three *silent* failures (3–5) are the instructive ones: nothing errored in
> the build, the process ran happily, and the only symptom was "no window". They
> are also what the hermetic package must handle at **runtime** — via
> `patchelf`/`makeWrapper` (baking rpaths + `/run/opengl-driver/lib`), not
> `LD_LIBRARY_PATH`.

> Note: `flutter` is taken from your ambient (home-manager) install, not the
> shell. nixpkgs' `flutter` is currently **3.41.9**, whose bundled Dart predates
> this app's `sdk: ^3.12.2`. The hermetic package below must pin a flutter whose
> Dart is ≥ 3.12.2 (your working toolchain is 3.44.4 / Dart 3.12.2).

## Goal: a hermetic `packages.default` (`buildFlutterApplication`)

nixpkgs builds run in a sandbox with **no network**. Two dependencies fetch from
the network mid-build and are the whole difficulty. Everything else is standard
`flutter.buildFlutterApplication` (it consumes `pubspec.lock` and computes an
FOD for the pub cache).

### Blocker 1 — flutter_webrtc downloads a prebuilt `libwebrtc.so`

- **Where:** `flutter_webrtc/third_party/CMakeLists.txt` reads
  `third_party/libwebrtc_version.ini` (`binary_version`, `download_url`) and
  composes
  `"<download_url>/<binary_version>/libwebrtc-linux-x64-release.zip"`,
  saving to `third_party/downloads/<asset>.zip` and extracting into
  `third_party/libwebrtc/`. For this app that resolves to:
  ```
  https://github.com/webrtc-sdk/libwebrtc/releases/download/libwebrtc.m144.7559.09/libwebrtc-linux-x64-release.zip
  ```
- **Fix:** pre-fetch it as a fixed-output derivation and drop it where CMake
  expects it *before* the build, so the guarded download is skipped:
  ```nix
  libwebrtcZip = pkgs.fetchurl {
    url = "https://github.com/webrtc-sdk/libwebrtc/releases/download/libwebrtc.m144.7559.09/libwebrtc-linux-x64-release.zip";
    hash = "sha256-AAAA…";   # fill from the first build's mismatch error
  };
  ```
  Then in the app derivation, `preBuild`/`postPatch`:
  ```sh
  mkdir -p <plugin>/third_party/downloads
  cp ${libwebrtcZip} <plugin>/third_party/downloads/libwebrtc-linux-x64-release.zip
  ```
  Confirm `third_party/CMakeLists.txt` guards on `if(NOT EXISTS ${ZIPFILE})`
  (skip download when the zip is present); patch that guard if needed.
- **Runtime:** instead of relying on `LD_LIBRARY_PATH`, patch the shipped lib so
  the packaged binary is self-contained:
  ```sh
  patchelf --add-rpath ${lib.makeLibraryPath [ libgbm libdrm glib gtk3 stdenv.cc.cc.lib
      libx11 libxcomposite libxdamage libxext libxfixes libxrandr ]} \
    $out/.../lib/libwebrtc.so
  ```
  or add those to the wrapped executable's `runtimeDependencies` /
  `makeWrapper --prefix LD_LIBRARY_PATH`.

### Blocker 2 — cargokit (vodozemac + super_native_extensions) fetch crates

- **Where:** both plugins carry a `rust/Cargo.lock`
  (`flutter_vodozemac-0.6.0/rust/Cargo.lock`,
  `super_native_extensions-0.9.1/rust/Cargo.lock`). cargokit runs `cargo build`,
  which downloads crates, and drives `rustup` — both impossible in the sandbox.
- **Fix (approach):**
  1. Vendor each lockfile offline with `pkgs.rustPlatform.importCargoLock`
     (or `fetchCargoVendor`) → a `.cargo/config.toml` pointing at the vendored
     registry.
  2. Provide a real toolchain via `pkgs.rustPlatform`/`rustc`+`cargo` (or a
     pinned `rustc` from `rust-overlay`) and force cargokit onto it instead of
     rustup. cargokit honours `CARGOKIT_*` env and can use a "precompiled" /
     system-cargo path; the reliable route in nixpkgs is to set
     `CARGO_HOME`/`RUSTUP_HOME` and a cargo config so no network/rustup call is
     made. This is the part that needs iteration — cargokit's rustup assumption
     is the friction point (see `cargokit/build_tool/lib/src/rustup.dart`).
  3. Because there are **two** cargokit plugins, expect two vendor derivations.

### Skeleton to start from

```nix
packages.default = pkgs.flutter.buildFlutterApplication {
  pname = "hardline";
  version = "0.1.0";
  src = ./.;
  autoPubspecLock = ./pubspec.lock;         # pub deps FOD

  nativeBuildInputs = [ pkgs.pkg-config pkgs.patchelf /* + cargo/rustc */ ];
  buildInputs = runtimeLibs;                # same list as the devShell

  # postPatch: drop libwebrtcZip into third_party/downloads (Blocker 1)
  # + wire vendored cargo registries for the two rust plugins (Blocker 2)
  # postFixup: patchelf --add-rpath runtimeLibs into the bundled libwebrtc.so
};
```

## The store cipher is missing on Nix

**Optional on-device encryption (`Settings → Security`) does not work on the Nix
build.** The app detects this and refuses to turn the setting on, with a message
saying why. It is not silently degraded, and everything else is unaffected.

**Why.** `pubspec.yaml` asks `package:sqlite3` for the
[SQLite3 Multiple Ciphers](https://github.com/utelle/SQLite3MultipleCiphers)
build — stock SQLite plus a page-level cipher behind `PRAGMA key`:

```yaml
hooks:
  user_defines:
    sqlite3:
      source: sqlite3mc
```

That request is honoured everywhere except here. nixpkgs carries its own source
builder for the `sqlite3` pub package
(`pkgs/development/compilers/dart/package-source-builders/sqlite3`), which
patches the package's build hook:

```nix
substituteInPlace lib/src/hook/compile/description.dart \
  --replace-fail "return fromGitHub(LibraryType.sqlite3);" "return LookupSystem('sqlite3');"
```

It has to: the unpatched hook *downloads* a prebuilt library from GitHub
releases at build time, which no hermetic build can allow. But the patch is
unconditional, so it overrides the `user_defines` above and links `pkgs.sqlite`
— plain SQLite, which accepts `PRAGMA key` and **ignores it**. Silently writing
plaintext behind a padlock is the one outcome that must not happen, which is why
`requireCipherSupport()` in `lib/core/storage/store_cipher.dart` probes for
`sqlite3mc_version()` before it will key anything.

**Two routes out**, neither taken yet because neither can be tested from the
machine this was written on:

1. **Package SQLite3 Multiple Ciphers in this flake** and supply our own
   `customSourceBuilders.sqlite3` patching to `LookupSystem('sqlite3mc')`, the
   way `nix/flutter_webrtc.nix` already supplies a fixed-output derivation for
   a prebuilt library. Keeps one cipher and one on-disk format across every
   platform, which is why it is the preferred route. It needs a `sha256` that
   only a real `nix build` can produce.
2. **Use `pkgs.sqlcipher`**, which nixpkgs already has, patching to
   `LookupSystem('sqlcipher')`. Much less work — but SQLCipher is a *different*
   cipher with different pragmas, so `store_cipher.dart` would have to learn
   both, and a store written on Linux would not open on Windows. Only worth it
   if route 1 proves impractical.

## Toward nixpkgs proper

- Pin `flutter` (Dart ≥ 3.12.2) inside the package rather than the ambient one.
- Prefer `patchelf`/`makeWrapper` over `LD_LIBRARY_PATH` so the result runs
  outside any dev shell.
- A nixpkgs submission for an app bundling a prebuilt `libwebrtc.so` will draw
  review scrutiny (binary blob, `webrtc-sdk` provenance). A personal flake
  `packages.default` is the pragmatic first destination; upstreaming is a later
  step once the two blockers above build reproducibly.
