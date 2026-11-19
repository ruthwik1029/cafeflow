; CafeFlow Windows Desktop Demo Installer Script for Inno Setup 6
; Copyright (C) 2026 CafeFlow Technologies
; Standalone Demonstration Version (Offline / In-Memory Simulation)

#define MyAppName "CafeFlow (Demo Mode)"
#define MyAppVersion "1.0.0-demo"
#define MyAppPublisher "CafeFlow Technologies"
#define MyAppURL "https://cafeflow.app"
#define MyAppExeName "cafeflow.exe"
#define SourceBuildDir "..\..\build\windows\x64\runner\Release"

[Setup]
; Distinct AppId for Demo installation to isolate from production CafeFlow
AppId={{A78C53E2-29C3-48F8-9A70-877298642E9B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\CafeFlow-Demo
DisableProgramGroupPage=yes
DefaultGroupName=CafeFlow Demo
OutputDir=..\..\build\installer
OutputBaseFilename=CafeFlow-Demo-Setup
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
CloseApplications=yes
RestartApplications=no
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}

[Messages]
WelcomeLabel2=This will install [name] on your computer.%n%nThis is a standalone Demonstration Version featuring pre-populated offline sample data for restaurant operations (Admin, POS, and Kitchen).%n%nIt is recommended that you close all other applications before continuing.

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceBuildDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceBuildDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceBuildDir}\native_assets.json"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "{#SourceBuildDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

