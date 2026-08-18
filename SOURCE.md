<!--
SPDX-FileCopyrightText: 2026 Mein1337
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Source code for this release

Hardline is free software under the **GNU AGPLv3 or later**. You are entitled to
the complete Corresponding Source for the exact binary you received.

The three values below identify the exact build this copy shipped with. They are
filled in by `tool/package_windows_release.ps1` as it stages the release
directory, and the script refuses to produce a package in which any of them is
still a token.

| | |
|---|---|
| **Version** | `VERSION_PLACEHOLDER` |
| **Git tag** | `TAG_PLACEHOLDER` |
| **Commit** | `COMMIT_PLACEHOLDER` |

## Where to get it

**Source archive for this exact version:**

<https://github.com/Mein1337/hardline/releases/tag/TAG_PLACEHOLDER>

**The tagged commit:**

<https://github.com/Mein1337/hardline/tree/COMMIT_PLACEHOLDER>

```sh
git clone https://github.com/Mein1337/hardline.git
cd hardline
git checkout TAG_PLACEHOLDER
```

That tag is kept available for as long as this binary is offered for download.
It is a fixed point, not a moving branch — do not use `main` if you want the
source that corresponds to this binary.

## What the archive contains

Everything needed to generate, install, run and modify this build, except
generally available unmodified system tools:

- `lib/`, `test/` — application source and tests
- `windows/`, `linux/`, `macos/`, `android/`, `ios/`, `web/` — platform runners
- `pubspec.yaml`, `pubspec.lock` — dependencies, with exact resolved versions
- `analysis_options.yaml`, `.metadata`
- `flake.nix`, `flake.lock` — reproducible development environment
- `tool/` — build, packaging and notice-generation scripts
- `RELEASING.md` — the exact procedure and toolchain versions this binary was
  built with

## Building it

The full procedure, including the pinned Flutter and Dart versions and the MSVC
requirements, is in `RELEASING.md` inside the archive. In short:

```sh
flutter pub get
flutter build windows --release
```

## Dependencies

`pubspec.lock` pins every Dart dependency to an exact version and content hash.
`THIRD_PARTY_NOTICES.md` lists all of them with their licenses reproduced in
full.

If a package ever becomes unavailable from pub.dev, a dependency source bundle
for this release is attached to the release page as
`hardline-TAG_PLACEHOLDER-dependencies.zip`.

## If any of this fails

If you cannot obtain the Corresponding Source for this binary from the links
above, that is a licensing bug and it will be fixed. Open an issue:

<https://github.com/Mein1337/hardline/issues>
