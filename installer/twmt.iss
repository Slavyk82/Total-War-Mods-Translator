; Inno Setup script for Total War Mods Translator (twmt)
; Compiled by scripts/release.ps1. Version and paths are injected via /D defines:
;   ISCC.exe /DMyAppVersion=2.0.6 /DBuildDir="...Release" /DOutputDir="...dist" installer\twmt.iss
; The AppId GUID is fixed on purpose: it must stay identical across versions so
; Inno Setup treats new installs as upgrades (single entry in Add/Remove Programs).

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

; Build output (Flutter Windows release bundle: twmt.exe + DLLs + data\). Default
; is relative to this .iss file; release.ps1 always passes an absolute path.
#ifndef BuildDir
  #define BuildDir "..\build\windows\x64\runner\Release"
#endif

#ifndef OutputDir
  #define OutputDir "..\dist"
#endif

#define MyAppName "Total War Mods Translator"
#define MyAppExeName "twmt.exe"
#define MyAppPublisher "com.github.slavyk82"
#define MyAppURL "https://github.com/Slavyk82/Total-War-Mods-Translator"

[Setup]
AppId={{A7BEDEDE-B059-45E0-BFA5-5E041C7A7413}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}/releases
; Per-user install (no admin/UAC). With PrivilegesRequired=lowest, {autopf}
; resolves to %LOCALAPPDATA%\Programs (i.e. C:\Users\<user>\AppData\Local\Programs),
; matching the existing install location. Pass /ALLUSERS on the command line for a
; machine-wide install instead.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=commandline
DefaultDirName={autopf}\TWMT
DefaultGroupName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
DisableProgramGroupPage=yes
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; 64-bit only: the Flutter Windows runner targets x64.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=twmt-setup-{#MyAppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Whole release bundle, recursively (exe, DLLs, and the data\ folder).
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
