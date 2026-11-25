# SPDX-FileCopyrightText: 2026 Mein1337
# SPDX-License-Identifier: AGPL-3.0-or-later

{
  description = "Hardline — an independent Flutter client for the Matrix protocol; reproducible NixOS build/run environment and a hermetic package.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  # Binary cache, so consumers download the built app instead of recompiling
  # Flutter + libwebrtc + the two Rust plugins. `nix run github:…` only honours
  # these when the caller passes --accept-flake-config or is a trusted user.
  # Fill in the real cache name and public key once the Cachix cache exists.
  nixConfig = {
    extra-substituters = [ "https://hardline.cachix.org" ];
    extra-trusted-public-keys = [ "hardline.cachix.org-1:uT6o7En8gf05Q8TDpkEQcNPxlNAy74koJkuLUX3/WAQ=" ];
  };

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
        sqlite # libsqlite3.so — the store itself no longer loads this: the
        #        package links SQLite3 Multiple Ciphers by absolute path (see
        #        nix/sqlite3mc.nix and postPatch below). Kept because a
        #        missing SQLite fails silently — the Matrix client throws
        #        before runApp and no window ever appears — so anything still
        #        asking for plain libsqlite3 by name should find it.
        # X11 libs pulled in by libwebrtc.so (top-level attrs; the `xorg.*`
        # set was deprecated in nixpkgs):
        libx11
        libxcomposite
        libxdamage
        libxext
        libxfixes
        libxrandr
        # Wayland screen sharing (linux/screencast/): the portal hands over a
        # PipeWire stream, and its GPU buffers are read back through EGL/GLES.
        # libglvnd only dispatches; the driver itself comes from
        # /run/opengl-driver at runtime.
        pipewire
        libglvnd
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
          # Reuse the macOS app icon as the Linux hicolor icon source. Referencing
          # the single file (rather than ./.) imports only it into the store.
          appIcon = ./macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png;
          sqlite3mc = pkgs.callPackage ./nix/sqlite3mc.nix { };
          # lastModifiedDate is "YYYYMMDDhhmmss" (UTC); render it as ISO-8601.
          buildTimestamp =
            let d = self.lastModifiedDate; sub = builtins.substring; in
            "${sub 0 4 d}-${sub 4 2 d}-${sub 6 2 d}T${sub 8 2 d}:${sub 10 2 d}:${sub 12 2 d}Z";
        in
        pkgs.flutter.buildFlutterApplication {
          pname = "hardline";
          # The app's own version, read from pubspec.yaml so the two cannot
          # drift ("0.3.0+5" -> "0.3.0"; the build number is Flutter's).
          version = builtins.head
            (builtins.match ".*\nversion: ([0-9]+[.][0-9]+[.][0-9]+).*" (builtins.readFile ./pubspec.yaml));
          src = ./.;

          # pubspec.yaml asks package:sqlite3's build hook for SQLite3 Multiple
          # Ciphers (`hooks.user_defines.sqlite3.source: sqlite3mc`), the build
          # behind on-device encryption. The hook fetches it prebuilt from GitHub
          # at build time; the sandbox has no network, and nixpkgs' sqlite3 source
          # builder only redirects the hook's *default* download, not this one.
          # So the Nix build points the hook at the same library built from
          # source (nix/sqlite3mc.nix), by absolute store path: `source: system`
          # with a `name` that is a path is loaded as exactly that file.
          #
          # Then stamp the About screen the way tool/write_build_info.dart does
          # for the other platforms. The sandbox has no .git, so the commit comes
          # from the flake itself: `self.rev` exists only for a clean checkout,
          # and a dirty tree stays `unknown`, which the app reports as a
          # development build. The timestamp is the commit's, not the build's,
          # so the output stays reproducible.
          postPatch = ''
            substituteInPlace pubspec.yaml \
              --replace-fail "      source: sqlite3mc" \
                "      source: system"$'\n'"      name: ${sqlite3mc}/lib/libsqlite3mc.so"
          '' + lib.optionalString (self ? rev) ''
            substituteInPlace lib/core/build_info.dart \
              --replace-fail "const buildCommit = 'unknown';" "const buildCommit = '${self.rev}';" \
              --replace-fail "const buildTimestamp = 'unknown';" "const buildTimestamp = '${buildTimestamp}';"
          '';

          # IFD (allowed in a flake, unlike nixpkgs): read pubspec.lock directly
          # instead of maintaining a committed pubspec.lock.json.
          autoPubspecLock = ./pubspec.lock;

          customSourceBuilders = {
            flutter_vodozemac = pkgs.callPackage ./nix/flutter_vodozemac.nix { };
            flutter_webrtc = pkgs.callPackage ./nix/flutter_webrtc.nix { };
          };

          # Desktop integration: an application-menu entry and a hicolor icon, so
          # the result is an installable app and not just a binary on PATH.
          # copyDesktopItems installs `desktopItems` during postInstall;
          # imagemagick resizes the icon below. buildFlutterApplication appends
          # its own nativeBuildInputs (wrapGAppsHook3, pkg-config), so this is
          # additive.
          nativeBuildInputs = [ pkgs.copyDesktopItems pkgs.imagemagick ];

          desktopItems = [
            (pkgs.makeDesktopItem {
              name = "com.mein1337.hardline"; # -> com.mein1337.hardline.desktop
              desktopName = "Hardline";
              genericName = "Matrix client";
              comment = "An independent client for the Matrix protocol";
              exec = "hardline";
              icon = "com.mein1337.hardline";
              categories = [ "Network" "InstantMessaging" ];
              keywords = [ "Matrix" "Chat" "Messaging" ];
              # Must equal the GTK application-id / g_set_prgname (see
              # linux/CMakeLists.txt) or the running window won't bind to this
              # entry's icon in the dock/launcher.
              startupWMClass = "com.mein1337.hardline";
            })
          ];

          # imagemagick 7 provides `magick`. `''${s}` emits a literal ${s} for
          # bash rather than interpolating in Nix.
          postInstall = ''
            for s in 16 24 32 48 64 128 256 512; do
              dir=$out/share/icons/hicolor/''${s}x''${s}/apps
              mkdir -p "$dir"
              magick ${appIcon} -resize ''${s}x''${s} "$dir/com.mein1337.hardline.png"
            done
          '';

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
          #   * __EGL_EXTERNAL_PLATFORM_CONFIG_DIRS — NVIDIA's EGL looks for its
          #     Wayland/GBM platform plugins only in /etc/egl and /usr/share/egl,
          #     which a NixOS system need not have. Without them every EGL
          #     context fails on Wayland ("No GL implementation is available")
          #     and the app crashes. NixOS ships the descriptors under
          #     /run/opengl-driver; a value the user set still wins.
          # NixOS-first by design; non-NixOS users launch via nixGL (see README).
          # One line: dartFixupHook evals this string, so a newline would end
          # the wrapProgram command.
          extraWrapProgramArgs = ''
            --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}:/run/opengl-driver/lib:$out/app/hardline/lib" --set-default __EGL_EXTERNAL_PLATFORM_CONFIG_DIRS /run/opengl-driver/share/egl/egl_external_platform.d
          '';

          meta = {
            description = "An independent Flutter client for the Matrix protocol";
            mainProgram = "hardline";
            platforms = [ "x86_64-linux" ];
            license = lib.licenses.agpl3Plus;
            # fromSource: the Dart/Rust compiled in-sandbox. binaryNativeCode: the
            # bundled prebuilt libwebrtc.so (see nix/flutter_webrtc.nix).
            sourceProvenance = with lib.sourceTypes; [ fromSource binaryNativeCode ];
          };
        };
    in
    {
      packages = forAllSystems (pkgs: rec {
        hardline = mkHardline pkgs;
        default = hardline;
      });

      # Inject the *pin-built* package into a consumer's pkgs. It deliberately
      # does not rebuild against their nixpkgs — the pinned nixpkgs is
      # load-bearing (Flutter version, source builders, cargoHashes), which is
      # also why consumers must not `follows` our nixpkgs. The cost is no
      # shared-lib dedup with their system; the binary cache is the mitigation.
      overlays.default = final: prev: {
        hardline = self.packages.${prev.system}.hardline;
      };

      nixosModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.programs.hardline;
        in
        {
          options.programs.hardline.enable =
            lib.mkEnableOption "Hardline, an independent Matrix client";

          config = lib.mkIf cfg.enable {
            environment.systemPackages = [ self.packages.${pkgs.system}.default ];

            # hardware.graphics.enable is what populates /run/opengl-driver/lib,
            # which the wrapper bakes onto LD_LIBRARY_PATH; without it Hardline
            # starts but paints no window. Warn rather than block — a headless or
            # remote setup may still want the package present.
            warnings = lib.optional (!config.hardware.graphics.enable)
              "programs.hardline: hardware.graphics.enable is false — Hardline needs /run/opengl-driver/lib to render.";
          };
        };

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

              # NVIDIA's Wayland EGL plugins: same reason as in the package
              # wrapper (extraWrapProgramArgs above).
              export __EGL_EXTERNAL_PLATFORM_CONFIG_DIRS="''${__EGL_EXTERNAL_PLATFORM_CONFIG_DIRS:-/run/opengl-driver/share/egl/egl_external_platform.d}"

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
