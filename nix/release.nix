# SPDX-FileCopyrightText: 2026 Mein1337
# SPDX-License-Identifier: AGPL-3.0-or-later

# The release tag this source is, for the About screen of the Nix build.
#
# A flake cannot see git tags: `self` carries the commit (`self.rev`) but not
# the ref it was fetched by, so `github:tMein1337/hardline/v0.3.0-nixos` and the
# same commit fetched by hash look identical to the build. The tag therefore has
# to be written into the source itself.
#
# It is `null` everywhere except in the one commit a Nix release tag points at:
# that commit is made on top of the release commit, changes only this line, and
# is pushed as the tag, never merged into main (RELEASING.md, "Nix release").
# CI enforces both halves: on a branch or pull request the tag must be `null`,
# and a pushed `*-nixos` tag must name itself here. A stamped tag on main would
# make every later build claim a release it is not, which is worse than
# `unknown`.
{
  tag = null;
}
