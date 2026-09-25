#define MyAppName "MAYELE +"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "GodFirst"
#define MyAppExeName "edupro_flutter_web.exe"

[Setup]
AppId={{B9E6449E-31C4-4F6E-9B83-47C1F3B02F9B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\MAYELE Plus
DefaultGroupName=MAYELE Plus
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
OutputDir=output
OutputBaseFilename=MAYELE_Plus_Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer un raccourci sur le Bureau"; GroupDescription: "Raccourcis :"; Flags: checkedonce

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\MAYELE +"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\MAYELE +"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Lancer MAYELE +"; Flags: nowait postinstall skipifsilent
