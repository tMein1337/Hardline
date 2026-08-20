# SPDX-FileCopyrightText: 2026 Mein1337
# SPDX-License-Identifier: AGPL-3.0-or-later

{
  description = "Hardline — an independent Flutter client for the Matrix protocol; reproducible NixOS build/run environment and a hermetic package.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));

      # Native libraries the *built app* links against and needs at runtime.
      # Every one of these is dragged in by flutter_webrtc's prebuilt
      # libwebrtc.so (confirmed with `ldd` — it is the only library in the
      # bundle with unresolved NEEDED entries). A plain Flutter app on NixOS
      # needs none of them; that is why this is the app's concern, not the
      # Flutter toolchain's. Shared by both the devShell and the package.
      runtimeLibsFor = pkgs: with pkgs; [
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

      # The hermetic package. Uses nixpkgs' flutter.buildFlutterApplication,
      # which consumes pubspec.lock, builds an FOD for the pub cache, and applies
      # per-package "source builders" for pub packages that need native work.
      #
      # nixpkgs already ships source builders for super_native_extensions (0.9.1),
      # matrix, sqlite3 and xdg_directories. We supply two of our own via
      # customSourceBuilders:
      #   * flutter_vodozemac — nixpkgs' builder only knows versions up to 0.5.0
      #     and throws on our 0.6.0, so we add the 0.6.0 cargoHash (nix/…).
      #   * flutter_webrtc    — has no upstream builder; ours pre-fetches the
      #     prebuilt libwebrtc as an FOD (Blocker 1; nix/…).
      # Both cargokit plugins are built from source, offline: the source builders
      # compile the Rust with rustPlatform.buildRustPackage and stub out cargokit's
      # rustup-driven cmake, so no rustup and no crate downloads happen mid-build.
      mkHardline = pkgs:
        let
          lib = pkgs.lib;
          runtimeLibs = runtimeLibsFor pkgs;
        in
        pkgs.flutter.buildFlutterApplication {
          pname = "hardline";
          version = "0.1.1";
          src = ./.;

          # IFD (allowed in a flake, unlike nixpkgs): read pubspec.lock directly
          # instead of maintaining a committed pubspec.lock.json.
          autoPubspecLock = ./pubspec.lock;

          customSourceBuilders = {
            flutter_vodozemac = pkgs.callPackage ./nix/flutter_vodozemac.nix { };
            flutter_webrtc = pkgs.callPackage ./nix/flutter_webrtc.nix { };
          };

          # Dev libraries flutter_webrtc's CMake resolves via pkg-config
          # (GTK, libpulse -> HAVE_LIBPULSE) and links the prebuilt libwebrtc.so
          # against. pkg-config itself is added by buildFlutterApplication.
          buildInputs = runtimeLibs;

          # The final executable links against the prebuilt libwebrtc.so, whose
          # DT_NEEDED list includes libgbm.so.1 / libdrm.so.2. buildInputs only
          # get a `-L` from the cc-wrapper, but GNU ld does NOT search `-L` dirs
          # when resolving a *transitive* shared-lib dependency — only -rpath /
          # -rpath-link / LD_LIBRARY_PATH — so the link fails with
          # "undefined reference to gbm_create_device". Add an -rpath for the
          # runtime libs: this both satisfies ld's transitive resolution at link
          # time and bakes the path into the binaries for runtime (kept by the
          # installer's rpath cleanup, which only strips /build paths).
          NIX_LDFLAGS = "-rpath ${lib.makeLibraryPath runtimeLibs}";

          # Runtime self-containment. The devShell fixed the same breakages via
          # LD_LIBRARY_PATH; here we bake them into the wrapper so the result runs
          # with no dev shell:
          #   * /run/opengl-driver/lib — the NixOS GPU driver (mesa EGL + DRI);
          #     without it Flutter renders no frame and shows no window.
          #   * libwebrtc.so's DT_NEEDED libs (libgbm/libdrm/X11/glib/libstdc++)
          #     and the bare-name dlopen'd libsqlite3/libpulse.
          #   * $out/app/hardline/lib — the app's own bundled Rust .so's
          #     (libvodozemac_bindings_dart.so, libsuper_native_extensions.so).
          # NixOS-first by design; non-NixOS users launch via nixGL (see README).
          extraWrapProgramArgs = ''
            --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}:/run/opengl-driver/lib:$out/app/hardline/lib"
          '';

          meta = {
            description = "An independent Flutter client for the Matrix protocol";
            mainProgram = "hardline";
            platforms = [ "x86_64-linux" ];
            license = lib.licenses.agpl3Plus;
          };
        };
    in
    {
      packages = forAllSystems (pkgs: rec {
        hardline = mkHardline pkgs;
        default = hardline;
      });

      apps = forAllSystems (pkgs: rec {
        hardline = {
          type = "app";
          program = "${mkHardline pkgs}/bin/hardline";
        };
        default = hardline;
      });

      devShells = forAllSystems (pkgs:
        let
          lib = pkgs.lib;
          runtimeLibs = runtimeLibsFor pkgs;
        in
        {
          default = pkgs.mkShell {
            # pkg-config + the *dev* outputs of these libs let flutter_webrtc's
            # CMake resolve `pkg_check_modules(PULSE libpulse libpulse-simple)`
            # (-> HAVE_LIBPULSE) and gtk at configure time.
            #
            # NOTE: `flutter` here is intentionally taken from your ambient
            # environment (home-manager), not from nixpkgs. The hermetic
            # `packages.default` above instead uses nixpkgs' flutter (3.44.4 /
            # Dart 3.12.2 in the pinned nixpkgs, which satisfies `sdk: ^3.12.2`).
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
