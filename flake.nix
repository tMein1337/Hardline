# SPDX-FileCopyrightText: 2026 Mein1337
# SPDX-License-Identifier: AGPL-3.0-or-later

{
  description = "Hardline — an independent Flutter client for the Matrix protocol; reproducible NixOS build/run environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
    in
    {
      devShells = forAllSystems (pkgs:
        let
          lib = pkgs.lib;

          # Native libraries the *built app* links against and needs at runtime.
          # Every one of these is dragged in by flutter_webrtc's prebuilt
          # libwebrtc.so (confirmed with `ldd` — it is the only library in the
          # bundle with unresolved NEEDED entries). A plain Flutter app on NixOS
          # needs none of them; that is why this is the app's concern, not the
          # Flutter toolchain's.
          runtimeLibs = with pkgs; [
            libgbm # libgbm.so.1  — WebRTC screen/video capture (GBM)
            libdrm # libdrm.so.2
            glib # libglib-2.0 / libgio-2.0 / libgobject-2.0
            gtk3 # gtk/gdk — Flutter's Linux shell
            stdenv.cc.cc.lib # libstdc++.so.6
            pulseaudio # libpulse — enables system-audio loopback capture and
            #             silences flutter_webrtc's CMake libpulse warning
            sqlite # libsqlite3.so — sqflite_common_ffi opens the Matrix store
            #        with a bare-name dlopen. Missing => buildMatrixClient throws
            #        before runApp, so no first frame is ever produced and the
            #        window is never shown (looks like a hung/invisible app).
            # X11 libs pulled in by libwebrtc.so (top-level attrs; the `xorg.*`
            # set was deprecated in nixpkgs):
            libx11
            libxcomposite
            libxdamage
            libxext
            libxfixes
            libxrandr
          ];
        in
        {
          default = pkgs.mkShell {
            # pkg-config + the *dev* outputs of these libs let flutter_webrtc's
            # CMake resolve `pkg_check_modules(PULSE libpulse libpulse-simple)`
            # (-> HAVE_LIBPULSE) and gtk at configure time.
            #
            # NOTE: `flutter` itself is intentionally taken from your ambient
            # environment (home-manager), not from nixpkgs: nixpkgs' `flutter`
            # is currently 3.41.9, whose bundled Dart is older than this app's
            # `sdk: ^3.12.2` constraint. Your installed 3.44.4 (Dart 3.12.2) is
            # what this shell is verified against. The hermetic package
            # (see NIX-PACKAGING.md) pins a compatible flutter instead.
            nativeBuildInputs = with pkgs; [ pkg-config rustup ];
            buildInputs = runtimeLibs;

            shellHook = ''
              # Two things go on LD_LIBRARY_PATH:
              #
              # 1. /run/opengl-driver/lib — NixOS exposes the GPU driver (mesa
              #    libEGL_mesa + gallium DRI) that matches the running kernel
              #    here. A dev-shell GUI app that can't find it gets an EGL
              #    dispatcher with NO driver behind it, so Flutter renders no
              #    frame; on Wayland a bufferless surface is never shown, so you
              #    get a live process but NO visible window. Must come first.
              #
              # 2. libwebrtc.so's DT_NEEDED libs (libgbm/libdrm/X11/glib/...),
              #    which aren't on NixOS' default search path. This is what fixes
              #    the "undefined reference to gbm_create_device / drmGetDevices2"
              #    link failure and resolves them at runtime (nix-ld reads
              #    LD_LIBRARY_PATH).
              export LD_LIBRARY_PATH="/run/opengl-driver/lib:${lib.makeLibraryPath runtimeLibs}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

              # The app's own Rust plugin libs (e.g. libvodozemac_bindings_dart.so)
              # sit in the build bundle and are dlopen'd by bare name, but the
              # Flutter runner leaves the executable with no usable RUNPATH under
              # Nix — so put the bundle lib dirs on the path too. Nonexistent
              # before the first build (harmless). The hermetic package patches
              # rpaths instead; see NIX-PACKAGING.md.
              _root="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
              for _flavor in debug profile release; do
                export LD_LIBRARY_PATH="$_root/build/linux/x64/$_flavor/bundle/lib:$LD_LIBRARY_PATH"
              done

              # flutter_vodozemac and super_native_extensions compile Rust via
              # cargokit, which drives `rustup` directly (it calls
              # `rustup toolchain install` / `rustup target add`), so a bare
              # nixpkgs cargo/rustc will not do. Ensure a default toolchain
              # exists; install once, idempotently.
              if command -v rustup >/dev/null 2>&1 && ! rustup default >/dev/null 2>&1; then
                echo "Hardline devshell: no default Rust toolchain — installing stable (first run only)…"
                rustup default stable
              fi

              echo "Hardline devshell ready. Build/run with:  flutter run -d linux"
            '';
          };
        });
    };
}
