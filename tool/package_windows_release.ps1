# SPDX-FileCopyrightText: 2026 Mein1337
# SPDX-License-Identifier: AGPL-3.0-or-later

<#
.SYNOPSIS
    Stages a complete, legally shippable Windows release directory.

.DESCRIPTION
    A Flutter Windows application is a directory, not a file. Publishing only
    hardline.exe produces a download that cannot start, because the engine DLL,
    the plugin DLLs and data\ (which carries icudtl.dat and the compiled Dart)
    all live beside it. This script copies the whole build output and adds the
    documents a release is required to carry:

      LICENSE                 the AGPL text
      THIRD_PARTY_NOTICES.md  every dependency and its own licence
      PRIVACY.md              what is stored and what is sent
      SOURCE.md               how to get the source for THIS binary
      README.txt              a short orientation for whoever unzips it

    SOURCE.md is copied with its version, tag and commit placeholders filled
    in, so the recipient of a binary can reach the exact commit it was built
    from. The script fails if any placeholder survives.

.PARAMETER Version
    Marketing version, e.g. 0.1.0. Must match pubspec.yaml.

.PARAMETER Tag
    Git tag for this release, e.g. v0.1.0.

.PARAMETER SkipBuildCheck
    Package whatever is already in the build directory instead of insisting it
    was produced from a clean tree. For local dry runs only.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tool\package_windows_release.ps1 -Version 0.1.0 -Tag v0.1.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Version,
    [Parameter(Mandatory = $true)] [string] $Tag,
    [switch] $SkipBuildCheck
)

$ErrorActionPreference = 'Stop'

function Fail($message) {
    Write-Error $message
    exit 1
}

# ── Locate the repository root ───────────────────────────────────────────
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not (Test-Path 'pubspec.yaml')) {
    Fail 'pubspec.yaml not found. Run this from inside the repository.'
}

# ── Sanity: the version must be the one that was built ───────────────────
$pubspecVersion = (Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
$pubspecMarketing = $pubspecVersion.Split('+')[0]
if ($pubspecMarketing -ne $Version) {
    Fail "pubspec.yaml says $pubspecMarketing but -Version is $Version. They must match."
}

# ── Sanity: the tree the binary came from ────────────────────────────────
if (-not $SkipBuildCheck) {
    # write_build_info.dart runs immediately before the build and rewrites
    # lib/core/build_info.dart, which is tracked so that a fresh clone compiles
    # without running the tool first. The documented procedure therefore always
    # arrives here with that one file modified. Anything else dirty means the
    # binary does not correspond to a commit, which is the failure worth
    # catching.
    $dirty = @(& git status --porcelain -- . ':(exclude)lib/core/build_info.dart')
    if ($dirty.Count -gt 0) {
        Fail "Working tree is not clean:`r`n$($dirty -join "`r`n")`r`nRelease from a tagged, clean checkout, or pass -SkipBuildCheck for a dry run."
    }
    $headTag = & git describe --tags --exact-match HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or $headTag -ne $Tag) {
        Fail "HEAD is not tagged $Tag. Tag the commit you are releasing first."
    }
}

$commit = (& git rev-parse HEAD).Trim()
if (-not $commit) { Fail 'Could not read the current commit.' }

# The About screen names the commit and tag it was stamped with, and that stamp
# is what a user follows back to the source. Checking it here is stronger than
# "is the tree clean": it catches a binary built before the tag was moved into
# place, or one left over from an earlier version entirely.
if (-not $SkipBuildCheck) {
    $stamp = Get-Content (Join-Path $root 'lib/core/build_info.dart') -Raw
    $stampCommit = [regex]::Match($stamp, "buildCommit = '([^']*)'").Groups[1].Value
    $stampTag = [regex]::Match($stamp, "buildTag = '([^']*)'").Groups[1].Value
    if ($stampCommit -ne $commit) {
        Fail "build_info.dart names commit '$stampCommit' but HEAD is '$commit'. The binary would send users to the wrong source. Run: dart run tool/write_build_info.dart, then rebuild."
    }
    if ($stampTag -ne $Tag) {
        Fail "build_info.dart names tag '$stampTag' but this release is '$Tag'. Run: dart run tool/write_build_info.dart, then rebuild."
    }
}

# ── Inputs ───────────────────────────────────────────────────────────────
$buildDir = Join-Path $root 'build\windows\x64\runner\Release'
if (-not (Test-Path $buildDir)) {
    Fail "No build output at $buildDir. Run: flutter build windows --release"
}
if (-not (Test-Path (Join-Path $buildDir 'hardline.exe'))) {
    Fail "hardline.exe not found in $buildDir. Did the build succeed?"
}
if (-not (Test-Path (Join-Path $buildDir 'data'))) {
    Fail "data\ not found in $buildDir. The build output is incomplete."
}

foreach ($doc in @('LICENSE', 'THIRD_PARTY_NOTICES.md', 'PRIVACY.md', 'SOURCE.md')) {
    if (-not (Test-Path (Join-Path $root $doc))) {
        Fail "$doc is missing from the repository root. A release must carry it."
    }
}

# ── Verify the notices are current before shipping them ──────────────────
& dart run tool/generate_third_party_notices.dart --check
if ($LASTEXITCODE -ne 0) {
    Fail 'THIRD_PARTY_NOTICES.md is out of date with pubspec.lock.'
}

# ── Stage ────────────────────────────────────────────────────────────────
$name = "hardline-$Version-windows"
$dist = Join-Path $root 'dist'
$stage = Join-Path $dist $name

if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

Write-Host "Copying the complete Windows runtime..."
Copy-Item -Path (Join-Path $buildDir '*') -Destination $stage -Recurse -Force

Write-Host "Adding release documents..."
Copy-Item (Join-Path $root 'LICENSE') $stage
Copy-Item (Join-Path $root 'THIRD_PARTY_NOTICES.md') $stage
Copy-Item (Join-Path $root 'PRIVACY.md') $stage

# Written without a byte-order mark. Windows PowerShell 5.1's `-Encoding utf8`
# emits one, and a BOM at the top of a text file a recipient may pipe through
# other tools is an avoidable surprise.
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

# SOURCE.md, with the placeholders resolved.
$source = Get-Content (Join-Path $root 'SOURCE.md') -Raw
$source = $source.Replace('VERSION_PLACEHOLDER', $Version)
$source = $source.Replace('TAG_PLACEHOLDER', $Tag)
$source = $source.Replace('COMMIT_PLACEHOLDER', $commit)
[System.IO.File]::WriteAllText((Join-Path $stage 'SOURCE.md'), $source, $utf8NoBom)

# -cmatch, not -match: PowerShell's default comparison is case-insensitive, and
# the word "placeholder" appears in ordinary prose. Only the upper-case token
# form is the failure being guarded against.
if ($source -cmatch '_PLACEHOLDER') {
    Fail 'A placeholder survived in SOURCE.md. Do not publish this package.'
}

$readme = @"
Hardline $Version
An independent desktop client for the Matrix protocol.

Run hardline.exe from this folder. Keep the folder together: the DLLs and the
data\ directory beside the executable are part of the application, and it will
not start without them.

Copyright (C) 2026 Mein1337
Licensed under the GNU Affero General Public License, version 3 or later.
This program comes with ABSOLUTELY NO WARRANTY.

  LICENSE                 the full licence text
  THIRD_PARTY_NOTICES.md  the components this is built from, and their licences
  PRIVACY.md              what is stored locally, and what is sent where
  SOURCE.md               how to obtain the source code for THIS build

Source for this exact build:
  https://github.com/tMein1337/hardline/tree/$commit

Release page:
  https://github.com/tMein1337/hardline/releases/tag/$Tag

Hardline is not affiliated with, endorsed by, or sponsored by The Matrix.org
Foundation C.I.C. or by Google LLC.
"@
[System.IO.File]::WriteAllText((Join-Path $stage 'README.txt'), $readme, $utf8NoBom)

# ── Archive ──────────────────────────────────────────────────────────────
$zip = Join-Path $dist "$name.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Write-Host "Compressing..."
Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal

# ── Checksums ────────────────────────────────────────────────────────────
$sums = Join-Path $dist 'SHA256SUMS.txt'
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
$exeHash = (Get-FileHash (Join-Path $stage 'hardline.exe') -Algorithm SHA256).Hash.ToLower()
[System.IO.File]::WriteAllLines($sums, @(
    "$hash  $name.zip",
    "$exeHash  $name/hardline.exe"
), $utf8NoBom)

Write-Host ''
Write-Host "Staged:    $stage"
Write-Host "Archive:   $zip"
Write-Host "Checksums: $sums"
Write-Host ''
Write-Host "  $name.zip"
Write-Host "  SHA-256: $hash"
Write-Host ''
Write-Host 'Still to do by hand:'
Write-Host '  1. Authenticode-sign and timestamp hardline.exe and the archive.'
Write-Host '  2. Re-run the checksums after signing - signing changes the file.'
Write-Host '  3. Attach the source archive to the same release page, with a'
Write-Host '     "Source code for this release" link beside the binary.'
Write-Host '  4. Test the archive on a clean Windows machine.'
