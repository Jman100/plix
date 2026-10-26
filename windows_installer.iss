; Inno Setup Script for Plix Windows
#ifndef MyAppName
  #define MyAppName "Plix"
#endif
#ifndef MyAppVersion
  #define MyAppVersion "1.3.2"
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
#ifndef MyAppArch
  #define MyAppArch "x64"
#endif
#ifndef MyAppSourceDir
  #define MyAppSourceDir "build\windows\x64\runner\Release"
#endif
#ifndef MyAppOutputBaseFilename
  #define MyAppOutputBaseFilename "plix_windows"
#endif

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
#if MyAppArch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Flags: nowait; Check: WizardSilent
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent; Check: not WizardSilent
