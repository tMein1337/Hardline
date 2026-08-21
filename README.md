# Hardline

An independent desktop client compatible with the Matrix protocol, written in
Flutter. Primary target is Windows desktop.

Hardline is not published, sponsored or endorsed by The Matrix.org Foundation
C.I.C., and is not affiliated with it. It speaks the Matrix protocol; that is
the whole of the relationship. "Matrix" and "Flutter" are the trademarks of
their respective owners.

Written in English to match the code comments.

## License

Hardline is free software under the **GNU Affero General Public License,
version 3 or later** (`AGPL-3.0-or-later`).

- Full text: [`LICENSE`](LICENSE)
- What it covers, and what it does not:
  [`PROJECT-LICENSING-NOTICE.md`](PROJECT-LICENSING-NOTICE.md)
- Third-party components and their own licenses:
  [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)

It comes with **no warranty**, to the extent permitted by applicable law.

Every binary release is published alongside the exact corresponding source for
that build — see [`RELEASING.md`](RELEASING.md) and [`SOURCE.md`](SOURCE.md).
The running application shows its own version, commit and source link under
**Settings → About**.

| | |
|---|---|
| Privacy | [`PRIVACY.md`](PRIVACY.md) |
| Security reports | [`SECURITY.md`](SECURITY.md) |
| Contributing | [`CONTRIBUTING.md`](CONTRIBUTING.md) |

## Design

A black panel with an orange accent, borrowing the conventions of an airliner
glass cockpit: surfaces separated by very little luminance, structure from thin
rules rather than a staircase of greys, and a small set of instrument colours
that mean the same thing everywhere — **green** normal, **amber** caution,
**red** warning, **cyan** reference, **orange** the accent and the current
selection.

Themes are user-editable and the three built-ins — *Flight Deck*, *Night Ops*
and *Day Panel* — are ordinary entries in the theme library, not a privileged
kind. See "Custom themes" in [notes.md](notes.md).

## How to Install

### Windows

Download from the [Releases page](https://github.com/tMein1337/Hardline/releases).
Two forms of the same build are published:

- **Installer** — `hardline-<version>-windows-setup.exe`. Double-click and follow
  the prompts. If the build is unsigned you may get a SmartScreen warning; the
  release notes say whether it is signed.
- **Portable** — `hardline-<version>-windows.zip`. Extract it anywhere and run
  `hardline.exe`. Keep the folder together — the DLLs and data beside the `.exe`
  are part of the app, and the bare `.exe` will not run on its own.

Verify the download against the SHA-256 published in the release notes. Every
release is accompanied by the exact source it was built from.

### NixOS (flakes)

Run it without installing anything:

```
nix run github:tMein1337/Hardline
```

Or add it to your system. In your flake:

```nix
inputs.hardline.url = "github:tMein1337/Hardline";
# Do NOT set inputs.hardline.inputs.nixpkgs.follows — the pinned nixpkgs is
# required to build.
```

then, in your `nixosSystem` modules:

```nix
imports = [ inputs.hardline.nixosModules.default ];
programs.hardline.enable = true;
```

and `sudo nixos-rebuild switch`. Needs `hardware.graphics.enable = true` (usually
already on) to render. On a **non-NixOS** distro, launch through nixGL — see
[Run on Linux with Nix](#run-on-linux-with-nix). The overlay and more detail are
under [Consuming this flake](#consuming-this-flake).

### Run on Linux with Nix

The flake ships a hermetic package, so no toolchain, checkout or dev shell is
needed:

```
nix run github:tMein1337/Hardline
```

This targets **NixOS**, where the GPU driver lives at `/run/opengl-driver/lib`
(the wrapper puts it on the library path). On a **non-NixOS** distro a Nix-built
GL app cannot see the host driver, so launch it through
[nixGL](https://github.com/nix-community/nixGL):

```
nix run --impure github:nix-community/nixGL#nixGLIntel -- \
  nix run github:tMein1337/Hardline
```

(Use `#nixGLNvidia` / the variant matching your GPU.) For development,
`nix develop` gives the same build/run environment (see `NIX-PACKAGING.md`).

### Consuming this flake

Add it as an input and install the package, the overlay, or the NixOS module:

```nix
{
  inputs.hardline.url = "github:tMein1337/Hardline";
  # Do NOT set inputs.hardline.inputs.nixpkgs.follows — the pinned nixpkgs
  # carries the exact Flutter/source-builder versions the build needs. See below.

  outputs = { nixpkgs, hardline, ... }: {
    # a) directly:
    #    environment.systemPackages = [ hardline.packages.x86_64-linux.default ];
    # b) via the overlay:  nixpkgs.overlays = [ hardline.overlays.default ];
    #                      environment.systemPackages = [ pkgs.hardline ];
    # c) via the module:   imports = [ hardline.nixosModules.default ];
    #                      programs.hardline.enable = true;
  };
}
```

Two things worth knowing:

- **The nixpkgs pin is load-bearing.** The package builds only against the
  nixpkgs revision in this flake's lock (a specific Flutter/Dart, nixpkgs' pub
  source builders, the cargo hashes). Overriding it with `follows` will likely
  break the build, so don't — the overlay and module both inject the pin-built
  package for the same reason. The cost is a second nixpkgs' worth of runtime
  libs; the binary cache below is the mitigation.
- **Use the cache.** `nix run github:…` only honours the flake's substituter
  when you pass `--accept-flake-config` (or are a trusted user); without it you
  rebuild Flutter + libwebrtc from source.

## TODO

Outstanding work - verifications that still need a second client or a second
machine, one known bug, the Nix packaging items, platform support, and ideas -
is in [`TODOs.md`](TODOs.md).

## Notes

Why the code is shaped the way it is - protocol quirks, SDK limitations,
platform traps, and the decisions taken around them - is in
[`notes.md`](notes.md).

It covers the activity summary, accounts and verification, file attachments,
custom themes, and the voice architecture.
