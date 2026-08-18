<!--
SPDX-FileCopyrightText: 2026 Mein1337
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Contributing to Hardline

Thanks for looking. Before anything else, the part that has to be unambiguous:

## Licensing of contributions

**By submitting a contribution to this project, you agree that it is licensed
under the GNU Affero General Public License, version 3 or (at your option) any
later version — `AGPL-3.0-or-later` — unless explicitly agreed otherwise in
writing before the contribution is merged.**

"Contribution" means anything you submit for inclusion: code, tests,
documentation, translations, icons, themes, build files, or patches sent by any
route.

You also confirm that:

1. You wrote the contribution, or you otherwise have the right to submit it
   under `AGPL-3.0-or-later`.
2. If your employer has rights to work you produce, you have their permission to
   contribute it, or they have waived those rights.
3. You are not knowingly submitting code copied from a source whose license is
   incompatible with `AGPL-3.0-or-later`, and not from a decompiled or otherwise
   proprietary binary.

There is no copyright assignment. You keep the copyright in what you write. This
statement exists only so the project can keep distributing the whole work under
one license — without it, a repository with several contributors eventually
cannot answer the question "may this be released at all?".

### Adding a license header

New files that this project authors carry:

```dart
// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later
```

If you would like your own copyright line on files you author, add it as an
additional `SPDX-FileCopyrightText` line rather than replacing the existing one:

```dart
// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-FileCopyrightText: 2026 Your Name
// SPDX-License-Identifier: AGPL-3.0-or-later
```

Never add a copyright line to a file this project did not author, and never
replace a third-party file's notices with ours.

### Adding a dependency

A new dependency is a licensing decision, not just a technical one.

- Its license must be compatible with `AGPL-3.0-or-later` for distribution in a
  combined work.
- After changing `pubspec.yaml` or `pubspec.lock`, regenerate the notices:

  ```sh
  dart run tool/generate_third_party_notices.dart
  ```

  Commit the regenerated `THIRD_PARTY_NOTICES.md` with your change. CI and the
  release checklist run the same tool with `--check`.

## Reporting a security issue

Please do **not** open a public issue for a security problem. See
[`SECURITY.md`](SECURITY.md).

## Getting set up

Hardline is a Flutter application; Windows desktop is the primary target.

```sh
flutter pub get
flutter run -d windows
```

There is a Nix flake for a reproducible Linux dev shell — see
[`NIX-PACKAGING.md`](NIX-PACKAGING.md).

## Before you open a pull request

```sh
flutter analyze
flutter test
dart run tool/generate_third_party_notices.dart --check
```

All three must pass.

## House style

The codebase has a consistent voice, and matching it matters more than any
individual rule below.

- **Comments explain *why*, not *what*.** The code already says what it does. A
  comment earns its place by recording a decision, a constraint, or a trap —
  particularly one that is invisible at the call site.
- **Widgets never name a colour, a size or a font directly.** They read roles
  through `context.colors`, `context.metrics` and `context.text`.
  `lib/theme/palettes.dart` is the only file allowed to contain hex literals.
- **Do not reproduce another product's interface.** Generic patterns — a space
  rail, a room list, a message timeline, a participant list — are fine and
  expected. Copying a specific product's palette, proportions, iconography or
  motion is not, and will be rejected regardless of how well it is implemented.
  See Phase 4 of the release roadmap for the history behind that rule.
- **English**, to match the existing comments.
- Prefer a **small, focused pull request** with a message that says why.

## Interface design changes

Hardline's look is deliberate: a black panel, an orange accent, square-cut
markers, and instrument colours that mean the same thing everywhere — green for
normal, amber for caution, red for warning. If you are changing visual design,
say in the pull request how the change fits that language.
