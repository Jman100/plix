; Inno Setup Script for Plix Windows (Unified x64 & ARM64 Installer)
#ifndef MyAppName
  #define MyAppName "Plix"
#endif
#ifndef MyAppVersion
  #define MyAppVersion "1.4.1"
#endif
#ifndef MyAppPublisher
  #define MyAppPublisher "Plix"
#endif
#ifndef MyAppURL
  #define MyAppURL "https://plix.jman100.com/"
#endif
#ifndef MyAppExeName
  #define MyAppExeName "plix.exe"
#endif
#ifndef MyAppOutputBaseFilename
  #define MyAppOutputBaseFilename "plix_windows"
#endif

#define HasArm64 DirExists("build\windows\arm64\runner\Release")
#define HasX64 DirExists("build\windows\x64\runner\Release")

[Setup]
AppId={{E6F7A189-9B21-48C2-82BA-7744318F8E1C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={localappdata}\Programs\Plix
DisableProgramGroupPage=yes
OutputDir=build\installer
OutputBaseFilename={#MyAppOutputBaseFilename}
SetupIconFile=windows\runner\resources\app_icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
CloseApplications=yes
RestartApplications=yes
ArchitecturesAllowed=x64compatible arm64
ArchitecturesInstallIn64BitMode=x64compatible arm64

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
#if HasArm64 && HasX64
; Dual architecture packaging: install native binaries based on target hardware
Source: "build\windows\arm64\runner\Release\*"; DestDir: "{app}"; Check: IsArm64; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Check: not IsArm64; Flags: ignoreversion recursesubdirs createallsubdirs
#elif HasArm64
Source: "build\windows\arm64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
#elif HasX64
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
#else
; Fallback to generic release directory if neither specific directory exists
Source: "build\windows\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
#endif

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Flags: nowait; Check: WizardSilent
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent; Check: not WizardSilent

[Code]
function IsArm64: Boolean;
begin
  Result := (ProcessorArchitecture = paARM64);
end;
