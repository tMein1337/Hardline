; SPDX-FileCopyrightText: 2026 Mein1337
; SPDX-License-Identifier: AGPL-3.0-or-later
;
; Inno Setup script for the Hardline Windows installer.
;
; This is Corresponding Source like everything else: the installer that ships
; beside a release must be reproducible from this file. Compile it with
; Inno Setup 6.3 or newer:
;
;   ISCC.exe /DMyAppVersion=0.1.1 /DStageDir=<staged folder> tool\hardline.iss
;
; tool\package_windows_release.ps1 passes those defines automatically; the
; defaults below exist only so the script can be opened and compiled by hand.
;
; The installer is a convenience, not the primary download. The portable zip
; carries the same files and needs nothing installed, so nothing here may be
; required for Hardline to run.

#define MyAppName "Hardline"
#define MyAppPublisher "Mein1337"
#define MyAppURL "https://github.com/tMein1337/hardline"
#define MyAppExeName "hardline.exe"

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#ifndef RepoRoot
  #define RepoRoot ".."
#endif
#ifndef StageDir
  #define StageDir RepoRoot + "\dist\hardline-" + MyAppVersion + "-windows"
#endif
#ifndef OutputDir
  #define OutputDir RepoRoot + "\dist"
#endif

[Setup]
; This GUID identifies the application to Windows across every version. It must
; never change: altering it makes an upgrade install alongside the old copy
; instead of replacing it, and leaves an orphaned Add/Remove Programs entry
; whose uninstaller points at files that are gone.
AppId={{8FE5F428-E27B-4EC5-AE5A-78B2D4E5FADB}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
AppCopyright=Copyright (C) 2026 Mein1337. Licensed under the GNU AGPLv3 or later.

; Install per-user by default so no administrator prompt appears. With
; PrivilegesRequired=lowest, {autopf} resolves to %LOCALAPPDATA%\Programs.
; A user who deliberately runs the installer elevated gets a machine-wide
; install instead, which is what PrivilegesRequiredOverridesAllowed permits.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={code:DefaultDirValue}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes

; The AGPL requires the licence to travel with the binary. Showing it during
; installation is not a substitute for the copy in the application directory,
; which the Files section installs as well.
LicenseFile={#RepoRoot}\LICENSE

OutputDir={#OutputDir}
OutputBaseFilename=hardline-{#MyAppVersion}-windows-setup
SetupIconFile={#RepoRoot}\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName} {#MyAppVersion}

Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

; Matches what the application itself supports: 64-bit, Windows 10 1809 or
; later. Refusing here produces a clear message instead of a missing-DLL
; dialog after the files are already on disk.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763

; Offer to close a running copy rather than failing on locked files, and
; restart it afterwards.
;
; AppMutex is what makes this reliable rather than best-effort. Restart Manager
; can only close what it can identify, and a Flutter window it fails to
; associate with these files is a locked DLL and a failed upgrade. The named
; mutex is created by the application itself (windows/runner/main.cpp), so the
; installer knows an instance is running before it touches anything.
CloseApplications=yes
RestartApplications=yes
AppMutex=HardlineRunningMutex
SetupMutex=HardlineSetupMutex

; The install directory is chosen by the code below, which finds the previous
; install in either registry hive. Warning about a directory that already
; exists would be warning about the expected case.
DirExistsWarning=no

; Version resource on setup.exe itself, so the installer is identifiable in
; Explorer and by any signature check applied to it later.
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoProductName={#MyAppName}
VersionInfoDescription={#MyAppName} {#MyAppVersion} setup
VersionInfoCopyright=Copyright (C) 2026 Mein1337. Licensed under the GNU AGPLv3 or later.

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
; Unchecked by default. A desktop shortcut nobody asked for is clutter.
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole staged directory, which package_windows_release.ps1 has already
; assembled and verified: the executable, the Flutter runtime, the bundled
; Visual C++ runtime, data\, and LICENSE, THIRD_PARTY_NOTICES.md, PRIVACY.md,
; SOURCE.md and README.txt. Installing anything less would ship a binary
; without its licence notices.
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

; Nothing is listed under [UninstallDelete] on purpose.
;
; Uninstalling removes the application, not the user's data. Messages,
; encryption keys, the account list and preferences live in
; %APPDATA%\Mein1337\Hardline and are deliberately left behind, so that
; uninstalling and reinstalling does not sign every account out or destroy the
; keys needed to read encrypted history. Anyone who wants that data gone can
; delete the directory, which PRIVACY.md documents.

[Code]

// Finding a previous install, in either registry hive.
//
// This is the fix for an upgrade landing beside the old copy instead of on top
// of it. PrivilegesRequired=lowest means setup normally runs unelevated, and
// Inno records a per-user install under HKCU and a machine-wide one under
// HKLM. An unelevated run only ever looks in HKCU -- so if the first install
// was elevated (or the user picked "for all users" once and not the next
// time), no previous install is found, the default program-files constant
// resolves to %LOCALAPPDATA%\Programs instead of C:\Program Files, and a
// *second* parallel copy is installed with its own Add/Remove entry. Same
// AppId, different hive, two Hardlines.
//
// So both hives are checked, and the directory the previous install actually
// used wins over whatever the default would have produced.
//
// Note the comments here are // rather than the Pascal { } form: a braced
// comment cannot contain a { } constant, because the first closing brace ends
// the comment and the rest is parsed as code.

const
  UninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{8FE5F428-E27B-4EC5-AE5A-78B2D4E5FADB}_is1';

// The install directory recorded by a previous install, or '' if there is none.
function PreviousInstallDir(): String;
var
  Path: String;
begin
  Result := '';

  // HKCU first: a per-user install is what this installer produces by
  // default, so it is the likelier of the two.
  if RegQueryStringValue(HKEY_CURRENT_USER, UninstallKey, 'InstallLocation', Path) then
  begin
    if Path <> '' then
    begin
      Result := RemoveBackslash(Path);
      Exit;
    end;
  end;

  // HKLM64 explicitly rather than HKLM: this is a 64-bit application, and a
  // 32-bit setup process reading plain HKLM would be redirected into
  // Wow6432Node and find nothing.
  if RegQueryStringValue(HKEY_LOCAL_MACHINE_64, UninstallKey, 'InstallLocation', Path) then
  begin
    if Path <> '' then
      Result := RemoveBackslash(Path);
  end;
end;

// Where to install, used by DefaultDirName.
//
// Falls back to the program-files default, which is what DefaultDirName said
// before this existed -- so a first install behaves exactly as it always did.
function DefaultDirValue(Param: String): String;
var
  Previous: String;
begin
  Previous := PreviousInstallDir();
  if Previous <> '' then
    Result := Previous
  else
    Result := ExpandConstant('{autopf}\Hardline');
end;
